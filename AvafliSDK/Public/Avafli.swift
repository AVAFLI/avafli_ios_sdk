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

    // Publisher presentation control (3.1.4).
    /// True while the host is holding the once-a-day auto-open (`holdAutoOpen()`).
    /// Deliberately NOT reset by `configure(_:)` — a hold is set before it.
    private static var autoOpenHeld = false
    /// True when this session's `registerDevice` minted a brand-new user. The
    /// `.returningUsersOnly` mode skips the auto-open for exactly this session.
    private static var isNewUserThisSession = false
    /// Registration (or the giveaway refresh) has settled — success or
    /// failure — since the last `configure(_:)`. `present()` waits on it.
    private static var hasBooted = false
    /// The boot fetch died on a NETWORK-class error (offline / timeout). The
    /// next foreground re-runs it before the auto-open check, so a flaky cold
    /// open recovers without a relaunch. Nothing is marked or counted for a
    /// failed boot (the gate needs a cached giveaway).
    private static var bootRecoveryPending = false
    /// Single-flight token refresh shared by EVERY network client the SDK
    /// builds (see `refreshTokenIfNeeded` and `DependencyContainer`): a cold
    /// open fires 2–3 parallel authed calls with a dead token → parallel
    /// 401s → without this, parallel `refreshToken` calls with the same
    /// refresh token (the Sept 24 Skape cold-open failure).
    static let tokenRefreshGate = AvafliSingleFlight<String?>()
    /// Test seam: replaces the network registration step of `configure(_:)`.
    private static var registrationOverrideForTests: ((AvafliConfiguration) async -> Void)?

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

    // MARK: - Presentation (publisher-initiated)

    /// Presents the Avafli experience modally from the top-most view controller
    /// (auto-detected). Call it from a button, a screen, or the end of your
    /// onboarding — typically paired with `AvafliConfiguration.autoOpen` set
    /// to `.never` or `.returningUsersOnly`. Call on the main thread.
    ///
    /// Same guards as the auto-open: the SDK must be configured, the user not
    /// opted out, the publisher not suspended, an active giveaway must exist
    /// (otherwise a logged no-op) and the experience must not already be on
    /// screen (no-op). Unlike the auto-open it **bypasses** the once-per-day
    /// mark and the unregistered impression cap, and never counts an
    /// impression. When the experience closes it writes the same once-per-day
    /// mark the auto-open writes, so the auto-open won't double-pop that day.
    ///
    /// If device registration is still in flight the call is accepted and the
    /// experience is presented once registration settles (it never races
    /// `registerDevice`); if registration failed, `completion` receives
    /// `.giveawayNotActive` — nothing is ever thrown to the host.
    ///
    /// - Returns: `false` when presentation was refused right away (not
    ///   configured, opted out, suspended, no giveaway, no presenting view
    ///   controller); `true` when it was presented, deferred until
    ///   registration settles, or already on screen.
    @discardableResult
    public static func present(completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)? = nil) -> Bool {
        lock.lock()
        let configured = configuration != nil
        let booted = hasBooted
        let registration = registrationTask
        lock.unlock()
        guard configured else {
            Logger.shared.log("present() ignored: SDK not configured", level: .info)
            completion?(.failure(.notConfigured))
            return false
        }
        // Registration in flight — never race registerDevice; present once it
        // settles (the completion carries the outcome).
        if !booted, let registration {
            Logger.shared.log("present(): registration in flight — presenting once it settles", level: .debug)
            Task {
                await registration.value
                await MainActor.run { _ = presentIfPresentable(completion: completion) }
            }
            return true
        }
        return presentIfPresentable(completion: completion)
    }

    /// The publisher-initiated open once registration has settled: the
    /// auto-open's guards minus the once-per-day mark and the impression cap.
    @discardableResult
    private static func presentIfPresentable(completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)?) -> Bool {
        lock.lock()
        let suspended = isSuspended
        let optedOut = cachedOptedOut
        let giveaway = cachedGiveaway
        lock.unlock()
        if suspended {
            Logger.shared.log("present() ignored: publisher suspended", level: .info)
            completion?(.failure(.serviceUnavailable))
            return false
        }
        if optedOut {
            Logger.shared.log("present() ignored: user opted out (RTD)", level: .info)
            completion?(.failure(.optedOut))
            return false
        }
        guard giveaway != nil else {
            Logger.shared.log("present() ignored: no active giveaway (registration failed or nothing is running)", level: .info)
            completion?(.failure(.giveawayNotActive))
            return false
        }
        guard let vc = topViewController() else {
            Logger.shared.log("present() ignored: no presenting view controller", level: .info)
            completion?(.failure(.noPresentingViewController))
            return false
        }
        if vc is AvafliExperienceViewController {
            Logger.shared.log("present() ignored: experience already on screen", level: .debug)
            return true
        }
        Logger.shared.log("Presenting Avafli experience (publisher-initiated)", level: .info)
        return present(from: vc, markDayOnClose: true, completion: completion)
    }

    // MARK: - Auto-open control (publisher)

    /// Pauses the once-a-day auto-open.
    ///
    /// Call this before `configure(_:)` when your app has a boot flow (splash
    /// screen, auth gate, onboarding) the drawer must not appear over. While
    /// held nothing is burned — no once-per-day mark, no impression — and
    /// `present()` still works. Call `releaseAutoOpen()` once your main
    /// screen is up.
    public static func holdAutoOpen() {
        lock.lock()
        autoOpenHeld = true
        lock.unlock()
        Logger.shared.log("Auto-open held by host", level: .debug)
    }

    /// Releases a `holdAutoOpen()` and immediately re-runs the once-a-day
    /// auto-open eligibility check (which applies the effective auto-open
    /// mode). Safe to call before `configure(_:)`, and safe to call repeatedly.
    public static func releaseAutoOpen() {
        lock.lock()
        autoOpenHeld = false
        lock.unlock()
        Logger.shared.log("Auto-open released by host", level: .debug)
        Task { @MainActor in autoPresentIfEligible() }
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
        // Fresh boot: registration hasn't settled, and "new user this session"
        // is only ever set by this session's registerDevice. A host hold
        // (`holdAutoOpen()`) is intentionally left alone — it's set before us.
        hasBooted = false
        isNewUserThisSession = false
        bootRecoveryPending = false
        // Register the bundled Inter/Oswald faces for the V2 experience.
        AvafliV2Font.registerIfNeeded()
        Logger.shared.level = configuration.options.logging
        Logger.shared.log("AvafliSDK configured for \(configuration.environment)")

        // Offline resilience (launch item 15): connectivity monitor + persisted
        // same-day retry queue + offline analytics buffering.
        let offline = AvafliOfflineResilience.activate(bundleId: configuration.bundleId)
        offline.coordinator.retryHandler = { kind in
            await performOfflineRetry(kind)
        }
        // Next-launch flush of analytics buffered during a previous offline run.
        offline.flushAnalyticsBuffer()
        Logger.shared.log(
            configuration.user.isGuest
                ? "Avafli user set: guest session (stable guest id will be minted)"
                : "Avafli user set: \(configuration.user.id)",
            level: .debug
        )

        // Register device in background, then attempt the once-a-day auto-present.
        // Registration runs in EVERY auto-open mode — it stamps lastSeenAt /
        // sdk_version / platform (DAU/MAU); the mode only gates the drawer.
        registrationTask = Task {
            if let override = registrationOverrideForTests {
                await override(configuration)
            } else {
                await registerDeviceIfNeeded(configuration: configuration)
            }
            markBooted()
            await MainActor.run { autoPresentIfEligible() }
            // Launch trigger for the offline retry queue: a pending same-day
            // claim persisted before a crash/kill retries now that the
            // session is (re)established.
            AvafliOfflineResilience.shared?.coordinator.noteLaunch()
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
                    // Boot resilience: a boot fetch that died on a flaky
                    // network is re-run now, BEFORE the auto-open check.
                    await recoverBootIfNeeded()
                    await MainActor.run { autoPresentIfEligible() }
                    // Foreground trigger for the offline retry queue +
                    // buffered-analytics flush.
                    AvafliOfflineResilience.shared?.coordinator.noteForeground()
                    AvafliOfflineResilience.shared?.flushAnalyticsBuffer()
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
        let held = autoOpenHeld
        let newUser = isNewUserThisSession
        lock.unlock()

        guard let config, !suspended, !optedOut else { return }
        // Host is holding the auto-open (boot flow) — defer; nothing is burned.
        if held {
            Logger.shared.log("Auto-present deferred: host is holding auto-open", level: .debug)
            return
        }
        // Effective mode = most restrictive of the server kill switch
        // (autoOpenEnabled), the server autoOpenMode and the client autoOpen.
        let experience = sdkConfig?.experience
        let mode = AvafliAutoOpen.effective(
            client: config.autoOpen,
            serverEnabled: experience?.autoOpenEnabled,
            serverMode: experience?.resolvedAutoOpenMode ?? .always
        )
        guard autoOpenAllowed(mode: mode, isNewUserThisSession: newUser) else {
            Logger.shared.log("Auto-present skipped: mode \(mode)\(newUser ? " (new user this session)" : "")", level: .debug)
            return
        }
        guard giveaway != nil else { return }

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
        guard let top = topViewController() else {
            Logger.shared.log("Auto-present skipped: no presenting view controller", level: .debug)
            return
        }
        if top is AvafliExperienceViewController { return }

        // Committed to presenting — NOW count the unregistered impression and
        // mark today so a burned impression always corresponds to a real open.
        if let seen = pendingImpressionCount {
            defaults.set(seen + 1, forKey: unregisteredImpressionsKey)
        }
        defaults.set(today, forKey: lastAutoPresentKey)
        Logger.shared.log("Auto-presenting Avafli experience (first open of the day)", level: .info)
        present(from: top)
    }

    /// The mode-based part of the auto-open gate (pure; unit-tested).
    /// `.returningUsersOnly` skips exactly the session in which this device
    /// registered for the first time; an older backend that never reports
    /// `isNewUser` leaves the flag false → treated as returning.
    static func autoOpenAllowed(mode: AvafliAutoOpen, isNewUserThisSession: Bool) -> Bool {
        switch mode {
        case .always: return true
        case .returningUsersOnly: return !isNewUserThisSession
        case .never: return false
        }
    }

    /// A publisher-initiated `present()` writes the once-per-day mark when the
    /// experience CLOSES (the auto-open writes it when it commits to opening),
    /// so a later auto-open the same day doesn't double-pop.
    private static func markAutoPresentedToday() {
        UserDefaults.standard.set(dayString(Date()), forKey: lastAutoPresentKey)
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
    /// Internal: reached by the once-per-day auto-open engine and by the
    /// public `present()`. `markDayOnClose` is the latter's once-per-day mark
    /// (written when the experience closes).
    ///
    /// Returns `false` if the SDK is not configured or presentation is suppressed.
    @discardableResult
    static func present(
        from presentingViewController: UIViewController,
        markDayOnClose: Bool = false,
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
        if markDayOnClose {
            experienceVC.onDismiss = { markAutoPresentedToday() }
        }

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
                        bootRecoveryPending = false
                        lock.unlock()
                        persistOptOutIfNeeded()
                        prewarmPublisherArt()
                    } catch {
                        handleSuspensionIfNeeded(error)
                        noteBootFailure(error)
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
                    bootRecoveryPending = false
                    lock.unlock()
                    persistOptOutIfNeeded()
                    prewarmPublisherArt()
                } catch {
                    handleSuspensionIfNeeded(error)
                    noteBootFailure(error)
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
            // First-ever registration of this device → `.returningUsersOnly`
            // skips this session's auto-open. Absent (older backend) → returning.
            isNewUserThisSession = response.isNewUser == true
            bootRecoveryPending = false
            lock.unlock()
            persistOptOutIfNeeded()
            prewarmPublisherArt()

            Logger.shared.log("Device registered: \(response.uuid)\(response.isNewUser == true ? " (new user)" : "")", level: .info)
            AvafliOfflineResilience.shared?.coordinator.clear(.registration)
        } catch {
            handleSuspensionIfNeeded(error)
            noteBootFailure(error)
            Logger.shared.log("Device registration failed: \(error)", level: .error)
            // NETWORK-class failure (offline/timeout): queue a same-day retry
            // on connectivity regain / foreground / capped backoff. Backend
            // rejections are NOT queued — they'd only be rejected again.
            if AvafliNetworkErrorClassifier.isRetriable(error) {
                AvafliOfflineResilience.shared?.coordinator.enqueue(.registration)
            }
            // SDK gracefully degrades — will use cached data
        }
    }

    // MARK: - Boot resilience

    /// A NETWORK-class boot failure (offline / timeout / connection dropped)
    /// is re-run on the next foreground; backend rejections are not — they'd
    /// only be rejected again.
    private static func noteBootFailure(_ error: Error) {
        guard AvafliNetworkErrorClassifier.isRetriable(error) else { return }
        lock.lock()
        bootRecoveryPending = true
        lock.unlock()
    }

    private static func markBooted() {
        lock.lock()
        hasBooted = true
        lock.unlock()
    }

    /// The configuration to re-run a failed boot with, or nil when nothing is pending.
    private static func pendingBootRecoveryConfiguration() -> AvafliConfiguration? {
        lock.lock(); defer { lock.unlock() }
        return bootRecoveryPending ? configuration : nil
    }

    /// Re-runs the registration / giveaway fetch after a failed boot (the
    /// foreground trigger). `registerDeviceIfNeeded` picks the right leg —
    /// token refresh, giveaway refresh or a fresh registerDevice.
    private static func recoverBootIfNeeded() async {
        guard let config = pendingBootRecoveryConfiguration() else { return }
        Logger.shared.log("Boot fetch failed earlier — retrying on foreground", level: .info)
        await registerDeviceIfNeeded(configuration: config)
    }

    // MARK: - Offline retry execution

    /// @internal — a claim transport failure in the experience. Queues a
    /// same-day automatic retry when (and only when) it was a NETWORK-class
    /// failure; backend rejections never queue.
    static func enqueueOfflineClaimRetry(for error: Error) {
        guard AvafliNetworkErrorClassifier.isRetriable(error) else { return }
        AvafliOfflineResilience.shared?.coordinator.enqueue(.claim)
    }

    /// @internal — today's claim is definitively recorded on the backend;
    /// drop any queued claim retry.
    static func clearOfflineClaimRetry() {
        AvafliOfflineResilience.shared?.coordinator.clear(.claim)
    }

    /// Executes one queued offline retry.
    ///
    /// Duplicate-claim safety (verified in the backend claim transaction):
    /// `claimDailyEntries` dedups server-side by the canonical user's
    /// local-day entry window and `daily_last_claimed === today`, throwing an
    /// `already-exists` callable error — so a duplicate retry can never
    /// double-grant, and an already-claimed rejection is treated as SUCCESS.
    static func performOfflineRetry(_ kind: AvafliPendingIntent.Kind) async -> AvafliRetryOutcome {
        guard let configuration = configuration else { return .retriableFailure }
        switch kind {
        case .registration:
            await registerDeviceIfNeeded(configuration: configuration)
            guard KeychainStorage().loadToken() != nil else { return .retriableFailure }
            // The boot that failed never reached the auto-open check — run it
            // now that the session exists (a backgrounded app has no
            // foreground-active scene and simply skips, burning nothing).
            await MainActor.run { autoPresentIfEligible() }
            return .success

        case .claim:
            let keychain = KeychainStorage()
            guard keychain.loadToken() != nil else {
                // Registration has to land first — its own retry restores the
                // session; keep the claim queued for the next trigger.
                return .retriableFailure
            }
            let network = makeNetworkClient(configuration: configuration, keychain: keychain)
            do {
                let response = try await network.send(ClaimDailyEntriesRequest())
                lock.lock()
                cachedClaimedToday = true
                cachedStreakDay = response.streakDay
                lock.unlock()
                // Publisher-facing analytics for the recovered claim (through
                // the buffering wrapper, like every other emission).
                let analytics = AvafliOfflineResilience.shared?
                    .analyticsAdapter(wrapping: configuration.options.analyticsAdapter)
                analytics?.track(
                    event: AvafliAnalyticsEvent.dailyEntryClaimed,
                    properties: ["day": response.streakDay, "entries": response.entries, "recovered_offline": true]
                )
                // An open experience reconciles via its existing load() path.
                NotificationCenter.default.post(
                    name: AvafliOfflineResilience.claimRetrySucceededNotification,
                    object: nil
                )
                Logger.shared.log("Offline claim retry recorded today's entry (+\(response.entries))", level: .info)
                return .success
            } catch {
                if Self.isAlreadyClaimedRejection(error) {
                    // Server-side daily dedup already holds today's entry —
                    // the original attempt (or another device) landed.
                    lock.lock()
                    cachedClaimedToday = true
                    lock.unlock()
                    Logger.shared.log("Offline claim retry: already claimed — treating as success", level: .info)
                    return .success
                }
                return AvafliNetworkErrorClassifier.isRetriable(error) ? .retriableFailure : .permanentFailure
            }
        }
    }

    /// The backend's `already-exists` dedup messages: "Already claimed daily
    /// entries today" / "Already claimed today" / "You've already entered
    /// today on another device…".
    static func isAlreadyClaimedRejection(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        return text.contains("already claimed") || text.contains("already entered today")
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

    /// Single-flight: concurrent callers share ONE refresh (see `tokenRefreshGate`).
    @discardableResult
    private static func refreshTokenIfNeeded(configuration: AvafliConfiguration, keychain: KeychainStorage) async -> String? {
        await tokenRefreshGate.run {
            await performTokenRefresh(configuration: configuration, keychain: keychain)
        }
    }

    private static func performTokenRefresh(configuration: AvafliConfiguration, keychain: KeychainStorage) async -> String? {
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
    /// Replaces the network registration step of `configure(_:)` (nil restores it).
    static func _setRegistrationOverrideForTests(_ override: ((AvafliConfiguration) async -> Void)?) {
        lock.lock(); registrationOverrideForTests = override; lock.unlock()
    }
    static func _awaitRegistrationForTests() async {
        await _registrationTaskForTests()?.value
    }
    private static func _registrationTaskForTests() -> Task<Void, Never>? {
        lock.lock(); defer { lock.unlock() }
        return registrationTask
    }
    static func _isAutoOpenHeldForTests() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return autoOpenHeld
    }
    static func _resetPresentationStateForTests() {
        lock.lock()
        configuration = nil
        registrationTask = nil
        cachedGiveaway = nil
        cachedSDKConfig = nil
        autoOpenHeld = false
        isNewUserThisSession = false
        hasBooted = false
        bootRecoveryPending = false
        lock.unlock()
    }
}
