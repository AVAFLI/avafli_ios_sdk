//
//  Avafli.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import UIKit

public enum Avafli {
    /// Internal (not private) so the demo-only extension can read it.
    internal static var configuration: AvafliConfiguration?
    private static let lock = NSLock()
    private static var registrationTask: Task<Void, Never>?
    private static var cachedGiveaway: GiveawayConfig?
    private static var cachedClaimedToday: Bool?
    private static var cachedStreakDay: Int?
    private static var cachedSDKConfig: SDKConfigResponse?
    private static var isRegistering = false
    /// Set when the backend reports the publisher is suspended / its API key is
    /// revoked. Cached so repeated auto-present attempts short-circuit without
    /// hitting the backend again. Reset on each `configure(_:)` so a re-enabled
    /// publisher recovers on the next launch.
    private static var isSuspended = false
    /// Backend truth for whether this person has confirmed email + consent
    /// (drives the unregistered impression cap for auto-present).
    private static var cachedEmailConsent: Bool?
    /// Abandoned verification-gated adoption reported by the backend
    /// (`adoptionPending` on the register / getActiveGiveaway response). The
    /// next experience open re-stages it (fresh code + code-entry screen).
    private static var cachedAdoptionPending: Bool?
    /// RTD opt-out — from the backend or the local persisted flag. Once true the
    /// experience is never auto-presented and `present` refuses.
    private static var cachedOptedOut = false
    private static var lifecycleObserver: NSObjectProtocol?

    // Auto-present persistence (per-bundle keys so app reinstalls of a different
    // publisher app on the same device don't cross-contaminate).
    private static var lastAutoPresentKey: String { "winr_last_auto_present_\(configuration?.bundleId ?? "")" }
    private static var unregisteredImpressionsKey: String { "winr_unregistered_impressions_\(configuration?.bundleId ?? "")" }
    private static var optedOutKey: String { "winr_opted_out_\(configuration?.bundleId ?? "")" }
    /// SPKI (public-key) pins for the backend hosted on *.cloudfunctions.net.
    ///
    /// These are Google Trust Services CA pins (NOT leaf-cert pins): pinning the CA
    /// public keys means we survive routine leaf-certificate rotation without shipping
    /// an SDK update, while still rejecting any chain not issued by GTS. The GTS roots
    /// are valid through ~2036, so these pins are stable long-term.
    ///   - GTS Root R1 (primary)
    ///   - GTS WR2 intermediate (backup)
    /// The `CertificatePinningDelegate` compares against the bare base64 SHA-256 SPKI
    /// hash, so the conventional `sha256/` prefix is stripped here.
    private static let gtsPins: [String] = [
        "sha256/hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=",
        "sha256/YPtHaftLw6/0vnc2BnNKGF54xiCA28WFcccjkA4ypCM=",
    ].map { $0.replacingOccurrences(of: "sha256/", with: "") }

    // MARK: - Availability (internal)

    /// Whether the Avafli experience is currently available.
    ///
    /// `false` when the SDK is not configured, or when the publisher's account
    /// is suspended / its API key has been revoked. Internal — used by the
    /// auto-open engine; suspension is only known after device registration
    /// completes.
    static var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return configuration != nil && !isSuspended
    }

    // MARK: - Presentation (internal — driven exclusively by auto-open)

    /// Presents the Avafli experience modally from the top-most view controller
    /// (auto-detected). Internal: the experience is opened only by the SDK's
    /// once-per-day auto-open engine, never by the host app.
    ///
    /// Returns `false` if the SDK is not configured or no presenting view
    /// controller could be found.
    @discardableResult
    static func present(completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)? = nil) -> Bool {
        guard let vc = topViewController() else {
            completion?(.failure(.noPresentingViewController))
            return false
        }
        return present(from: vc, completion: completion)
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var vc = root
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }

    // MARK: - Configuration

    /// Configures the SDK and registers the device with the backend.
    /// This is the single entry point for the SDK — call once at app launch.
    /// Fetches a Firebase custom token and caches the active giveaway.
    public static func configure(_ configuration: AvafliConfiguration) {
        lock.lock(); defer { lock.unlock() }
        self.configuration = configuration
        // Re-check suspension state on every configure — a previously suspended
        // publisher may have been re-enabled since the last launch.
        isSuspended = false
        // Restore the persisted RTD flag so an opted-out user stays suppressed
        // even before (or without) a network round-trip.
        cachedOptedOut = UserDefaults.standard.bool(forKey: optedOutKey)
        // Register the bundled Inter/Oswald faces for the V2 experience.
        AvafliV2Font.registerIfNeeded()
        Logger.shared.level = configuration.options.logging
        Logger.shared.log("AvafliSDK configured for \(configuration.environment)")
        Logger.shared.log(
            configuration.user.isGuest
                ? "Avafli user set: guest session (stable guest id will be minted)"
                : "Avafli user set: \(configuration.user.id)",
            level: .debug
        )

        // Register device in background, then attempt the once-a-day auto-present.
        registrationTask = Task {
            await registerDeviceIfNeeded(configuration: configuration)
            await MainActor.run { autoPresentIfEligible() }
        }

        // Auto-present on subsequent foregrounds too (covers the "app stayed in
        // memory overnight" case — a new day should re-open the experience).
        if lifecycleObserver == nil {
            lifecycleObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task {
                    await registrationTask?.value
                    await MainActor.run { autoPresentIfEligible() }
                }
            }
        }

        // Submit user profile (same as old setUser behavior)
        Task {
            await submitUserProfileIfNeeded(user: configuration.user)
        }
    }

    // MARK: - Auto-present (V2 experience: open once per day on app open)

    /// Presents the experience automatically, at most once per calendar day,
    /// when all conditions allow. Called after registration completes and on
    /// each app foreground. All short-circuits are silent by design.
    @MainActor
    private static func autoPresentIfEligible() {
        lock.lock()
        let config = configuration
        let suspended = isSuspended
        let optedOut = cachedOptedOut
        let sdkConfig = cachedSDKConfig
        let giveaway = cachedGiveaway
        let emailConsent = cachedEmailConsent
        lock.unlock()

        guard let config, !suspended, !optedOut else { return }
        let experience = sdkConfig?.experience
        guard experience?.autoOpenEnabled ?? true else { return }
        guard giveaway != nil else { return }
        _ = config

        // Once per day.
        let today = Self.dayString(Date())
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastAutoPresentKey) != today else { return }

        // Unregistered users (no confirmed email) see the auto-open at most N
        // times (default 3 per the MVP decision), then the SDK goes quiet until
        // they register. We evaluate the cap here but DEFER counting the
        // impression until presentation is actually committed (below) — mirroring
        // web/Flutter, which check presentability first and count second, so a
        // suppressed open never burns an impression.
        var pendingImpressionCount: Int?
        if emailConsent != true {
            let cap = experience?.unregisteredImpressionCap ?? 3
            let seen = defaults.integer(forKey: unregisteredImpressionsKey)
            guard seen < cap else {
                Logger.shared.log("Auto-present skipped: unregistered impression cap (\(cap)) reached", level: .debug)
                return
            }
            pendingImpressionCount = seen
        }

        // Don't stack on top of an already-presented experience, and make sure a
        // presenting view controller actually exists — otherwise nothing renders
        // and neither the impression nor the once-per-day flag may be committed.
        let top = topViewController()
        if top is AvafliExperienceViewController { return }
        guard top != nil else {
            Logger.shared.log("Auto-present skipped: no presenting view controller", level: .debug)
            return
        }

        // Committed to presenting — NOW count the unregistered impression and
        // mark today so a burned impression always corresponds to a real open.
        if let seen = pendingImpressionCount {
            defaults.set(seen + 1, forKey: unregisteredImpressionsKey)
        }
        defaults.set(today, forKey: lastAutoPresentKey)
        Logger.shared.log("Auto-presenting Avafli experience (first open of the day)", level: .info)
        present()
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    // MARK: - RTD Opt-out

    /// Right-To-Delete opt-out: tombstones the person on the backend (identity-wide,
    /// PII anonymized, email suppressed) and permanently silences the experience on
    /// this device. Wire this to the opt-out action in your privacy-policy flow.
    public static func optOut() async throws {
        guard let configuration = configuration else { throw AvafliError.notConfigured }
        let keychain = KeychainStorage()
        guard keychain.loadToken() != nil else { throw AvafliError.authenticationRequired }

        let network = makeNetworkClient(configuration: configuration, keychain: keychain)
        _ = try await network.send(OptOutRequest())

        lock.lock()
        cachedOptedOut = true
        lock.unlock()
        UserDefaults.standard.set(true, forKey: optedOutKey)
        Logger.shared.log("User opted out of Avafli (RTD) — experience permanently silenced", level: .info)
    }

    /// Presents the Avafli experience modally from the specified view controller.
    /// Internal: called only by the SDK's once-per-day auto-open engine.
    ///
    /// Returns `false` if the SDK is not configured or presentation is suppressed.
    @discardableResult
    static func present(
        from presentingViewController: UIViewController,
        completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)? = nil
    ) -> Bool {
        guard let configuration = configuration else {
            completion?(.failure(.notConfigured))
            return false
        }

        // If the publisher is suspended, do not present anything.
        lock.lock()
        let suspended = isSuspended
        let optedOut = cachedOptedOut
        lock.unlock()
        if suspended {
            Logger.shared.log("Avafli present suppressed: publisher suspended", level: .info)
            completion?(.failure(.serviceUnavailable))
            return false
        }
        // RTD: an opted-out person never sees the experience again.
        if optedOut {
            Logger.shared.log("Avafli present suppressed: user opted out (RTD)", level: .info)
            completion?(.failure(.optedOut))
            return false
        }

        let user = configuration.user
        var container = DependencyContainer(configuration: configuration, user: user)
        container.cachedGiveaway = cachedGiveaway
        container.cachedClaimedToday = cachedClaimedToday
        container.cachedStreakDay = cachedStreakDay
        container.sdkConfig = cachedSDKConfig
        container.adoptionPending = cachedAdoptionPending

        let viewModel = AvafliExperienceViewModel(
            container: container,
            presentingViewController: presentingViewController,
            completion: { result in
                // Update cached claim state so subsequent opens show the correct UI
                if case .success = result {
                    lock.lock()
                    cachedClaimedToday = true
                    lock.unlock()
                }
                completion?(result)
            }
        )

        // Branding is server-driven only — configured via admin or publisher dashboard.
        // Falls back to built-in defaults if server config hasn't loaded yet.
        let theme = AvafliBranding.from(serverConfig: cachedSDKConfig?.branding)

        let experienceVC = AvafliExperienceViewController(
            viewModel: viewModel,
            theme: theme
        )

        // The V2 drawer is rendered by SwiftUI itself (flush to the screen's
        // bottom + sides, rounded TOP corners only, host app dimmed behind) —
        // system sheets (esp. iOS 26's floating style) fight that shape.
        experienceVC.modalPresentationStyle = .overFullScreen
        experienceVC.modalTransitionStyle = .crossDissolve
        experienceVC.view.backgroundColor = .clear

        presentingViewController.present(experienceVC, animated: true, completion: nil)
        return true
    }

    // MARK: - Device Registration

    private static func registerDeviceIfNeeded(configuration: AvafliConfiguration) async {
        // Guard against re-entrant registration loops
        lock.lock()
        if isRegistering { lock.unlock(); return }
        isRegistering = true
        lock.unlock()
        defer { lock.lock(); isRegistering = false; lock.unlock() }

        let keychain = KeychainStorage()

        // If we already have a token, refresh if expired, then fetch giveaway
        if keychain.loadToken() != nil, keychain.loadUUID() != nil {
            // Proactively refresh if token is expired
            if keychain.isTokenExpired() {
                let refreshed = await refreshTokenIfNeeded(configuration: configuration, keychain: keychain)
                if refreshed == nil {
                    // Refresh failed and keychain was cleared — fall through to re-register
                    Logger.shared.log("Token refresh failed, re-registering device", level: .info)
                    // Don't return — fall through to new registration below
                } else {
                    // Fetch giveaway config with refreshed token
                    do {
                        let network = makeNetworkClient(configuration: configuration, keychain: keychain)
                        let response = try await network.send(GetActiveGiveawayRequest())
                        lock.lock()
                        cachedGiveaway = response.giveaway
                        cachedClaimedToday = response.claimedToday
                        cachedStreakDay = response.streakDay
                        cachedSDKConfig = response.sdkConfig
                        cachedEmailConsent = response.emailConsentStatus
                        cachedAdoptionPending = response.adoptionPending
                        if response.optedOut == true { cachedOptedOut = true }
                        lock.unlock()
                        persistOptOutIfNeeded()
                        prewarmPublisherArt()
                    } catch {
                        handleSuspensionIfNeeded(error)
                        Logger.shared.log("Failed to refresh giveaway: \(error)", level: .error)
                    }
                    return
                }
            } else {
                // Token not expired — fetch giveaway
                do {
                    let network = makeNetworkClient(configuration: configuration, keychain: keychain)
                    let response = try await network.send(GetActiveGiveawayRequest())
                    lock.lock()
                    cachedGiveaway = response.giveaway
                    cachedClaimedToday = response.claimedToday
                    cachedStreakDay = response.streakDay
                    cachedSDKConfig = response.sdkConfig
                    cachedEmailConsent = response.emailConsentStatus
                    cachedAdoptionPending = response.adoptionPending
                    if response.optedOut == true { cachedOptedOut = true }
                    lock.unlock()
                    persistOptOutIfNeeded()
                    prewarmPublisherArt()
                } catch {
                    handleSuspensionIfNeeded(error)
                    Logger.shared.log("Failed to refresh giveaway: \(error)", level: .error)
                }
                return
            }
        }

        let deviceFingerprint = await deviceIdentifier()

        let baseURL = cloudFunctionsBaseURL(for: configuration.environment)
        let network = URLSessionNetworkClient(
            baseURL: baseURL,
            apiKey: configuration.apiKey,
            enablePinning: true,
            pinnedKeyHashes: gtsPins
        )

        do {
            let request = RegisterDeviceRequest(
                apiKey: configuration.apiKey,
                deviceFingerprint: deviceFingerprint,
                bundleId: configuration.bundleId,
                timezone: TimeZone.current.identifier,
                platformOS: AvafliConstants.platformOS,
                sdkVersion: AvafliConstants.sdkVersion
            )
            let response = try await network.send(request)

            // Cache token, refresh token, and UUID in keychain
            keychain.saveToken(response.token)
            keychain.saveRefreshToken(response.refreshToken)
            keychain.saveUUID(response.uuid)

            lock.lock()
            cachedGiveaway = response.giveaway
            cachedClaimedToday = response.claimedToday
            cachedStreakDay = response.streakDay
            cachedSDKConfig = response.sdkConfig
            cachedAdoptionPending = response.adoptionPending
            if response.optedOut == true { cachedOptedOut = true }
            lock.unlock()
            persistOptOutIfNeeded()
            prewarmPublisherArt()

            Logger.shared.log("Device registered: \(response.uuid)", level: .info)
        } catch {
            handleSuspensionIfNeeded(error)
            Logger.shared.log("Device registration failed: \(error)", level: .error)
            // SDK gracefully degrades — will use cached data
        }
    }

    /// Decodes the publisher's remote art (prize hero + logo) into the image
    /// cache as soon as the SDK learns the giveaway config — at registration
    /// and on every giveaway refresh — so the drawer paints the prize card
    /// complete on its first frame instead of the art popping in after
    /// everything else. Mirrors the confetti-GIF prewarm; fire-and-forget, and
    /// a failure just falls back to loading at display time.
    private static func prewarmPublisherArt() {
        lock.lock()
        let prizeImageUrl = cachedGiveaway?.prizeImageUrl
        let logoUrl = cachedSDKConfig?.branding?.logoUrl
        lock.unlock()
        AvafliV2ImageWarmer.prewarm(prizeImageUrl)
        AvafliV2ImageWarmer.prewarm(logoUrl)
    }

    /// @internal — RETRY from the V2 session-expired state: re-runs the device
    /// registration handshake (token refresh when possible, else a fresh
    /// registerDevice) so the experience can reload with a live session.
    static func reregisterDevice(configuration: AvafliConfiguration) async {
        await registerDeviceIfNeeded(configuration: configuration)
    }

    /// @internal — Records that this person has confirmed their email, the
    /// moment a submit succeeds. The flag is otherwise only refreshed by
    /// `getActiveGiveaway`, which can be a whole session away; the auto-present
    /// engine reads it to decide whether the unregistered impression cap
    /// applies.
    static func markEmailConsentGranted() {
        lock.lock()
        cachedEmailConsent = true
        lock.unlock()
    }

    /// @internal — The abandoned adoption completed (code verified); clear the
    /// cached flag so subsequent opens in this session don't re-stage it.
    static func clearAdoptionPending() {
        lock.lock()
        cachedAdoptionPending = nil
        lock.unlock()
    }

    /// Persist the RTD flag whenever the backend reports it, so the suppression
    /// holds on future launches even offline.
    private static func persistOptOutIfNeeded() {
        lock.lock()
        let optedOut = cachedOptedOut
        lock.unlock()
        if optedOut {
            UserDefaults.standard.set(true, forKey: optedOutKey)
        }
    }

    /// If the given error indicates the publisher is suspended / API key revoked,
    /// cache that state so subsequent `present` calls short-circuit cleanly.
    private static func handleSuspensionIfNeeded(_ error: Error) {
        guard case AvafliError.serviceUnavailable = error else { return }
        lock.lock()
        isSuspended = true
        lock.unlock()
        Logger.shared.log("Publisher suspended — Avafli experience disabled", level: .info)
    }

    // MARK: - Token Refresh

    /// Builds a NetworkClient with auto-refresh on 401
    private static func makeNetworkClient(configuration: AvafliConfiguration, keychain: KeychainStorage) -> URLSessionNetworkClient {
        let baseURL = cloudFunctionsBaseURL(for: configuration.environment)
        return URLSessionNetworkClient(
            baseURL: baseURL,
            apiKey: configuration.apiKey,
            tokenProvider: { keychain.loadToken() },
            refreshHandler: { [configuration] in
                await refreshTokenIfNeeded(configuration: configuration, keychain: keychain)
            },
            enablePinning: true,
            pinnedKeyHashes: gtsPins
        )
    }

    @discardableResult
    private static func refreshTokenIfNeeded(configuration: AvafliConfiguration, keychain: KeychainStorage) async -> String? {
        guard let refreshToken = keychain.loadRefreshToken() else {
            Logger.shared.log("No refresh token available", level: .debug)
            return nil
        }

        let baseURL = cloudFunctionsBaseURL(for: configuration.environment)
        // Use a plain client (no refresh handler) to avoid infinite loop
        let plainNetwork = URLSessionNetworkClient(
            baseURL: baseURL,
            apiKey: configuration.apiKey,
            enablePinning: true,
            pinnedKeyHashes: gtsPins
        )

        do {
            let request = RefreshTokenRequest(refreshToken: refreshToken)
            let response = try await plainNetwork.send(request)
            keychain.saveToken(response.token)
            keychain.saveRefreshToken(response.refreshToken)
            Logger.shared.log("Token refreshed successfully", level: .debug)
            return response.token
        } catch {
            Logger.shared.log("Token refresh failed: \(error)", level: .error)
            // Clear stale tokens — the next configure() will re-register
            keychain.deleteAll()
            return nil
        }
    }

    private static func cloudFunctionsBaseURL(for environment: AvafliEnvironment) -> URL {
        switch environment {
        case .production:
            return URL(string: "https://us-central1-winr-9c11f.cloudfunctions.net")!
        }
    }

    private static func deviceIdentifier() async -> String {
        // Demo-only override (example app): "New demo user" stores a fresh
        // UUID so the next registration creates a brand-new backend user
        // instead of matching the stable identifierForVendor.
        if let key = demoFingerprintKey,
           let override = UserDefaults.standard.string(forKey: key) {
            return override
        }
        // Use identifierForVendor as device fingerprint
        return await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }

    // MARK: - Profile Data Submission

    private static func hasProfileData(_ user: AvafliUser) -> Bool {
        return !user.firstName.isEmpty || !user.lastName.isEmpty || user.phone != nil
    }

    private static func submitUserProfileIfNeeded(user: AvafliUser) async {
        guard let configuration = configuration else { return }
        
        let keychain = KeychainStorage()
        guard keychain.loadToken() != nil else {
            Logger.shared.log("No auth token available for profile submission", level: .debug)
            return
        }

        let network = makeNetworkClient(configuration: configuration, keychain: keychain)

        do {
            // Guest sessions get the SDK-minted stable id, so attribution always
            // carries a real identifier and never a publisher-fabricated one.
            // When the publisher later re-configures with a signed-in user, the
            // same call path overwrites pub_user_id with the real id — the Avafli
            // account itself is device-anchored and unaffected.
            let effectiveId = user.isGuest ? keychain.loadOrCreateGuestId() : user.id
            let request = SubmitUserProfileRequest(
                firstName: user.firstName,
                lastName: user.lastName,
                phone: user.phone,
                smsConsent: false,
                // Advertising-id collection removed Aug 2026: the SDK never shows the
                // App Tracking Transparency prompt and collects no IDFA. The backend
                // maid_id field remains for a future opt-in attribution feature.
                maidId: nil,
                publisherUserId: effectiveId
            )
            let _ = try await network.send(request)
            Logger.shared.log("User profile submitted successfully", level: .debug)
        } catch {
            Logger.shared.log("User profile submission failed: \(error)", level: .error)
        }
    }

    // MARK: - Right-to-be-Forgotten (GDPR/CCPA)
    //
    // `deleteAccount()` was REMOVED. It called a backend hard-delete that wiped the
    // user's entries, leaving no tombstone — so delete -> re-register -> claim again
    // the same day farmed unlimited entries. It also destroyed the records proving the
    // drawing was fair, and left prize-claim PII orphaned.
    //
    // Use `optOut()` instead. It is the correct erasure: identity-wide, PII scrubbed
    // everywhere including prize claims, tombstoned so it survives a reinstall, and
    // the experience stays permanently silenced on the device.

    // MARK: - Push Notifications

    /// Registers for push notifications (streak reminders).
    /// Requests notification permission, registers for APNs, and sends the token to the backend.
    /// No-op if `AvafliOptions.enablePushReminders` is false.
    public static func registerForPushNotifications() {
        guard let configuration = configuration else {
            Logger.shared.log("Cannot register for push: SDK not configured", level: .error)
            return
        }
        guard configuration.options.enablePushReminders else {
            Logger.shared.log("Push reminders disabled in options", level: .debug)
            return
        }
        PushNotificationManager.shared.register()
    }

    /// Forward APNs device token from AppDelegate to the SDK.
    /// Call from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    /// Server-sent reminders additionally require the FCM token — see
    /// `didReceiveFCMToken(_:)`; without it the SDK uses local reminders.
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    /// Forward the Firebase Messaging registration token so Avafli's backend can
    /// send streak reminders through your Firebase project. Call from
    /// `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)`.
    public static func didReceiveFCMToken(_ token: String) {
        PushNotificationManager.shared.didReceiveFCMToken(token)
    }

    /// Forward APNs registration failure from AppDelegate to the SDK.
    /// Call from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
    public static func didFailToRegisterForRemoteNotifications(error: Error) {
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
    }

    // MARK: - Internal access for tests

    static func _configurationForTests() -> AvafliConfiguration? { configuration }
    static func _userForTests() -> AvafliUser? { configuration?.user }
    static func _cachedGiveawayForTests() -> GiveawayConfig? { cachedGiveaway }
    static func _cachedEmailConsentForTests() -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return cachedEmailConsent
    }
    static func _resetEmailConsentForTests() {
        lock.lock(); cachedEmailConsent = nil; lock.unlock()
    }
}
