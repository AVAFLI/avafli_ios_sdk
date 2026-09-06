//
//  AvafliExperienceViewModel.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation
import UIKit
import SwiftUI

/// The cache-first render decision, split out from the view model so it is
/// exercisable on its own: the drawer may paint the real dashboard from cached
/// values ONLY when every ingredient it needs is already on the device AND the
/// user has cleared the email gate.
enum AvafliV2CacheRender {
    /// Whether `hydrateFromCache` may paint the dashboard immediately.
    ///
    /// - `isLoading`: false once a fresh network response has already resolved
    ///   the phase — never stomp fresher truth.
    /// - `hasEmailConsent`: Day 1 / unconsented users must land on email
    ///   capture, NEVER on a cached dashboard.
    static func canHydrate(
        giveaway: GiveawayConfig?,
        streak: StreakState?,
        hasEmailConsent: Bool,
        isLoading: Bool,
        adoptionPending: Bool = false
    ) -> Bool {
        guard isLoading else { return false }
        // A parked cross-device link owns the open: the code screen is the
        // first frame, never a cached dashboard (see hydrateFromCache).
        guard !adoptionPending else { return false }
        guard giveaway != nil else { return false }
        guard hasEmailConsent else { return false }
        guard streak != nil else { return false }
        return true
    }
}

/// A transient, non-blocking notice shown at the top of the dashboard
/// (duplicate same-day entry, claim transport failure). Never blocks the
/// dashboard; `showsRetry` adds a "TRY AGAIN" affordance that re-attempts
/// the daily claim.
struct AvafliV2DashboardNotice: Equatable {
    let message: String
    let showsRetry: Bool
}

/// Drives the "Delete my data & stop participating" flow. Since 2.9.4 it is
/// raised by the privacy webview's `winr://delete` bridge (the privacy page,
/// loaded with ?app=1, carries the delete section); the confirmation renders
/// at the experience root. A tiny state machine, split out from the view
/// model so the transitions are exercisable on their own with a stubbed
/// opt-out action:
///
///     idle → confirming → inFlight → done → (dismiss whole experience)
///                     ↘ failed (inline error, retryable) ↗
///
/// Failure NEVER pretends success — the confirmation stays up with the
/// error and the destructive button remains available to retry.
@MainActor
final class AvafliV2OptOutCoordinator: ObservableObject {

    enum Phase: Equatable {
        /// Nothing showing (the "Privacy choices" link is idle).
        case idle
        /// The destructive confirmation is up.
        case confirming
        /// DELETE MY DATA tapped; the /optOut round-trip is in flight.
        case inFlight
        /// The round-trip failed — confirmation stays up with this inline error.
        case failed(String)
        /// Deleted. "Your data has been deleted." holds briefly, then the
        /// whole experience dismisses.
        case done
    }

    @Published private(set) var phase: Phase = .idle

    /// The real flow performs `Avafli.optOut()`; tests inject a stub.
    private let action: () async throws -> Void
    /// Dismisses the WHOLE experience (not just the dialog) after success.
    private let dismissExperience: () -> Void
    /// How long the success state holds before the experience dismisses.
    private let successHold: TimeInterval

    nonisolated init(
        successHold: TimeInterval = 1.4,
        action: @escaping () async throws -> Void,
        dismissExperience: @escaping () -> Void
    ) {
        self.successHold = successHold
        self.action = action
        self.dismissExperience = dismissExperience
    }

    /// Delete requested (the privacy webview's winr://delete bridge) — raise
    /// the confirmation.
    func begin() {
        if case .idle = phase { phase = .confirming }
    }

    /// Cancel / tap-outside. A no-op while the call is in flight or after the
    /// deletion has already happened.
    func cancel() {
        switch phase {
        case .confirming, .failed: phase = .idle
        case .idle, .inFlight, .done: break
        }
    }

    /// DELETE MY DATA tapped (initial attempt or retry after failure).
    func confirm() {
        switch phase {
        case .confirming, .failed: break
        case .idle, .inFlight, .done: return
        }
        phase = .inFlight
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.action()
                self.phase = .done
                try? await Task.sleep(nanoseconds: UInt64(self.successHold * 1_000_000_000))
                self.dismissExperience()
            } catch {
                self.phase = .failed(AvafliV2Strings.optOutFailed)
            }
        }
    }
}

final class AvafliExperienceViewModel: ObservableObject {

    /// Non-PII flag marking that the user completed the email-capture / consent
    /// flow. We persist this boolean instead of the raw email (PII-High) so the
    /// experience knows registration is complete without storing plaintext email.
    private var emailSubmittedKey: String {
        "winr.\(container.configuration.bundleId).user.\(container.user.id).emailSubmitted"
    }

    /// Cooldown between automatic code re-sends for a parked link: every open
    /// lands on the code screen, but the e-mail goes out at most once per
    /// window (the code itself lives 10 minutes). "Send a new code" always sends.
    private static let adoptionCodeResendCooldown: TimeInterval = 10 * 60

    private var adoptionCodeSentAtKey: String {
        "winr.\(container.configuration.bundleId).user.\(container.user.id).adoptionCodeSentAt"
    }

    private var adoptionCodeIsStale: Bool {
        let last: Double = (try? container.storage.load(Double.self, for: adoptionCodeSentAtKey)) ?? 0
        return Date().timeIntervalSince1970 - last >= Self.adoptionCodeResendCooldown
    }

    private func markAdoptionCodeSent() {
        try? container.storage.save(Date().timeIntervalSince1970, for: adoptionCodeSentAtKey)
    }

    private var streakStorageKey: String {
        "winr.\(container.configuration.bundleId).user.\(container.user.id).streak"
    }

    private var giveawayCacheKey: String {
        "winr.\(container.configuration.bundleId).giveaway"
    }

    enum State {
        case loading
        case noActiveGiveaway
        case emailCapture
        /// Verified adoption: the typed email matches an existing account; the
        /// merge waits on the 6-digit code sent to that inbox.
        case codeEntry(email: String)
        /// Soft email verification: reached by tapping the dashboard chip. Reuses
        /// the adoption code screen but is DISMISSIBLE (Cancel returns to the
        /// dashboard) and never gates play — it only confirms draw eligibility.
        case emailVerification
        /// Abandoned verification-gated adoption re-entry (2.9): the backend
        /// reported `adoptionPending`, a fresh code was just re-sent via
        /// `restageAdoption`, and the code screen shows with "pick up where
        /// you left off" copy. Same verify path as `.codeEntry`.
        case adoptionReentry
        case streak(StreakState, Int, [Int])
        case milestoneCelebration(MilestoneAward, DailyEntryGrant)
        /// Daily entries confirmation screen
        case dailyConfirmed(DailyEntryGrant, totalEntries: Int)
        case completed(DailyEntryGrant)
        case howItWorks
        /// This person is the drawn winner and hasn't submitted their claim yet
        /// — the drawer shows the winner splash → claim form → confirmation
        /// flow instead of the dashboard. Takes precedence on open.
        case winnerClaim(PrizeClaimBlock)
        case error(AvafliError)
    }

    /// Sub-screen of the winner claim flow (`state == .winnerClaim`).
    enum WinnerClaimStep: Equatable {
        case splash
        case form
        /// Post-submit "Please share a little" screen (2.9) — the claim is
        /// already on the backend, so closing here loses nothing.
        case share(claimNumber: String, submittedAt: String)
        case confirmation(claimNumber: String, submittedAt: String)
    }

    /// Whether the user has already claimed today's entry
    @Published var claimedToday: Bool = false

    /// Loading indicator for the daily claim button
    @Published var isClaimingDaily: Bool = false

    @Published private(set) var state: State = .loading

    private let container: DependencyContainer
    
    var activeGiveawayConfig: GiveawayConfig? { activeGiveaway }
    private weak var presentingViewController: UIViewController?
    private let completion: (Result<DailyEntryGrant, AvafliError>) -> Void
    private let streakEngine: StreakEngineProtocol
    private var lastPrimaryState: State?
    private var activeGiveaway: GiveawayConfig?
    private var cachedBackendClaimedToday: Bool?
    private var cachedBackendStreakDay: Int?
    private var cachedBackendMonthlyCurrent: Int?
    private var cachedBackendWeeklyCurrent: Int?
    private var cachedBackendLifetimeCount: Int?
    private var cachedBackendTotalEntries: Int?
    /// One-shot guard for the "already claimed on another device" re-sync.
    private var didResyncAfterAlreadyClaimed = false
    /// One-shot guard so a single experience open never spams restageAdoption
    /// (load() can run more than once per session).
    private var didAttemptAdoptionRestage = false

    // MARK: - Winner prize claim

    /// Which screen of the winner claim flow is showing.
    @Published var winnerClaimStep: WinnerClaimStep = .splash
    /// Spinner state for the claim form's SUBMIT pill.
    @Published var isSubmittingClaim = false
    /// Transport-level submit failure surfaced inline on the form ("Not the
    /// winner"/"Already submitted" instead fall back to the dashboard silently).
    @Published var claimSubmitError: String?
    /// The submitted form, kept for the confirmation screen's winner card.
    private(set) var submittedClaimForm: AvafliPrizeClaimForm?
    /// Set after a "Not the winner"/"Already submitted" rejection so the next
    /// load skips the winner flow and lands on the normal dashboard.
    private var suppressWinnerClaim = false

    /// Prefill for the claim form (host-app-provided identity).
    var claimFormPrefill: AvafliPrizeClaimForm {
        var form = AvafliPrizeClaimForm()
        form.firstName = container.user.firstName
        form.lastName = container.user.lastName
        form.phone = container.user.phone ?? ""
        return form
    }

    /// Email pre-fill is no longer supported — the SDK captures email via its own consent flow
    var prefillEmail: String? { nil }

    /// Server-driven copy & branding config from admin/publisher dashboard
    var sdkConfig: SDKConfigResponse? { container.sdkConfig }

    // MARK: - V2 display accessors

    @Published var isSubmittingEmail = false
    @Published var isVerifyingCode = false
    @Published var codeError: String?

    /// Soft email-verification affordance: `true` when the backend reported the
    /// user's freshly-typed email as unverified (`emailVerified == false`). Drives
    /// the persistent "Verify your email" chip on the dashboard. Never gates play.
    @Published var emailUnverified: Bool = false
    /// Inline error on the capture screen when the email submit network call
    /// failed — the user stays on the capture screen and can retry.
    @Published var emailSubmitError: String?
    /// The transient dashboard notice (nil = none showing).
    @Published var dashboardNotice: AvafliV2DashboardNotice?
    /// Consents from the ORIGINAL submit — resend must reuse them (fabricating
    /// values would overwrite the person's real marketing choice). Memory only.
    private var pendingConsents: (age: Bool, marketing: Bool)?

    /// Partner-authenticated email from AvafliUser, for the capture screen's
    /// read-only pre-fill. Nil when the publisher didn't supply one.
    var prefilledEmail: String? { container.user.email }

    // MARK: - V2 reveal flow (all days — Day 1 unified with Day 2+)
    //
    // The dashboard's FIRST VISIBLE FRAME is the celebration (the CTO's final
    // spec): toast bar, streak flip, counting total, and tile confetti all
    // fire in one beat at mount. Because the claim round-trip lands AFTER the
    // dashboard mounts, the grant is PREDICTED client-side from the pre-claim
    // status (AvafliV2Ladder mirrors the backend's math exactly) and the real
    // response reconciles silently — identical numbers in the normal case.
    // The pill reads "GOT IT" the whole time — there is no claim tap.

    /// The grant staged for the celebration (nil when nothing is pending).
    /// Predicted at load; replaced by the real grant when the claim lands.
    @Published private(set) var pendingRevealGrant: DailyEntryGrant?
    /// Whether the in-place celebration has played.
    @Published private(set) var claimRevealed = false
    /// Total entries as of before today's claim, for the pre-reveal frame.
    private(set) var preClaimTotalEntries: Int?

    /// Tiny mount-settle delay before the celebration fires — just enough for
    /// SwiftUI to render the staged "before" frame so every transition and
    /// count has something to animate from. Visually imperceptible; the
    /// drawer's slide-up covers it.
    static let mountRevealDelay: TimeInterval = 0.15

    @MainActor
    func revealClaim() {
        guard pendingRevealGrant != nil, !claimRevealed else { return }
        claimRevealed = true
    }

    /// Fires the celebration one frame after the dashboard mounts, making the
    /// first visible frame the celebrating one. Idempotent — the guard in
    /// revealClaim() makes double-fires harmless.
    @MainActor
    func armCelebrationReveal() {
        guard pendingRevealGrant != nil, !claimRevealed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.mountRevealDelay) { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                self.revealClaim()
            }
        }
    }

    /// Current streak day for display (backend truth, falling back to local).
    var displayStreakDay: Int {
        if let day = cachedBackendStreakDay { return day }
        let stored: StreakState? = try? container.storage.load(StreakState.self, for: streakStorageKey)
        return stored?.currentDay ?? 1
    }

    var displayTotalEntries: Int {
        // A staged celebration counts up to the PREDICTED post-claim total —
        // the real claim response reconciles these silently (normally a no-op).
        if let grant = pendingRevealGrant, let pre = preClaimTotalEntries {
            return pre + grant.baseEntries + grant.bonusEntries
        }
        return cachedBackendTotalEntries ?? lastClaimTotalEntries
    }

    /// The effective reward ladder (giveaway config, else engine defaults).
    var displayLadder: [Int] {
        if let ladder = activeGiveaway?.streakLadder, !ladder.isEmpty { return ladder }
        return (1...7).map { streakEngine.baseEntries(forDay: $0) }
    }

    /// Tomorrow's reward, for the come-back bar messaging.
    /// Uses the shared ladder math so accelerator milestones keep increasing it.
    var displayNextEntries: Int {
        AvafliV2Ladder.entries(
            day: displayStreakDay + 1,
            ladder: displayLadder,
            milestones: activeGiveaway?.milestones
        )
    }

    /// V2: the celebration modal's GOT IT — settle onto the dashboard.
    @MainActor
    func showDashboardAfterCelebration() {
        Task {
            try? await computeStreakAndMoveToDashboard(
                backendClaimedToday: true,
                backendStreakDay: cachedBackendStreakDay
            )
        }
    }

    /// V2: close the whole experience (X buttons / GOT IT on the dashboard).
    func requestDismiss() {
        NotificationCenter.default.post(name: .avafliCloseRequested, object: nil)
    }

    /// The delete-my-data flow (raised by the privacy webview's winr://delete
    /// bridge; confirmation rendered at the experience root). On confirm it
    /// performs the real RTD opt-out (`Avafli.optOut()`), holds the success
    /// state a beat, then dismisses the whole experience.
    lazy var optOutCoordinator = AvafliV2OptOutCoordinator(
        action: { try await Avafli.optOut() },
        dismissExperience: { [weak self] in self?.requestDismiss() }
    )

    init(
        container: DependencyContainer,
        presentingViewController: UIViewController,
        streakEngine: StreakEngineProtocol = StreakEngine(),
        completion: @escaping (Result<DailyEntryGrant, AvafliError>) -> Void
    ) {
        self.container = container
        self.presentingViewController = presentingViewController
        self.streakEngine = streakEngine
        self.completion = completion
        self.activeGiveaway = container.cachedGiveaway
        container.analytics?.trackExperienceOpened(giveawayId: activeGiveaway?.id)
        // Paint the dashboard from cache on the FIRST frames — before any
        // network call resolves — then let load() reconcile silently.
        hydrateFromCache()
        Task { await load() }
        // A background offline-claim retry landed while the drawer is open —
        // reconcile through the existing load() refresh path (no new UI).
        offlineRetryObserver = NotificationCenter.default.addObserver(
            forName: AvafliOfflineResilience.claimRetrySucceededNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if case .streak = self.state {
                Task { await self.load() }
            }
        }
    }

    private var offlineRetryObserver: NSObjectProtocol?

    deinit {
        if let offlineRetryObserver {
            NotificationCenter.default.removeObserver(offlineRetryObserver)
        }
    }

    // MARK: - Cache-first render

    /// True once the dashboard has been painted from cached values, so the
    /// network reconcile knows it is updating a LIVE dashboard rather than
    /// replacing a loading screen.
    private(set) var hydratedFromCache = false

    /// Renders the dashboard IMMEDIATELY from cached state (giveaway config +
    /// persisted streak), skipping the loading phase entirely.
    ///
    /// The drawer used to sit on a spinner for as long as the sequential
    /// registerDevice → getActiveGiveaway → claim round-trips took (5s+ on a
    /// slow network) even when every value it needed was already on the device.
    /// Everything here is a LOCAL read, so it lands in the same runloop turn as
    /// the drawer's first frame; load() then reconciles the same way the
    /// celebration staging already does — silently, in place, with no
    /// re-animation (the reveal flags are untouched, so a staged celebration
    /// still fires exactly once).
    ///
    /// Bails out (leaving the skeleton up) when anything is missing — a
    /// first-ever open, an un-consented user who must see email capture first,
    /// or a cold cache all take the genuine loading path.
    private func hydrateFromCache() {
        let storage = container.storage
        let giveaway = activeGiveaway ?? (try? storage.load(GiveawayConfig.self, for: giveawayCacheKey))
        let stored: StreakState? = try? storage.load(StreakState.self, for: streakStorageKey)
        var isLoading = false
        if case .loading = state { isLoading = true }

        // A parked cross-device link OWNS this open: the code screen is the
        // FIRST frame — never a cached dashboard that sits there for the
        // network round-trips and reads as "day 1" to a person who then
        // closes the sheet having seen no code prompt (while the code e-mail
        // is already on its way). load() re-affirms the screen and handles
        // the cooled-down resend.
        if container.adoptionPending == true, isLoading {
            if let giveaway { activeGiveaway = giveaway }
            codeError = nil
            state = .adoptionReentry
            return
        }

        guard AvafliV2CacheRender.canHydrate(
            giveaway: giveaway,
            streak: stored,
            hasEmailConsent: hasEmailConsent,
            isLoading: isLoading,
            adoptionPending: container.adoptionPending == true
        ), let giveaway, var display = stored else { return }

        let ladder = giveaway.streakLadder.isEmpty
            ? (1...7).map { streakEngine.baseEntries(forDay: $0) }
            : giveaway.streakLadder
        let day = container.cachedStreakDay ?? display.currentDay
        display.currentDay = day
        let dayIndex = min(max(day - 1, 0), ladder.count - 1)

        activeGiveaway = giveaway
        claimedToday = container.cachedClaimedToday ?? false
        // Seed the display caches from the persisted state, otherwise the
        // already-claimed readout falls through to `lastClaimTotalEntries` and
        // the card's first frame reads "0 Total Entries". The fresh response
        // overwrites both a moment later (normally with the same numbers).
        if cachedBackendTotalEntries == nil { cachedBackendTotalEntries = display.totalEntriesEarned }
        if cachedBackendStreakDay == nil { cachedBackendStreakDay = day }
        hydratedFromCache = true
        state = .streak(display, ladder[dayIndex], ladder)
    }

    // MARK: - State machine

    /// `claimBeforeDashboard` (email-capture path): AWAIT the daily claim
    /// before the dashboard state is ever set, so the capture view (spinner)
    /// stays up through the round-trip and the dashboard MOUNTS with the
    /// celebration staged from the REAL claim response — the new user's first
    /// dashboard frame is the celebration, exactly like Day 2+ (CTO spec:
    /// the streak page is never seen uncelebrated).
    @MainActor
    private func load(claimBeforeDashboard: Bool = false) async {
        do {
            let storage = container.storage

            // Always fetch fresh claim status from the backend.
            // The giveaway config may already be cached, but claimedToday can change
            // between experience opens (e.g., after the user already claimed).
            var backendClaimedToday: Bool? = container.cachedClaimedToday
            var backendStreakDay: Int? = container.cachedStreakDay
            var pendingPrizeClaim: PrizeClaimBlock?
            // Abandoned adoption signal: seeded from the register response
            // (via the container), refreshed by getActiveGiveaway below.
            var backendAdoptionPending: Bool? = container.adoptionPending

            do {
                let response = try await container.network.send(GetActiveGiveawayRequest())

                // RTD: an opted-out person never sees the experience content.
                if response.optedOut == true {
                    state = .noActiveGiveaway
                    return
                }

                // Winner prize claim: a PENDING block takes precedence over the
                // dashboard on open (routed below, once the caches are synced).
                // A "submitted" block is ignored — the normal dashboard shows.
                if let claim = response.prizeClaim, claim.isPending, !suppressWinnerClaim {
                    pendingPrizeClaim = claim
                }

                // Check if backend returned no active giveaway. (A pending prize
                // claim can outlive its giveaway — the winner flow still shows.)
                if response.giveaway == nil && pendingPrizeClaim == nil {
                    // Clear cached giveaway and set state to no active giveaway
                    activeGiveaway = nil
                    try? storage.remove(for: giveawayCacheKey)
                    state = .noActiveGiveaway
                    return
                }

                if let giveaway = response.giveaway {
                    activeGiveaway = giveaway
                    // Cache the new giveaway
                    try? storage.save(giveaway, for: giveawayCacheKey)
                    // Keep the prize art warm across prize changes mid-session.
                    AvafliV2ImageWarmer.prewarm(giveaway.prizeImageUrl)
                }
                backendClaimedToday = response.claimedToday
                backendStreakDay = response.streakDay
                cachedBackendMonthlyCurrent = response.monthlyCurrent
                cachedBackendWeeklyCurrent = response.weeklyCurrent
                cachedBackendLifetimeCount = response.lifetimeCount
                cachedBackendTotalEntries = response.totalEntries

                // Backend is the source of truth for email consent. If it confirms
                // an email on file, seed the local "submitted" flag so a user whose
                // local flag was lost (e.g. reinstall) isn't re-prompted for email.
                // ...unless a cross-device link is parked: the backend echoes
                // the shell user's consent, and seeding the flag from it let
                // the next open bypass the code screen into a cached dashboard
                // (Sept 2026 field report).
                if response.emailConsentStatus == true, response.adoptionPending != true {
                    try? storage.save(true, for: emailSubmittedKey)
                }

                // Soft email-verification signal: ONLY an explicit `false` means
                // "typed a new email, not yet confirmed" → show the chip. Absent
                // (verified / partner-passed / adoption-verified / no email)
                // leaves the chip hidden. Never gates play.
                emailUnverified = Self.showsVerifyEmailChip(emailVerified: response.emailVerified)

                if let adoptionPending = response.adoptionPending {
                    backendAdoptionPending = adoptionPending
                }
            } catch {
                // Backend geo-fence rejection: a dedicated state, never the
                // generic empty state — the person needs to know WHY there is
                // nothing here (Master Field List "User Message (UI)").
                if case AvafliError.geoBlocked = error {
                    state = .error(.geoBlocked)
                    return
                }
                // Dead session: the silent token refresh failed for a device
                // that HAS registered before. Render the session-expired state
                // (with RETRY) rather than collapsing into the empty state.
                // An unregistered fresh install still takes the normal
                // offline/email-capture path below.
                if case AvafliError.authenticationRequired = error, hasRegistered {
                    state = .error(.authenticationRequired)
                    return
                }
                // Offline fallback: use cached giveaway
                if activeGiveaway == nil {
                    activeGiveaway = try? storage.load(GiveawayConfig.self, for: giveawayCacheKey)
                }
                Logger.shared.log("Using cached giveaway (offline): \(error)", level: .debug)
            }

            cachedBackendClaimedToday = backendClaimedToday
            cachedBackendStreakDay = backendStreakDay

            // Winner prize claim takes precedence over auto-claim/dashboard on
            // open — but the daily auto-claim still fires silently in the
            // background so the winner's entries keep accruing.
            if let claim = pendingPrizeClaim {
                winnerClaimStep = .splash
                state = .winnerClaim(claim)
                container.analytics?.track(
                    event: "avafli_winner_claim_shown",
                    properties: ["giveaway_id": claim.giveawayId]
                )
                if backendClaimedToday != true, hasEmailConsent {
                    silentDailyClaim()
                }
                return
            }

            // Adoption re-entry (2.9): this device typed an existing account's
            // email, was sent a code, and never finished. Re-stage the adoption
            // (the backend re-sends a fresh 6-digit code) and drop straight
            // onto the code screen with "pick up where you left off" copy.
            // One-shot per experience open; any failure falls through to the
            // normal email-capture gate — never a dead end.
            // Runs BEFORE the email gate (hardened Sept 2026): an earlier open
            // may have seeded the local consent flag from the backend's echo
            // for the shell user, and a parked link must never be bypassed
            // into a cached dashboard or a claim. Screen first, then a
            // cooled-down resend; a failed send keeps the code screen up.
            if backendAdoptionPending == true, !didAttemptAdoptionRestage {
                didAttemptAdoptionRestage = true
                codeError = nil
                state = .adoptionReentry
                guard adoptionCodeIsStale else { return }
                do {
                    let restage = try await container.network.send(RestageAdoptionRequest())
                    if restage.sent {
                        markAdoptionCodeSent()
                        return
                    }
                    Logger.shared.log("restageAdoption declined (sent=false) — falling back to email capture", level: .info)
                    Avafli.clearAdoptionPending()
                } catch {
                    Logger.shared.log("restageAdoption failed — code screen kept, resend available: \(error)", level: .error)
                    return
                }
            }

            // Email-capture gate: shown until the user completes the consent flow.
            // Raw email is never persisted in plaintext — we gate on a non-PII
            // "email submitted" flag plus the presence of user_uid in the Keychain
            // (the handshake identifier), not on a stored email value.
            if !hasEmailConsent {
                state = .emailCapture
                return
            }

            // Email path (Day 1): claim FIRST, while the capture view's spinner
            // is still up. On success the celebration is staged from the real
            // response (synchronous with the transition — no prediction needed)
            // and the caches below already reflect the claim, so the predicted
            // staging is naturally skipped. On failure this is a no-op and the
            // normal predict → auto-claim → reconcile path takes over.
            if claimBeforeDashboard, backendClaimedToday == false, hasEmailConsent {
                await claimAndStageBeforeDashboard()
                backendClaimedToday = cachedBackendClaimedToday
                backendStreakDay = cachedBackendStreakDay
            }

            // Auto-claim staging (Day 1 AND Day 2+): stage the PREDICTED grant
            // BEFORE the dashboard state is set, so the celebration is the
            // dashboard's first visible frame — the claim round-trip lands
            // later and reconciles silently. Day 1 celebrates in place exactly
            // like Day 2+ (the "You're in!" modal is gone); only the toast
            // headline differs.
            if backendClaimedToday == false, hasEmailConsent,
               let day = backendStreakDay, day >= 1,
               let preTotal = cachedBackendTotalEntries {
                let predicted = AvafliV2Ladder.entries(
                    day: day,
                    ladder: displayLadder,
                    milestones: activeGiveaway?.milestones
                )
                pendingRevealGrant = DailyEntryGrant(baseEntries: predicted, bonusEntries: 0)
                claimRevealed = false
                preClaimTotalEntries = preTotal
            }

            try await computeStreakAndMoveToDashboard(backendClaimedToday: backendClaimedToday, backendStreakDay: backendStreakDay)

            // Cache-first render: the dashboard MOUNTED before this staging
            // landed, so its .onAppear already ran with nothing pending and
            // will not run again. Arm the reveal here instead — armCelebration
            // Reveal is guarded, so the celebration still fires exactly once.
            if hydratedFromCache, case .streak = state {
                armCelebrationReveal()
            }

            // V2 experience: entries are granted automatically when the drawer opens —
            // no tap required. Registered + consented + not-yet-claimed → claim now.
            // Failures are silent (the dashboard just shows the unclaimed state).
            if case .streak = state, claimedToday == false, hasEmailConsent {
                claimDailyEntries(auto: true)
            }
        } catch {
            // Already showing a cache-rendered dashboard: a local hiccup is not
            // worth replacing live content with an error screen.
            if !hydratedFromCache {
                state = .error(.internalError(error.localizedDescription))
            }
        }
    }

    @MainActor
    func primaryFromHowItWorks() {
        hideHowItWorks()
    }

    @MainActor
    func showHowItWorks() {
        lastPrimaryState = state
        state = .howItWorks
    }

    @MainActor
    func hideHowItWorks() {
        if let previous = lastPrimaryState {
            state = previous
        } else {
            state = .loading
            Task { await load() }
        }
    }

    @MainActor
    private func computeStreakAndMoveToDashboard(backendClaimedToday: Bool? = nil, backendStreakDay: Int? = nil) async throws {
        let storage = container.storage
        let stored: StreakState? = try storage.load(StreakState.self, for: streakStorageKey)
        let today = Date()

        // Use giveaway ladder if available, otherwise fall back to engine defaults
        let ladder: [Int]
        if let giveaway = activeGiveaway {
            ladder = giveaway.streakLadder
        } else {
            ladder = (1...7).map { streakEngine.baseEntries(forDay: $0) }
        }

        // ─── Backend is source of truth for claim status ───
        // If the backend told us whether the user claimed today, use that directly.
        if let backendClaimed = backendClaimedToday {
            let day = backendStreakDay ?? stored?.currentDay ?? 1
            let dayIndex = min(day - 1, ladder.count - 1)
            let entriesToday = ladder[max(0, dayIndex)]
            
            var displayState = stored ?? StreakState(
                currentDay: day,
                lastClaimedDate: backendClaimed ? today : nil,
                totalEntriesEarned: 0,
                weeklyCurrent: 1,
                weeklyStart: "",
                monthlyCurrent: 1,
                monthlyStart: "",
                lifetimeCount: 0
            )
            
            // Always sync with backend — backend is source of truth
            displayState.currentDay = day
            if let mc = cachedBackendMonthlyCurrent { displayState.monthlyCurrent = mc }
            if let wc = cachedBackendWeeklyCurrent { displayState.weeklyCurrent = wc }
            if let lc = cachedBackendLifetimeCount { displayState.lifetimeCount = lc }
            // Seed the running total from the backend (source of truth) so the
            // "current → after" reward pill and the Total-entries readout reflect
            // entries claimed on OTHER devices — otherwise this shows a stale local
            // total (e.g. 110 from a prior local claim while the backend is at 170).
            if let te = cachedBackendTotalEntries { displayState.totalEntriesEarned = te }
            
            // Sync local state with backend
            if backendClaimed && stored?.lastClaimedDate == nil {
                displayState.lastClaimedDate = today
            }
            try? storage.save(displayState, for: streakStorageKey)
            
            claimedToday = backendClaimed
            state = .streak(displayState, entriesToday, ladder)
            return
        }

        // ─── Offline fallback: use local StreakEngine ───
        let result = streakEngine.nextState(from: stored, on: today)
        switch result {
        case .failure(let error):
            if case .ineligibleToday = error, let stored = stored {
                claimedToday = true
                let dayIndex = min(stored.currentDay - 1, ladder.count - 1)
                let entriesToday = ladder[max(0, dayIndex)]
                state = .streak(stored, entriesToday, ladder)
            } else if !hydratedFromCache {
                state = .error(error)
            }
            // Already showing a cache-rendered dashboard: a local streak-engine
            // hiccup is not worth replacing it with an error screen.

        case .success(let newState):
            let dayIndex = min(newState.currentDay - 1, ladder.count - 1)
            let entriesToday = ladder[max(0, dayIndex)]
            claimedToday = false
            state = .streak(newState, entriesToday, ladder)
        }
    }

    // MARK: - Email capture

    @MainActor
    /// Check the 6-digit adoption code; approved → adopt the canonical user's
    /// credentials and reload into the dashboard (same as a direct adoption).
    func submitVerificationCode(_ code: String) {
        guard !isVerifyingCode else { return }
        isVerifyingCode = true
        codeError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isVerifyingCode = false } }
            do {
                let response = try await container.network.send(VerifyAdoptionCodeRequest(code: code))
                if response.adopted == true, let token = response.token, let uuid = response.uuid {
                    container.keychain.saveToken(token)
                    if let refresh = response.refreshToken { container.keychain.saveRefreshToken(refresh) }
                    container.keychain.saveUUID(uuid)
                    Logger.shared.log("Adoption verified — streak unified across devices", level: .info)
                }
                // The adoption is complete — a restaged re-entry must not
                // re-trigger on the next open.
                Avafli.clearAdoptionPending()
                try? container.storage.remove(for: adoptionCodeSentAtKey)
                // The inbox is proven and the backend has the email — record
                // consent now (submitEmail no longer pre-saves the flag).
                recordEmailConsent(
                    ageConfirmed: pendingConsents?.age ?? true,
                    marketingConsent: pendingConsents?.marketing ?? false
                )
                await MainActor.run { self.state = .loading }
                await load(claimBeforeDashboard: true)
            } catch {
                Logger.shared.log("Adoption code check failed: \(error)", level: .error)
                await MainActor.run {
                    // Three-way taxonomy (matched across SDKs): the backend sends
                    // distinguishable failures for an expired code and a
                    // too-many-attempts lockout; everything else is a mismatch.
                    self.codeError = Self.codeErrorMessage(for: error)
                }
            }
        }
    }

    /// The soft-verification chip-visibility rule, in one place: ONLY an explicit
    /// `false` (a freshly-typed, unconfirmed email) shows the "Verify your email"
    /// chip. Absent (verified / partner-passed / adoption-verified / no email) and
    /// an explicit `true` never do. Never gates play.
    static func showsVerifyEmailChip(emailVerified: Bool?) -> Bool {
        emailVerified == false
    }

    /// Maps a verifyAdoptionCode failure to user copy. The backend emits a
    /// `deadline-exceeded` error whose message contains "expired" and a
    /// `resource-exhausted` error whose message contains "attempts"; both reach
    /// us as `AvafliError.internalError(message)`. A plain mismatch arrives as a
    /// `permission-denied`/auth error with no distinguishing keyword and falls
    /// through to the generic "didn't match" copy. Matching is case-insensitive.
    static func codeErrorMessage(for error: Error) -> String {
        let raw: String
        if let avafli = error as? AvafliError {
            raw = avafli.errorDescription ?? ""
        } else {
            raw = error.localizedDescription
        }
        let lowered = raw.lowercased()
        if lowered.contains("expired") { return AvafliV2Strings.codeExpired }
        if lowered.contains("attempts") { return AvafliV2Strings.codeTooManyAttempts }
        return AvafliV2Strings.codeIncorrect
    }

    /// Request a fresh code by re-submitting the ORIGINAL email + consents.
    ///
    /// The code-entry screen stays up the entire time: a FAILED resend shows the
    /// code-screen error inline instead of stranding the user back on email
    /// capture, and a SUCCESSFUL resend leaves them on code entry ready to type
    /// the new code. The consents are the ones captured on the original submit —
    /// never fabricated or reset (the established pattern).
    func resendVerificationCode() {
        guard case let .codeEntry(email) = state, let consents = pendingConsents else { return }
        guard !isVerifyingCode else { return }
        isVerifyingCode = true
        codeError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isVerifyingCode = false } }
            do {
                let response = try await container.network.send(
                    SubmitEmailRequest(email: email, ageConfirmed: consents.age, marketingConsent: consents.marketing)
                )
                // If the OTP gate is off and the backend adopted outright, honor
                // it and load straight into the dashboard (same as submitEmail).
                if response.adopted == true, let token = response.token, let uuid = response.uuid {
                    container.keychain.saveToken(token)
                    if let refresh = response.refreshToken { container.keychain.saveRefreshToken(refresh) }
                    container.keychain.saveUUID(uuid)
                    recordEmailConsent(ageConfirmed: consents.age, marketingConsent: consents.marketing)
                    await MainActor.run { self.state = .loading }
                    await load(claimBeforeDashboard: true)
                    return
                }
                // Normal path: a fresh code is on its way. Stay on code entry.
                await MainActor.run {
                    self.codeError = nil
                    self.state = .codeEntry(email: email)
                }
            } catch {
                Logger.shared.log("Resend verification code failed: \(error)", level: .error)
                await MainActor.run {
                    // Keep the code screen up with an inline error — never
                    // navigate away, so a failed resend can't strand the user.
                    self.codeError = AvafliV2Strings.resendFailed
                }
            }
        }
    }

    /// "Send a new code" on the adoption RE-ENTRY screen: the SDK holds no
    /// email/consents from the abandoned session, so the resend is another
    /// restageAdoption round-trip (the backend still knows the address). The
    /// code screen stays up throughout; failures show inline.
    @MainActor
    func resendRestagedAdoption() {
        guard !isVerifyingCode else { return }
        isVerifyingCode = true
        codeError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isVerifyingCode = false } }
            do {
                let response = try await container.network.send(RestageAdoptionRequest())
                if response.sent { markAdoptionCodeSent() }
                await MainActor.run {
                    self.codeError = response.sent ? nil : AvafliV2Strings.resendFailed
                }
            } catch {
                Logger.shared.log("Restage adoption resend failed: \(error)", level: .error)
                await MainActor.run { self.codeError = AvafliV2Strings.resendFailed }
            }
        }
    }

    // MARK: - Email verification (soft gate — dismissible, never blocks play)

    /// Open the verification screen from the dashboard chip. Dismissible (unlike
    /// adoption): `hideEmailVerification()` returns to whatever primary screen
    /// was showing.
    @MainActor
    func showEmailVerification() {
        codeError = nil
        lastPrimaryState = state
        state = .emailVerification
    }

    /// Cancel/back out of the verification screen — return to the dashboard.
    @MainActor
    func hideEmailVerification() {
        codeError = nil
        if let previous = lastPrimaryState {
            state = previous
        } else {
            state = .loading
            Task { await load() }
        }
    }

    /// Confirm the freshly-typed email with the 6-digit code. On success: hide
    /// the chip, drop a brief "Email verified ✓" confirmation, and return to the
    /// dashboard. On failure: stay on the code screen with the mapped inline
    /// error (same three-way taxonomy as adoption).
    @MainActor
    func confirmEmailVerification(_ code: String) {
        guard !isVerifyingCode else { return }
        isVerifyingCode = true
        codeError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isVerifyingCode = false } }
            do {
                let response = try await container.network.send(ConfirmEmailVerificationRequest(code: code))
                await MainActor.run {
                    if response.verified {
                        self.emailUnverified = false
                        Logger.shared.log("Email verified — draw eligibility confirmed", level: .info)
                        // Return to the dashboard and float a brief confirmation.
                        if let previous = self.lastPrimaryState {
                            self.state = previous
                        }
                        self.showDashboardNotice(AvafliV2Strings.verifyEmailSuccess, showsRetry: false)
                    } else {
                        self.codeError = AvafliV2Strings.codeIncorrect
                    }
                }
            } catch {
                Logger.shared.log("Email verification code check failed: \(error)", level: .error)
                await MainActor.run {
                    self.codeError = Self.codeErrorMessage(for: error)
                }
            }
        }
    }

    /// Re-send the email-verification code. Stays on the code screen throughout —
    /// a failed resend shows an inline error rather than stranding the user.
    @MainActor
    func resendEmailVerification() {
        guard !isVerifyingCode else { return }
        isVerifyingCode = true
        codeError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isVerifyingCode = false } }
            do {
                _ = try await container.network.send(ResendEmailVerificationRequest())
                await MainActor.run { self.codeError = nil }
            } catch {
                Logger.shared.log("Resend email verification failed: \(error)", level: .error)
                await MainActor.run { self.codeError = AvafliV2Strings.resendFailed }
            }
        }
    }

    func submitEmail(_ email: String, ageConfirmed: Bool, marketingConsent: Bool) {
        guard !email.isEmpty else { return }

        // Submit email to the backend, THEN advance. We await (rather than the old
        // fire-and-forget) because the backend consent gate blocks a claim until the
        // email is on file — advancing first would race into a failed claim.
        //
        // The non-PII "email submitted" flag is persisted only AFTER the
        // backend confirms (see recordEmailConsent). It used to be saved
        // before the network call, so a failed submit still marked the user
        // as consented and skipped the capture screen forever after.
        emailSubmitError = nil
        isSubmittingEmail = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.isSubmittingEmail = false } }
            guard let self else { return }
            do {
                let response = try await container.network.send(
                    SubmitEmailRequest(email: email, ageConfirmed: ageConfirmed, marketingConsent: marketingConsent)
                )
                // Cross-device streak unification: if this email already belonged to
                // an existing user under this publisher (another device/SDK), the
                // backend hands back that canonical user's credentials. Switch to
                // them so the person keeps ONE streak per publisher across devices.
                if response.verificationRequired == true {
                    // The merge is parked until the person proves the inbox is
                    // theirs. Raw email stays in view-model state only.
                    markAdoptionCodeSent()
                    await MainActor.run {
                        self.pendingConsents = (ageConfirmed, marketingConsent)
                        self.codeError = nil
                        self.state = .codeEntry(email: email)
                    }
                    return
                }
                if response.adopted == true, let token = response.token, let uuid = response.uuid {
                    container.keychain.saveToken(token)
                    if let refresh = response.refreshToken { container.keychain.saveRefreshToken(refresh) }
                    container.keychain.saveUUID(uuid)
                    Logger.shared.log("Adopted existing account — streak unified across devices", level: .info)
                }
                // Soft email-verification: a brand-new typed email comes back
                // `emailVerified == false` — surface the dashboard chip right away
                // (the subsequent load re-confirms it). Only an explicit false counts.
                await MainActor.run { self.emailUnverified = Self.showsVerifyEmailChip(emailVerified: response.emailVerified) }
                // The backend has the email now — persist the non-PII consent
                // flags and refresh the facade's cached consent (otherwise only
                // getActiveGiveaway refreshes it, which can be a session away).
                recordEmailConsent(ageConfirmed: ageConfirmed, marketingConsent: marketingConsent)
                Logger.shared.log("Email submitted to backend", level: .debug)
            } catch {
                Logger.shared.log("Email submit to backend failed: \(error)", level: .error)
                await MainActor.run {
                    if case AvafliError.geoBlocked = error {
                        self.state = .error(.geoBlocked)
                    } else if case AvafliError.authenticationRequired = error, self.hasRegistered {
                        self.state = .error(.authenticationRequired)
                    } else {
                        // Keep the user ON the capture screen with an inline
                        // error and let them retry — never proceed as success.
                        self.emailSubmitError = AvafliV2Strings.emailSubmitFailed
                    }
                }
                return
            }

            // Re-load so the (possibly switched) canonical user's authoritative
            // streak + claim status drive the UI. The Day-1 claim is awaited
            // INSIDE the load (capture spinner stays up) so the dashboard
            // mounts already celebrating — never an uncelebrated streak page.
            await load(claimBeforeDashboard: true)
        }
    }

    /// Persists the non-PII consent flags the moment a submit (or verified
    /// adoption) actually SUCCEEDS — never before. We deliberately do NOT
    /// persist the raw email locally (PII-High): the backend stores it
    /// AES-256-encrypted and returns a user_uid handshake; registration state
    /// is derived from user_uid in the Keychain instead.
    private func recordEmailConsent(ageConfirmed: Bool, marketingConsent: Bool) {
        do {
            try container.storage.save(true, for: emailSubmittedKey)
            try container.storage.save(marketingConsent, for: "winr_marketing_consent")
            Logger.shared.log("Avafli email submitted (age confirmed: \(ageConfirmed), marketing consent: \(marketingConsent))", level: .info)
        } catch {
            Logger.shared.log("Failed to save email-submitted flag: \(error)", level: .error)
        }
        Avafli.markEmailConsentGranted()
    }

    /// Email path (Day 1): awaited claim BEFORE the dashboard ever mounts. On
    /// success the celebration is staged from the real response, so the first
    /// dashboard frame counts 0 → N under the "YOU'RE IN!" toast. On failure
    /// this is a no-op — load() falls through to the predicted staging and the
    /// silent auto-claim retry, the same as any other open.
    @MainActor
    private func claimAndStageBeforeDashboard() async {
        do {
            let response = try await container.network.send(ClaimDailyEntriesRequest())
            var bonusEntries = 0
            if let weekly = response.weeklyBonusEntries { bonusEntries += weekly }
            if let monthly = response.monthlyBonusEntries { bonusEntries += monthly }
            if let milestone = response.milestone { bonusEntries += milestone.bonusEntries }
            if let monthlyMilestone = response.monthlyMilestone { bonusEntries += monthlyMilestone.bonusEntries }
            let grant = DailyEntryGrant(baseEntries: response.entries, bonusEntries: bonusEntries)

            lastClaimTotalEntries = response.totalEntries
            cachedBackendTotalEntries = response.totalEntries
            cachedBackendStreakDay = response.streakDay
            cachedBackendClaimedToday = true
            if let mc = response.monthlyCurrent { cachedBackendMonthlyCurrent = mc }
            if let wc = response.weeklyCurrent { cachedBackendWeeklyCurrent = wc }
            if let lc = response.lifetimeCount { cachedBackendLifetimeCount = lc }

            pendingRevealGrant = grant
            preClaimTotalEntries = response.totalEntries - (grant.baseEntries + grant.bonusEntries)
            claimRevealed = false

            container.analytics?.track(
                event: AvafliAnalyticsEvent.dailyEntryClaimed,
                properties: ["day": response.streakDay, "entries": response.entries]
            )
            Avafli.clearOfflineClaimRetry()
        } catch {
            Logger.shared.log("Day-1 claim after email submit failed (dashboard will retry): \(error)", level: .info)
            Avafli.enqueueOfflineClaimRetry(for: error)
        }
    }

    @MainActor
    func skipEmailCapture() {
        // Email is mandatory — redirect back to email capture
        state = .emailCapture
    }

    // MARK: - Daily entries

    /// Whether the registration handshake produced a user_uid in the Keychain.
    private var hasRegistered: Bool {
        container.keychain.loadUUID() != nil
    }

    /// Whether the user has completed email capture (required before claiming).
    /// Gated on the non-PII "email submitted" flag — raw email is never stored.
    /// Requires the handshake user_uid to exist so the backend can attribute the
    /// entry; if registration hasn't completed yet we re-show the capture flow.
    var hasEmailConsent: Bool {
        let submitted: Bool = (try? container.storage.load(Bool.self, for: emailSubmittedKey)) ?? false
        return submitted && hasRegistered
    }

    @MainActor
    func claimDailyEntries(auto: Bool = false) {
        guard case let .streak(streak, entries, ladder) = state else { return }
        guard !isClaimingDaily else { return }

        // Email consent gate: must have email before claiming
        if !hasEmailConsent {
            state = .emailCapture
            return
        }

        isClaimingDaily = true

        // Claim from backend
        Task {
            do {
                let response = try await container.network.send(ClaimDailyEntriesRequest())
                
                // Handle bonus entries from all sources (milestones, weekly/monthly bonuses)
                var streakBonusEntries = 0
                if let weeklyBonus = response.weeklyBonusEntries {
                    streakBonusEntries += weeklyBonus
                }
                if let monthlyBonus = response.monthlyBonusEntries {
                    streakBonusEntries += monthlyBonus
                }
                if let milestone = response.milestone {
                    streakBonusEntries += milestone.bonusEntries
                }
                if let monthlyMilestone = response.monthlyMilestone {
                    streakBonusEntries += monthlyMilestone.bonusEntries
                }
                
                // Keep baseEntries as just the daily ladder amount;
                // streak bonuses (monthly/weekly/milestone) go into bonusEntries
                // so the UI can show a proper breakdown.
                let grant = DailyEntryGrant(baseEntries: response.entries, bonusEntries: streakBonusEntries)
                lastClaimTotalEntries = response.totalEntries
                // Keep the display caches in sync so the post-celebration dashboard
                // shows the fresh totals (not the pre-claim snapshot).
                cachedBackendTotalEntries = response.totalEntries
                cachedBackendStreakDay = response.streakDay
                cachedBackendClaimedToday = true

                // Update local streak cache — only NOW mark as claimed
                var updatedStreak = streak
                updatedStreak.currentDay = response.streakDay
                updatedStreak.lastClaimedDate = Date()
                updatedStreak.totalEntriesEarned = response.totalEntries
                if let mc = response.monthlyCurrent { updatedStreak.monthlyCurrent = mc }
                if let wc = response.weeklyCurrent { updatedStreak.weeklyCurrent = wc }
                if let lc = response.lifetimeCount { updatedStreak.lifetimeCount = lc }
                try? container.storage.save(updatedStreak, for: streakStorageKey)
                claimedToday = true
                Avafli.clearOfflineClaimRetry()

                // V2 auto-claim routing (Day 1 AND Day 2+, unified — the
                // celebration modal is gone): the celebration already played at
                // mount off the PREDICTED grant — reconcile the staged numbers
                // with the real response. In the normal case they're identical,
                // so nothing visibly changes; a mismatch silently corrects the
                // readouts. Day 1 only differs in the toast headline
                // ("YOU'RE IN!" instead of "YOU'RE ON A ROLL!").
                if auto {
                    pendingRevealGrant = grant
                    preClaimTotalEntries = response.totalEntries - (grant.baseEntries + grant.bonusEntries)
                    state = .streak(updatedStreak, response.entries, ladder)
                    // Safety net: if no prediction was staged pre-mount
                    // (e.g. the status fetch was offline), the dashboard's
                    // onAppear found nothing pending — fire the reveal now.
                    armCelebrationReveal()
                    isClaimingDaily = false
                    return
                }

                let celebrationMilestone = response.milestone ?? response.monthlyMilestone
                if let milestone = celebrationMilestone {
                    state = .milestoneCelebration(milestone, grant)
                    
                    // Track milestone analytics
                    container.analytics?.trackStreakMilestone(
                        day: milestone.day,
                        bonusEntries: milestone.bonusEntries
                    )
                    if let badge = milestone.badge {
                        container.analytics?.track(
                            event: "avafli_badge_earned",
                            properties: [
                                "badge": badge,
                                "milestone_day": milestone.day,
                                "bonus_entries": milestone.bonusEntries
                            ]
                        )
                    }
                } else {
                    state = .dailyConfirmed(grant, totalEntries: response.totalEntries)
                }

                var analyticsProperties: [String: Any] = [
                    "day": response.streakDay,
                    "entries": response.entries
                ]
                if let weeklyBonus = response.weeklyBonusEntries {
                    analyticsProperties["weekly_bonus"] = weeklyBonus
                }
                if let monthlyBonus = response.monthlyBonusEntries {
                    analyticsProperties["monthly_bonus"] = monthlyBonus
                }
                if let milestone = response.milestone {
                    analyticsProperties["milestone_day"] = milestone.day
                    analyticsProperties["milestone_bonus"] = milestone.bonusEntries
                    if let badge = milestone.badge {
                        analyticsProperties["milestone_badge"] = badge
                    }
                }
                
                container.analytics?.track(
                    event: AvafliAnalyticsEvent.dailyEntryClaimed,
                    properties: analyticsProperties
                )
            } catch {
                isClaimingDaily = false

                switch Self.claimFailureResolution(for: error, auto: auto, hasRegistered: hasRegistered) {
                case .alreadyClaimedNotice:
                    // The backend already holds today's entry (another device
                    // beat us between the status fetch and the claim) and local
                    // state didn't know. Sync the claimed state and TELL the
                    // user — this rejection used to be swallowed silently.
                    Logger.shared.log("Already claimed today — syncing local state", level: .info)
                    // The entry exists server-side — a queued retry is moot.
                    Avafli.clearOfflineClaimRetry()
                    var updatedStreak = streak
                    updatedStreak.lastClaimedDate = Date()
                    try? container.storage.save(updatedStreak, for: streakStorageKey)
                    claimedToday = true
                    // Roll back the predicted celebration NUMBERS — the
                    // prediction was built on a stale total. The reveal state
                    // itself stays (no animation replay); the re-load silently
                    // corrects the total readout.
                    pendingRevealGrant = nil
                    preClaimTotalEntries = nil
                    state = .streak(updatedStreak, entries, ladder)
                    showDashboardNotice(AvafliV2Strings.alreadyEnteredToday, showsRetry: false)
                    // Cached totals are one claim behind — re-load to pull the
                    // authoritative streak/total. One-shot: never loop if
                    // status + claim keep disagreeing.
                    if !didResyncAfterAlreadyClaimed {
                        didResyncAfterAlreadyClaimed = true
                        Task { await load() }
                    }

                case .geoBlocked:
                    // Dedicated "Not available in your location" state.
                    state = .error(.geoBlocked)

                case .sessionExpired:
                    // Dead session (silent refresh failed) — dedicated state
                    // with RETRY, never the generic empty state.
                    state = .error(.authenticationRequired)

                case .silentUnclaimed:
                    // Auto-claim backend rejection (consent, opt-out…): the
                    // dashboard simply shows the calm unclaimed state.
                    Logger.shared.log("Auto-claim declined: \(error)", level: .info)
                    claimedToday = false
                    pendingRevealGrant = nil
                    preClaimTotalEntries = nil
                    claimRevealed = false
                    state = .streak(streak, entries, ladder)

                case .surfaceError:
                    // Manual claim, backend REJECTION: surface the error state.
                    // The V2 router renders every non-geo/non-session error as
                    // the friendly empty state — raw backend text is never
                    // shown to users.
                    state = .error((error as? AvafliError) ?? .internalError("\(error)"))

                case .connectionNotice:
                    // Transport failure. HONEST failure handling (2.6.0): no
                    // fabricated local success, no celebration for an entry
                    // that does not exist. The dashboard shows the unclaimed
                    // state with a non-blocking notice and a retry affordance.
                    Logger.shared.log("Claim transport failure — showing retry notice: \(error)", level: .error)
                    // Offline resilience: queue a same-day automatic retry
                    // (connectivity regain / foreground / capped backoff) so a
                    // transient drop can't cost the streak if the user closes
                    // the drawer without tapping TRY AGAIN.
                    Avafli.enqueueOfflineClaimRetry(for: error)
                    claimedToday = false
                    pendingRevealGrant = nil
                    preClaimTotalEntries = nil
                    claimRevealed = false
                    state = .streak(streak, entries, ladder)
                    showDashboardNotice(AvafliV2Strings.claimNotRecorded, showsRetry: true)
                }
            }
        }
    }

    // MARK: - Claim failure policy

    /// How a failed daily claim resolves, split out as a pure decision so the
    /// policy is unit-testable. There is deliberately NO resolution that
    /// fabricates a local success — a transport failure used to fake a claimed
    /// state and celebrate an entry that was never recorded.
    enum ClaimFailureResolution: Equatable {
        /// Backend says today's entry already exists and local state didn't
        /// know → claimed dashboard + transient "already entered" notice.
        case alreadyClaimedNotice
        /// Backend geo-fence rejection → dedicated geo-blocked state.
        case geoBlocked
        /// Dead session (token refresh failed) → dedicated retry state.
        case sessionExpired
        /// Auto-claim backend rejection → calm unclaimed dashboard, no copy.
        case silentUnclaimed
        /// Manual-claim backend rejection → error state (rendered as the
        /// friendly empty state; raw error text never reaches the user).
        case surfaceError
        /// Transport failure → honest unclaimed dashboard + connection notice
        /// with a retry affordance.
        case connectionNotice
    }

    static func claimFailureResolution(for error: Error, auto: Bool, hasRegistered: Bool) -> ClaimFailureResolution {
        if "\(error)".contains("Already claimed") { return .alreadyClaimedNotice }
        guard let avafliError = error as? AvafliError else {
            // URLError and friends — the request never completed.
            return .connectionNotice
        }
        switch avafliError {
        case .geoBlocked:
            return .geoBlocked
        case .authenticationRequired where hasRegistered:
            return .sessionExpired
        case .network:
            return .connectionNotice
        default:
            // Any other backend/SDK rejection (consent, opt-out, suspension…).
            return auto ? .silentUnclaimed : .surfaceError
        }
    }

    // MARK: - Dashboard notices

    /// Shows a transient dashboard notice. Informational notices auto-dismiss
    /// after a few seconds; retry notices persist until acted on or dismissed.
    @MainActor
    private func showDashboardNotice(_ message: String, showsRetry: Bool) {
        let notice = AvafliV2DashboardNotice(message: message, showsRetry: showsRetry)
        dashboardNotice = notice
        if !showsRetry {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.dashboardNotice == notice else { return }
                self.dashboardNotice = nil
            }
        }
    }

    /// TRY AGAIN on the connection notice — re-attempts the daily claim.
    @MainActor
    func retryDailyClaim() {
        dashboardNotice = nil
        claimDailyEntries(auto: true)
    }

    @MainActor
    func dismissDashboardNotice() {
        dashboardNotice = nil
    }

    /// RETRY on the session-expired state: run the registration handshake
    /// again (refresh if possible, else a fresh register) and reload.
    @MainActor
    func retryAfterSessionExpiry() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            await Avafli.reregisterDevice(configuration: container.configuration)
            await load()
        }
    }

    /// The total entries from the last claim response (cached for dailyConfirmed screen)
    private var lastClaimTotalEntries: Int = 0

    /// Dismiss the milestone celebration and proceed to the confirmation screen
    @MainActor
    func dismissMilestoneCelebration() {
        guard case let .milestoneCelebration(_, grant) = state else { return }
        state = .dailyConfirmed(grant, totalEntries: lastClaimTotalEntries)
    }

    /// Dismiss the daily entries confirmation and close the SDK
    @MainActor
    func dismissDailyConfirmation() {
        guard case let .dailyConfirmed(grant, _) = state else { return }
        complete(with: grant)
    }

    // MARK: - Winner prize claim

    /// Fire-and-forget daily claim while the winner flow is on screen — the
    /// winner still accrues their streak entries, but nothing is revealed.
    @MainActor
    private func silentDailyClaim() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await container.network.send(ClaimDailyEntriesRequest())
                await MainActor.run {
                    self.cachedBackendClaimedToday = true
                    self.cachedBackendStreakDay = response.streakDay
                    self.cachedBackendTotalEntries = response.totalEntries
                    self.claimedToday = true
                }
                Logger.shared.log("Silent daily claim during winner flow: +\(response.entries)", level: .debug)
                Avafli.clearOfflineClaimRetry()
            } catch {
                Logger.shared.log("Silent daily claim declined during winner flow: \(error)", level: .debug)
                Avafli.enqueueOfflineClaimRetry(for: error)
            }
        }
    }

    /// Splash CONTINUE → the claim form.
    @MainActor
    func winnerClaimContinue() {
        guard case .winnerClaim = state else { return }
        winnerClaimStep = .form
    }

    /// DONE on the post-submit share screen → the confirmation screen.
    @MainActor
    func winnerShareDone() {
        guard case let .share(claimNumber, submittedAt) = winnerClaimStep else { return }
        winnerClaimStep = .confirmation(claimNumber: claimNumber, submittedAt: submittedAt)
    }

    /// One-shot guard so the story is attached at most once (the share screen
    /// fires on DONE, close, AND disappear so a typed story is never lost).
    private var didAttachClaimStory = false

    /// Sends the post-submit "please share a little" story via the
    /// attachClaimStory callable. FIRE-AND-FORGET with one retry: the claim is
    /// already submitted, so a failure never blocks and never surfaces an
    /// error. Blank stories are dropped.
    @MainActor
    func attachClaimStory(_ story: String) {
        let trimmed = story.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !didAttachClaimStory else { return }
        didAttachClaimStory = true
        Task { [weak self] in
            guard let self else { return }
            for attempt in 1...2 {
                do {
                    let response = try await self.container.network.send(
                        AttachClaimStoryRequest(story: trimmed)
                    )
                    Logger.shared.log(
                        "Claim story attached (saved: \(response.saved))", level: .debug
                    )
                    return
                } catch {
                    Logger.shared.log(
                        "attachClaimStory attempt \(attempt) failed: \(error)",
                        level: attempt == 2 ? .error : .info
                    )
                    if attempt == 1 {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }
            }
        }
    }

    /// SUBMIT on the claim form. Success → confirmation screen. A backend
    /// "Not the winner"/"Already submitted" rejection falls back to the normal
    /// dashboard silently (logged); transport failures surface inline.
    @MainActor
    func submitPrizeClaim(_ form: AvafliPrizeClaimForm) {
        guard case let .winnerClaim(claim) = state, !isSubmittingClaim else { return }
        guard form.isValid else { return }
        claimSubmitError = nil
        isSubmittingClaim = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await container.network.send(SubmitPrizeClaimRequest(
                    giveawayId: claim.giveawayId,
                    firstName: form.trimmed(\.firstName),
                    lastName: form.trimmed(\.lastName),
                    // Wire format: the bare 10 digits (or nil when blank) —
                    // isValid already guarantees blank-or-normalizable.
                    phone: form.normalizedPhone,
                    street: form.trimmed(\.street),
                    apt: form.trimmed(\.apt).isEmpty ? nil : form.trimmed(\.apt),
                    city: form.trimmed(\.city),
                    state: form.trimmed(\.state),
                    zip: form.trimmed(\.zip),
                    country: form.country,
                    photoBase64: form.photoBase64,
                    // The optional likeness/promo checkbox (2.9) — always sent.
                    // The story rides attachClaimStory AFTER submit instead.
                    promoConsentGranted: form.authorizesLikeness
                ))
                isSubmittingClaim = false
                submittedClaimForm = form
                // 2.9: the share step comes AFTER submit — the claim is safe,
                // so closing the share screen loses nothing.
                winnerClaimStep = .share(
                    claimNumber: response.claimNumber,
                    submittedAt: response.submittedAt
                )
                container.analytics?.track(
                    event: "avafli_prize_claim_submitted",
                    properties: ["giveaway_id": claim.giveawayId, "claim_number": response.claimNumber]
                )
            } catch {
                isSubmittingClaim = false
                let message = "\(error)"
                if message.contains("Not the winner") || message.contains("Already submitted") {
                    // Stale/duplicate winner state — never trap the user in the
                    // claim flow. Fall back to the normal dashboard silently.
                    Logger.shared.log("Prize claim rejected (\(message)) — falling back to dashboard", level: .info)
                    suppressWinnerClaim = true
                    state = .loading
                    await load()
                    return
                }
                Logger.shared.log("Prize claim submit failed: \(error)", level: .error)
                claimSubmitError = "Something went wrong. Please check your connection and try again."
            }
        }
    }

    // MARK: - Completion

    @MainActor
    private func complete(with grant: DailyEntryGrant) {
        state = .completed(grant)
        container.analytics?.trackExperienceClosed(giveawayId: activeGiveaway?.id)
        completion(.success(grant))
    }
}
