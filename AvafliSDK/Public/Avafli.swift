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
    /// RTD opt-out — from the backend or the local persisted flag. While true
    /// the experience is never auto-presented and `present` refuses. It lifts
    /// 24 hours after the deletion (3.2.0 — see `restoreOptOutLocked`).
    private static var cachedOptedOut = false
    /// A lapsed opt-out was just lifted and a fresh registration went out.
    /// If its response STILL reports the opt-out, the next try waits at least
    /// `optOutRecheckInterval` — never a loop. Cleared by that response.
    private static var rejoinAttempted = false
    /// The latest registerDevice / getActiveGiveaway response carried a
    /// `prizeClaim` still waiting to be submitted (`status == "pending"`).
    /// While true the auto-open is not held back by the once-per-day mark —
    /// a winner must always be able to get back to their claim.
    private static var cachedPendingPrizeClaim = false
    /// `configure(_:)` ran and no auto-open check has had its say yet. The
    /// first check of a cold launch reopens a pending claim regardless of the
    /// 30-minute throttle; later (foreground) checks respect it.
    private static var launchAutoOpenPending = false
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
    /// Test seam: the clock the 24-hour rejoin runs on.
    private static var nowOverrideForTests: (() -> Date)?
    /// Test seam: stands in for putting the experience on screen.
    private static var presentationOverrideForTests: ((PresentationTrigger) -> Void)?

    /// What put the experience on screen.
    enum PresentationTrigger: Equatable {
        /// The once-a-day auto-open.
        case autoDaily
        /// The auto-open of a pending prize claim (bypasses the daily mark).
        case autoPendingClaim
        /// `Avafli.present()`.
        case publisher
    }

    /// A pending claim reopens on every cold launch, and on a foreground only
    /// when this long has passed since it was last put in front of the winner.
    static let pendingClaimReopenInterval: TimeInterval = 30 * 60

    /// How long "Delete my data" blocks this device from registering again
    /// (Rules §9, Terms §5.2, Privacy §6).
    static let optOutRejoinInterval: TimeInterval = 24 * 60 * 60
    /// The wait after the server refused a rejoin without naming a later time.
    static let optOutRecheckInterval: TimeInterval = 15 * 60

    // Auto-present persistence (per-bundle keys so app reinstalls of a different
    // publisher app on the same device don't cross-contaminate).
    private static var lastAutoPresentKey: String { "winr_last_auto_present_\(configuration?.bundleId ?? "")" }
    private static var unregisteredImpressionsKey: String { "winr_unregistered_impressions_\(configuration?.bundleId ?? "")" }
    private static var optedOutKey: String { "winr_opted_out_\(configuration?.bundleId ?? "")" }
    /// When the opt-out lifts, as seconds since 1970 (stored beside the flag).
    private static var optedOutUntilKey: String { "winr_opted_out_until_\(configuration?.bundleId ?? "")" }
    /// When a pending prize claim was last put on screen, as seconds since
    /// 1970. Its own key — the daily mark is never used for this throttle.
    private static var lastClaimAutoPresentKey: String { "winr_last_claim_auto_present_\(configuration?.bundleId ?? "")" }
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
    /// or a prize claim must be pending (otherwise a logged no-op) and the
    /// experience must not already be on screen (no-op). With a prize claim
    /// pending it opens on the winner splash. Unlike the auto-open it **bypasses** the once-per-day
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
        let pendingClaim = cachedPendingPrizeClaim
        let presentationOverride = presentationOverrideForTests
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
        // A pending prize claim can outlive its giveaway — the winner flow
        // still opens (on the winner splash).
        guard giveaway != nil || pendingClaim else {
            Logger.shared.log("present() ignored: no active giveaway (registration failed or nothing is running)", level: .info)
            completion?(.failure(.giveawayNotActive))
            return false
        }
        if let presentationOverride {
            if pendingClaim { notePendingClaimShown() }
            presentationOverride(.publisher)
            return true
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
        if pendingClaim { notePendingClaimShown() }
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
        // even before (or without) a network round-trip — unless its 24 hours
        // are up, in which case the old session is cleared here and the
        // registration below runs for a brand-new participant.
        rejoinAttempted = false
        restoreOptOutLocked()
        // Fresh boot: registration hasn't settled, and "new user this session"
        // is only ever set by this session's registerDevice. A host hold
        // (`holdAutoOpen()`) is intentionally left alone — it's set before us.
        hasBooted = false
        isNewUserThisSession = false
        bootRecoveryPending = false
        launchAutoOpenPending = true
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
            await runRegistration(configuration: configuration)
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
                    // 24-hour rejoin: an opt-out that lapsed while the app
                    // stayed in memory lifts on this foreground.
                    await rejoinIfOptOutLapsed()
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
    ///
    /// A PENDING PRIZE CLAIM (3.2.0) changes the rules: the once-per-day
    /// mark, the unregistered impression cap and `returningUsersOnly` no
    /// longer hold the drawer back — see `autoPresentPendingClaim`.
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
        let pendingClaim = cachedPendingPrizeClaim
        let presentationOverride = presentationOverrideForTests
        lock.unlock()

        guard let config, !suspended, !optedOut else { return }
        // Host is holding the auto-open (boot flow) — defer; nothing is burned.
        if held {
            Logger.shared.log("Auto-present deferred: host is holding auto-open", level: .debug)
            return
        }
        if pendingClaim {
            autoPresentPendingClaim(config: config, experience: sdkConfig?.experience, presentationOverride: presentationOverride)
            return
        }
        // This check has had its say: whatever a later one decides, it is
        // no longer the cold launch's.
        if presentationOverride != nil || topViewController() != nil {
            consumeLaunchAutoOpen()
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
        let top = topViewController()
        if presentationOverride == nil {
            guard let top else {
                Logger.shared.log("Auto-present skipped: no presenting view controller", level: .debug)
                return
            }
            if top is AvafliExperienceViewController { return }
        }

        // Committed to presenting — NOW count the unregistered impression and
        // mark today so a burned impression always corresponds to a real open.
        if let seen = pendingImpressionCount {
            defaults.set(seen + 1, forKey: unregisteredImpressionsKey)
        }
        defaults.set(today, forKey: lastAutoPresentKey)
        Logger.shared.log("Auto-presenting Avafli experience (first open of the day)", level: .info)
        if let presentationOverride {
            presentationOverride(.autoDaily)
        } else if let top {
            present(from: top)
        }
    }

    /// The auto-open while a prize claim is pending. A winner who closed the
    /// drawer must be able to get back to their claim (the claim window is 72
    /// hours), so this BYPASSES the once-per-day mark, the unregistered
    /// impression cap (and counts no impression) and `returningUsersOnly`.
    /// It still RESPECTS the host's hold, opt-out and suspension (checked by
    /// the caller), the server kill switch and mode `never` — a publisher on
    /// `never` owns the timing and opens the winner flow with `present()`.
    ///
    /// Not a nag: it opens on every cold launch, and on a foreground only
    /// when `pendingClaimReopenInterval` has passed since the claim was last
    /// on screen.
    @MainActor
    private static func autoPresentPendingClaim(
        config: AvafliConfiguration,
        experience: ExperienceConfig?,
        presentationOverride: ((PresentationTrigger) -> Void)?
    ) {
        let mode = AvafliAutoOpen.effective(
            client: config.autoOpen,
            serverEnabled: experience?.autoOpenEnabled,
            serverMode: experience?.resolvedAutoOpenMode ?? .always
        )
        guard mode != .never else {
            Logger.shared.log("Auto-present skipped: prize claim pending, but auto-open is off (mode never / kill switch)", level: .debug)
            return
        }
        let top = topViewController()
        if presentationOverride == nil {
            guard let top else {
                Logger.shared.log("Auto-present skipped: no presenting view controller", level: .debug)
                return
            }
            if top is AvafliExperienceViewController { return }
        }

        let isLaunch = consumeLaunchAutoOpen()
        let defaults = UserDefaults.standard
        let now = currentDate()
        let lastShown = defaults.object(forKey: lastClaimAutoPresentKey) as? Double
        guard pendingClaimShouldReopen(isLaunch: isLaunch, lastShown: lastShown.map(Date.init(timeIntervalSince1970:)), now: now) else {
            Logger.shared.log("Auto-present skipped: prize claim pending, shown less than 30 minutes ago", level: .debug)
            return
        }

        // Committed. Its own timestamp drives the throttle; the daily mark is
        // written as for any open, so once the claim is submitted the normal
        // once-per-day rule picks up where this left off.
        notePendingClaimShown()
        defaults.set(Self.dayString(Date()), forKey: lastAutoPresentKey)
        Logger.shared.log("Auto-presenting Avafli experience (prize claim pending)", level: .info)
        if let presentationOverride {
            presentationOverride(.autoPendingClaim)
        } else if let top {
            present(from: top)
        }
    }

    /// The pending-claim throttle (pure; unit-tested).
    static func pendingClaimShouldReopen(isLaunch: Bool, lastShown: Date?, now: Date) -> Bool {
        if isLaunch { return true }
        guard let lastShown else { return true }
        // A stamp from the future (the device clock was set back) must never
        // hold the claim back: the throttle counts as expired.
        guard now >= lastShown else { return true }
        return now.timeIntervalSince(lastShown) >= pendingClaimReopenInterval
    }

    /// Takes the cold launch's say, once registration has settled. Returns
    /// whether this check is the cold launch's. A boot that died on the
    /// network keeps it for the check that follows the recovery.
    @discardableResult
    private static func consumeLaunchAutoOpen() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard hasBooted, !bootRecoveryPending, launchAutoOpenPending else { return false }
        launchAutoOpenPending = false
        return true
    }

    /// Stamps "the pending claim was put in front of the winner just now".
    private static func notePendingClaimShown() {
        guard configuration != nil else { return }
        UserDefaults.standard.set(currentDate().timeIntervalSince1970, forKey: lastClaimAutoPresentKey)
    }

    /// @internal — what the experience learned from its own getActiveGiveaway
    /// (or from a submitted claim): whether a prize claim is still pending.
    /// `onScreen` = the winner flow is showing right now.
    static func notePendingPrizeClaim(_ pending: Bool, onScreen: Bool = false) {
        lock.lock()
        cachedPendingPrizeClaim = pending
        lock.unlock()
        if pending, onScreen { notePendingClaimShown() }
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

    /// Right-To-Delete opt-out: erases the person on the backend (identity-wide,
    /// PII anonymized, entries and streaks forfeited) and silences the experience
    /// on this device. For 24 hours that email and this device cannot register;
    /// after that the person may join again as a brand-new participant with no
    /// connection to the old profile. Wire this to the opt-out action in your
    /// privacy-policy flow.
    public static func optOut() async throws {
        guard let configuration = configuration else { throw AvafliError.notConfigured }
        let keychain = KeychainStorage()
        guard keychain.loadToken() != nil else { throw AvafliError.authenticationRequired }

        let network = makeNetworkClient(configuration: configuration, keychain: keychain)
        let response = try await network.send(OptOutRequest())

        recordOptOut(serverUntil: response.optedOutUntil, refusedRejoin: false)
        Logger.shared.log("User opted out of Avafli (RTD) — experience silenced; rejoin possible after 24 hours", level: .info)
    }

    // MARK: - 24-hour rejoin after deletion (3.2.0)

    private static func currentDate() -> Date {
        nowOverrideForTests?() ?? Date()
    }

    /// Restores the persisted opt-out and lifts it when its time is up.
    /// Call with `lock` HELD. A flag cached by an older build carries no time:
    /// it is given "first seen + 24 hours" here and lifts a day later.
    /// Returns true when the opt-out was lifted by this call.
    @discardableResult
    private static func restoreOptOutLocked() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: optedOutKey) else {
            cachedOptedOut = false
            return false
        }
        let now = currentDate().timeIntervalSince1970
        let until: Double
        if let stored = defaults.object(forKey: optedOutUntilKey) as? Double {
            until = stored
        } else {
            until = now + optOutRejoinInterval
            defaults.set(until, forKey: optedOutUntilKey)
        }
        guard now >= until else {
            cachedOptedOut = true
            return false
        }
        clearSessionForRejoinLocked()
        rejoinAttempted = true
        Logger.shared.log("Opt-out lapsed (24 hours) — old session cleared; registering as a new participant", level: .info)
        return true
    }

    /// Drops the opt-out and EVERY piece of the old session, so the next
    /// registration starts a participant with no connection to the old
    /// profile. The device id (identifierForVendor) is not the SDK's to clear
    /// and stays. Call with `lock` HELD.
    private static func clearSessionForRejoinLocked() {
        let bundleId = configuration?.bundleId ?? ""
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: optedOutKey)
        defaults.removeObject(forKey: optedOutUntilKey)
        // Once-per-day auto-open mark + unregistered impression counter.
        defaults.removeObject(forKey: lastAutoPresentKey)
        defaults.removeObject(forKey: unregisteredImpressionsKey)
        defaults.removeObject(forKey: lastClaimAutoPresentKey)
        defaults.removeObject(forKey: "winr_marketing_consent")
        // Cached giveaway + a claim retry queued by the old session.
        defaults.removeObject(forKey: "winr.\(bundleId).giveaway")
        defaults.removeObject(forKey: "winr.\(bundleId).offline.pendingIntents")
        // Per-user state: email-submitted flag, streak, adoption code stamp.
        let userPrefix = "winr.\(bundleId).user."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(userPrefix) {
            defaults.removeObject(forKey: key)
        }
        // Auth token, refresh token, token expiry, user id.
        KeychainStorage().deleteAll()

        cachedOptedOut = false
        cachedGiveaway = nil
        cachedClaimedToday = nil
        cachedStreakDay = nil
        cachedEmailConsent = nil
        cachedAdoptionPending = nil
        cachedPendingPrizeClaim = false
        isNewUserThisSession = false
    }

    /// 3.2.2 — What to do with identity-scoped local state after the server
    /// answered about THIS account. Pure; the apply step is
    /// [applyIdentityReconcile].
    ///
    /// Why: the "email submitted" flag, the streak snapshot and the
    /// adoption-code stamp are cached locally and were only ever written, never
    /// re-checked. When the account they describe is deleted or reset
    /// server-side (data erasure, a database reset, a record that went away)
    /// the next `registerDevice` mints a FRESH user — and the SDK kept
    /// believing the old flags: it skipped email capture and auto-claimed, the
    /// backend refused with "email required", and the person sat on a Day-1
    /// dashboard that never advanced (Skape, Oct 2026). Mirrors web 3.1.10.
    ///
    /// Every rule needs a CURRENT backend; older backends omit these fields
    /// and local state is left alone. An opted-out account is also left alone
    /// — the 24-hour rejoin clears the whole session itself once the block
    /// lifts, and until then local state is deliberately frozen.
    enum IdentityReconcilePlan: Equatable {
        case leaveAlone
        /// `isNewUser == true`: the server has no history for this device —
        /// drop every per-user key and any queued claim retry. A genuine first
        /// install has nothing to drop, so this is a no-op there.
        case dropAccountState
        /// `emailConsentStatus == false` with no parked adoption: no email on
        /// file — drop the email flag only (streak history is the server's and
        /// is reconciled by the status call as usual). A parked adoption also
        /// reports `false`, but that state is routed to the code screen and
        /// must keep its stamp.
        case dropEmailFlag
    }

    static func identityReconcilePlan(
        isNewUser: Bool?, emailConsentStatus: Bool?, adoptionPending: Bool?, optedOut: Bool?
    ) -> IdentityReconcilePlan {
        if optedOut == true { return .leaveAlone }
        if isNewUser == true { return .dropAccountState }
        if emailConsentStatus == false, adoptionPending != true { return .dropEmailFlag }
        return .leaveAlone
    }

    /// Applies a plan to the on-device keys for `bundleId` / `userId`
    /// (the same keys the experience reads). Internal so tests can run it
    /// against UserDefaults directly.
    static func applyIdentityReconcile(
        _ plan: IdentityReconcilePlan, bundleId: String, userId: String, defaults: UserDefaults = .standard
    ) {
        switch plan {
        case .leaveAlone:
            return
        case .dropAccountState:
            let userPrefix = "winr.\(bundleId).user."
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(userPrefix) {
                defaults.removeObject(forKey: key)
            }
            AvafliOfflineResilience.shared?.coordinator.clear(.claim)
            Logger.shared.log("Fresh account from the server — stale local identity state dropped", level: .info)
        case .dropEmailFlag:
            defaults.removeObject(forKey: "winr.\(bundleId).user.\(userId).emailSubmitted")
            Logger.shared.log("Server reports no email on file — stale local email flag dropped", level: .info)
        }
    }

    /// Reconciles identity-scoped local state with the server's answer. Call
    /// with `lock` HELD (it touches the cached flags).
    private static func reconcileLocalIdentityLocked(
        isNewUser: Bool?, emailConsentStatus: Bool?, adoptionPending: Bool?, optedOut: Bool?
    ) {
        guard let configuration else { return }
        let plan = identityReconcilePlan(
            isNewUser: isNewUser, emailConsentStatus: emailConsentStatus,
            adoptionPending: adoptionPending, optedOut: optedOut
        )
        applyIdentityReconcile(plan, bundleId: configuration.bundleId, userId: configuration.user.id)
        switch plan {
        case .leaveAlone: break
        case .dropAccountState:
            cachedEmailConsent = emailConsentStatus ?? false
            cachedClaimedToday = false
        case .dropEmailFlag:
            cachedEmailConsent = false
        }
    }

    /// Foreground trigger: lifts an opt-out whose time passed while the app
    /// stayed in memory, then registers. At most one registration per call.
    private static func rejoinIfOptOutLapsed() async {
        lock.lock()
        let lifted = cachedOptedOut && restoreOptOutLocked()
        let config = configuration
        lock.unlock()
        guard lifted, let config else { return }
        await runRegistration(configuration: config)
    }

    private static func runRegistration(configuration: AvafliConfiguration) async {
        lock.lock()
        let override = registrationOverrideForTests
        lock.unlock()
        if let override {
            await override(configuration)
        } else {
            await registerDeviceIfNeeded(configuration: configuration)
        }
    }

    /// Caches and persists an opt-out together with the moment it lifts: the
    /// server's `optedOutUntil` when a response carries one, otherwise this
    /// device's clock + 24 hours (kept if a time is already stored).
    private static func recordOptOut(serverUntil: String?, refusedRejoin: Bool) {
        lock.lock()
        cachedOptedOut = true
        // An erased account has no claim to come back to.
        cachedPendingPrizeClaim = false
        lock.unlock()

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: optedOutKey)
        let now = currentDate().timeIntervalSince1970
        let server = serverUntil.flatMap(AvafliClaimDates.parseISO)?.timeIntervalSince1970
        if refusedRejoin {
            // We waited out the local time, asked, and the server still says
            // no (clock skew, sweep lag). Adopt its time and try again after
            // it — never sooner than the recheck interval, so a time that is
            // already behind this device's clock can't turn into a loop.
            defaults.set(max(server ?? 0, now + optOutRecheckInterval), forKey: optedOutUntilKey)
        } else if let server {
            defaults.set(server, forKey: optedOutUntilKey)
        } else if defaults.object(forKey: optedOutUntilKey) == nil {
            defaults.set(now + optOutRejoinInterval, forKey: optedOutUntilKey)
        }
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
        container.pendingPrizeClaim = cachedPendingPrizeClaim

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
                        cachedPendingPrizeClaim = response.prizeClaim?.isPending == true
                        if response.optedOut == true { cachedOptedOut = true }
                        // 3.2.2: an explicit "no email on file" drops the stale
                        // local flag (the status call never mints a user).
                        reconcileLocalIdentityLocked(
                            isNewUser: nil,
                            emailConsentStatus: response.emailConsentStatus,
                            adoptionPending: response.adoptionPending,
                            optedOut: response.optedOut
                        )
                        bootRecoveryPending = false
                        lock.unlock()
                        persistOptOutIfNeeded(serverUntil: response.optedOutUntil)
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
                    cachedPendingPrizeClaim = response.prizeClaim?.isPending == true
                    if response.optedOut == true { cachedOptedOut = true }
                    // 3.2.2: an explicit "no email on file" drops the stale
                    // local flag (the status call never mints a user).
                    reconcileLocalIdentityLocked(
                        isNewUser: nil,
                        emailConsentStatus: response.emailConsentStatus,
                        adoptionPending: response.adoptionPending,
                        optedOut: response.optedOut
                    )
                    bootRecoveryPending = false
                    lock.unlock()
                    persistOptOutIfNeeded(serverUntil: response.optedOutUntil)
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
            cachedPendingPrizeClaim = response.prizeClaim?.isPending == true
            if response.optedOut == true { cachedOptedOut = true }
            // First-ever registration of this device → `.returningUsersOnly`
            // skips this session's auto-open. Absent (older backend) → returning.
            isNewUserThisSession = response.isNewUser == true
            // 3.2.2: the server's identity answer outranks anything cached here.
            reconcileLocalIdentityLocked(
                isNewUser: response.isNewUser,
                emailConsentStatus: response.emailConsentStatus,
                adoptionPending: response.adoptionPending,
                optedOut: response.optedOut
            )
            bootRecoveryPending = false
            lock.unlock()
            persistOptOutIfNeeded(serverUntil: response.optedOutUntil)
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

    /// Persist the RTD flag (and the moment it lifts) whenever the backend
    /// reports it, so the suppression holds on future launches even offline.
    private static func persistOptOutIfNeeded(serverUntil: String? = nil) {
        lock.lock()
        let optedOut = cachedOptedOut
        // This response answers the rejoin attempt (if there was one).
        let refusedRejoin = rejoinAttempted
        rejoinAttempted = false
        lock.unlock()
        if optedOut {
            recordOptOut(serverUntil: serverUntil, refusedRejoin: refusedRejoin)
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
    // everywhere including prize claims, and tombstoned so the same email and
    // device cannot register again for 24 hours (it survives a reinstall). After
    // that the person may join again as a brand-new participant (3.2.0).

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
        cachedOptedOut = false
        rejoinAttempted = false
        nowOverrideForTests = nil
        cachedPendingPrizeClaim = false
        launchAutoOpenPending = false
        presentationOverrideForTests = nil
        isSuspended = false
        lock.unlock()
    }
    /// Stands in for putting the experience on screen (nil restores it).
    static func _setPresentationOverrideForTests(_ override: ((PresentationTrigger) -> Void)?) {
        lock.lock(); presentationOverrideForTests = override; lock.unlock()
    }
    static func _isPrizeClaimPendingForTests() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedPendingPrizeClaim
    }
    /// What a register / getActiveGiveaway response does to the cached state.
    static func _noteServerStateForTests(
        giveaway: GiveawayConfig?,
        prizeClaim: PrizeClaimBlock?,
        sdkConfig: SDKConfigResponse? = nil,
        emailConsent: Bool? = nil,
        isNewUser: Bool = false
    ) {
        lock.lock()
        cachedGiveaway = giveaway
        cachedSDKConfig = sdkConfig
        cachedEmailConsent = emailConsent
        cachedPendingPrizeClaim = prizeClaim?.isPending == true
        isNewUserThisSession = isNewUser
        lock.unlock()
    }
    /// The foreground trigger's auto-open check.
    @MainActor
    static func _foregroundAutoOpenCheckForTests() {
        autoPresentIfEligible()
    }
    static func _setSuspendedForTests(_ suspended: Bool) {
        lock.lock(); isSuspended = suspended; lock.unlock()
    }
    /// Replaces the clock the 24-hour rejoin runs on (nil restores it).
    static func _setNowForTests(_ now: (() -> Date)?) {
        lock.lock(); nowOverrideForTests = now; lock.unlock()
    }
    static func _isOptedOutForTests() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cachedOptedOut
    }
    /// What a register / getActiveGiveaway response carrying `optedOut` does.
    static func _noteServerOptOutForTests(optedOut: Bool?, until: String?) {
        lock.lock()
        if optedOut == true { cachedOptedOut = true }
        lock.unlock()
        persistOptOutIfNeeded(serverUntil: until)
    }
    /// The foreground trigger's rejoin check.
    static func _foregroundRejoinCheckForTests() async {
        await rejoinIfOptOutLapsed()
    }
    static func _setCachedGiveawayForTests(_ giveaway: GiveawayConfig?) {
        lock.lock(); cachedGiveaway = giveaway; lock.unlock()
    }
}
