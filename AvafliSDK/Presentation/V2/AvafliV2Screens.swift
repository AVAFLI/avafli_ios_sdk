//
//  AvafliV2Screens.swift
//  AvafliSDK
//
//  The V2 experience screens, matched to Joe's Figma flows (Solitaire / GLI /
//  Slice examples): new-user capture, the dashboard (whose mount IS the daily
//  celebration — Day 1 and Day 2+ alike), and how-it-works. Publisher can
//  customize ONLY: logo, prize image, primary color. Everything else is
//  hardcoded to the design or derived from the prize.
//

import SwiftUI

// MARK: - Root router

struct AvafliV2ExperienceRoot: View {
    @ObservedObject var viewModel: AvafliExperienceViewModel

    private var accent: Color {
        AvafliV2Accent(hex: viewModel.sdkConfig?.branding?.primaryColor).color
    }
    private var logoUrl: String? {
        viewModel.sdkConfig?.branding?.logoUrl
    }
    private var rulesUrl: String? {
        viewModel.activeGiveawayConfig?.rulesUrl ?? viewModel.sdkConfig?.rulesUrl
    }

    @State private var drawerAppeared = false
    @State private var showWinnerModal = false
    /// The in-app legal webview (2.9.4): every Official Rules / Privacy
    /// Policy link in the experience presents here instead of Safari.
    @State private var legalSheet: AvafliV2LegalSheet?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Dimmed host app behind the drawer.
                Color.black.opacity(drawerAppeared ? 0.45 : 0)
                    .ignoresSafeArea()
                drawerContent
                    .frame(maxWidth: .infinity)
                    .frame(height: geo.size.height * 0.90)
                    .background(AvafliV2Color.gunmetal)
                    .clipShape(AvafliV2TopRoundedShape(radius: 30))
                    .offset(y: drawerAppeared ? 0 : geo.size.height)

                if showWinnerModal, let winner = viewModel.activeGiveawayConfig?.latestWinner {
                    AvafliV2WinnerModal(accent: accent, winner: winner) {
                        showWinnerModal = false
                    }
                    .transition(.opacity)
                }

                // Delete-my-data destructive confirmation. Mounted at the
                // ROOT (2.9.4) so the privacy webview's winr://delete bridge
                // can raise it from any screen; renders nothing while idle.
                AvafliV2OptOutDialog(optOut: viewModel.optOutCoordinator)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: drawerAppeared)
        }
        .ignoresSafeArea()
        // 2.9.4: EVERY legal link in the experience — the capture sentence's
        // AttributedString links, the OFFICIAL RULES • PRIVACY POLICY rows,
        // and the how-it-works privacy entry point — funnels through this
        // handler and opens IN-APP in the legal webview sheet instead of
        // Safari. Non-legal URLs keep the system behavior.
        .environment(\.openURL, OpenURLAction { url in
            if let sheet = AvafliV2LegalRouting.sheet(for: url, rulesUrl: rulesUrl) {
                legalSheet = sheet
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $legalSheet) { sheet in
            AvafliV2LegalWebView(
                sheet: sheet,
                accent: accent,
                onClose: { legalSheet = nil },
                onDeleteRequested: {
                    // The privacy page's delete section navigated to
                    // winr://delete: drop the sheet and raise the EXISTING
                    // destructive confirmation (rendered at this root, so it
                    // survives the sheet dismissing beneath it).
                    legalSheet = nil
                    viewModel.optOutCoordinator.begin()
                }
            )
        }
        .onAppear {
            drawerAppeared = true
            // Decode the confetti-burst GIF off-main NOW so mounting it at the
            // reveal beat (dashboard mount) is instant.
            AvafliV2GifAsset.prewarm("confetti-burst")
            // Same idea for the publisher's remote art: normally already warm
            // (the SDK warms it at registration/refresh), but a drawer opened
            // before that landed gets one more chance to have it decoded before
            // the prize card paints.
            AvafliV2ImageWarmer.prewarm(viewModel.activeGiveawayConfig?.prizeImageUrl)
            AvafliV2ImageWarmer.prewarm(logoUrl)
        }
    }

    @ViewBuilder private var drawerContent: some View {
        ZStack {
            AvafliV2Color.gunmetal

            switch viewModel.state {
            case .loading:
                AvafliV2LoadingView()
            case .noActiveGiveaway:
                // Nothing to pitch (or opted out) — quiet empty state.
                emptyState
            case let .error(error):
                // Geo-block and dead-session get DEDICATED states (Master
                // Field List "User Message (UI)"); every other error keeps the
                // friendly empty state — raw AvafliError/backend text is never
                // rendered to users.
                switch error {
                case .geoBlocked:
                    geoBlockedState
                case .authenticationRequired:
                    sessionExpiredState
                default:
                    emptyState
                }
            case let .codeEntry(email):
                AvafliV2CodeEntryView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    email: email,
                    isVerifying: viewModel.isVerifyingCode,
                    errorText: viewModel.codeError,
                    onSubmit: { viewModel.submitVerificationCode($0) },
                    onResend: { viewModel.resendVerificationCode() },
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.requestDismiss() }
                )
            case .emailVerification:
                // Soft email verification: SAME code-entry screen as adoption,
                // but with verify copy, the confirm/resend callables, and a
                // Cancel (onClose) that returns to the dashboard — this flow is
                // dismissible and never gates play.
                AvafliV2CodeEntryView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    email: "",
                    headline: AvafliV2Strings.verifyEmailHeader.uppercased(),
                    subtitle: AvafliV2Strings.verifyEmailSubtitle,
                    isVerifying: viewModel.isVerifyingCode,
                    errorText: viewModel.codeError,
                    onSubmit: { viewModel.confirmEmailVerification($0) },
                    onResend: { viewModel.resendEmailVerification() },
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.hideEmailVerification() }
                )
            case .adoptionReentry:
                // Abandoned adoption re-entry (2.9): the backend re-sent a
                // fresh code via restageAdoption — same code-entry screen,
                // "pick up where you left off" copy. Verify path is identical
                // to the normal adoption gate.
                AvafliV2CodeEntryView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    email: "",
                    subtitle: AvafliV2Strings.adoptionReentrySubtitle,
                    isVerifying: viewModel.isVerifyingCode,
                    errorText: viewModel.codeError,
                    onSubmit: { viewModel.submitVerificationCode($0) },
                    onResend: { viewModel.resendRestagedAdoption() },
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.requestDismiss() }
                )
            case .emailCapture:
                AvafliV2CaptureView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    giveaway: viewModel.activeGiveawayConfig,
                    isSubmitting: viewModel.isSubmittingEmail,
                    // Nested publisher copy first, then the flat legacy field. The wire
                    // key stays `emailConsentText` for compatibility; its VALUE is the
                    // marketing-consent copy, publisher-named by the backend.
                    marketingConsentText: viewModel.sdkConfig?.copy?.emailCapture?.emailConsentText
                        ?? viewModel.sdkConfig?.copy?.emailConsentText,
                    // Nested per-screen age-gate copy first, then the flat legacy
                    // field; the fallback label is built from ageGateMinAge below.
                    ageGateText: viewModel.sdkConfig?.copy?.emailCapture?.ageGateText
                        ?? viewModel.sdkConfig?.copy?.ageGateText,
                    ageGateMinAge: viewModel.sdkConfig?.ageGateMinAge,
                    prefilledEmail: viewModel.prefilledEmail,
                    submitError: viewModel.emailSubmitError,
                    onSubmit: { email, ageConfirmed, marketingConsent in
                        viewModel.submitEmail(email, ageConfirmed: ageConfirmed, marketingConsent: marketingConsent)
                    },
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.requestDismiss() }
                )
            case let .streak(streak, entriesToday, ladder):
                // Pinned from the FIRST frame: while today is unclaimed OR the reveal
                // hasn't played, show yesterday's numbers. Without the claimedToday
                // clause there's a flash of the raw post-claim server state during
                // the network round-trip, and elements flip at different times.
                let preReveal = !viewModel.claimRevealed
                    && (viewModel.pendingRevealGrant != nil || !viewModel.claimedToday)
                AvafliV2DashboardView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    giveaway: viewModel.activeGiveawayConfig,
                    streakDay: streak.currentDay,
                    totalEntries: preReveal
                        ? (viewModel.preClaimTotalEntries ?? streak.totalEntriesEarned)
                        : viewModel.displayTotalEntries,
                    entriesToday: entriesToday,
                    ladder: ladder,
                    claimedToday: viewModel.claimedToday,
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.requestDismiss() },
                    onWinnerTap: { showWinnerModal = true },
                    showWinnerBanner: viewModel.sdkConfig?.experience?.winnerBannerEnabled == true,
                    showVerifyEmailChip: viewModel.emailUnverified,
                    onVerifyEmailTap: { viewModel.showEmailVerification() },
                    pendingClaimEntries: viewModel.pendingRevealGrant.map { $0.baseEntries + $0.bonusEntries },
                    revealed: viewModel.claimRevealed
                )
                // Day 2+: the celebration IS the first visible frame — the
                // reveal flips one imperceptible beat after mount so SwiftUI
                // has a "before" frame for every transition to animate from.
                .onAppear { viewModel.armCelebrationReveal() }
            case let .dailyConfirmed(grant, totalEntries):
                // Legacy arrivals only (manual/offline claim paths) — the
                // celebration modal is GONE. Route to the already-celebrated
                // dashboard: claimed state, toast-first come-back bar, GOT IT
                // closes the experience.
                AvafliV2DashboardView(
                    accent: accent,
                    logoUrl: logoUrl,
                    rulesUrl: rulesUrl,
                    giveaway: viewModel.activeGiveawayConfig,
                    streakDay: viewModel.displayStreakDay,
                    totalEntries: totalEntries,
                    entriesToday: grant.baseEntries,
                    ladder: viewModel.displayLadder,
                    claimedToday: true,
                    onInfo: { viewModel.showHowItWorks() },
                    onClose: { viewModel.requestDismiss() },
                    pendingClaimEntries: grant.baseEntries + grant.bonusEntries,
                    revealed: true
                )
            case let .completed(grant):
                ZStack {
                    AvafliV2DashboardView(
                        accent: accent,
                        logoUrl: logoUrl,
                        rulesUrl: rulesUrl,
                        giveaway: viewModel.activeGiveawayConfig,
                        streakDay: viewModel.displayStreakDay,
                        totalEntries: viewModel.displayTotalEntries,
                        entriesToday: grant.baseEntries,
                        ladder: viewModel.displayLadder,
                        claimedToday: true,
                        onInfo: { viewModel.showHowItWorks() },
                        onClose: { viewModel.requestDismiss() }
                    )
                }
            case let .winnerClaim(claim):
                // This person is the drawn winner: splash → claim form →
                // confirmation, instead of the dashboard.
                AvafliV2WinnerClaimFlow(
                    viewModel: viewModel,
                    accent: accent,
                    logoUrl: logoUrl,
                    appName: viewModel.sdkConfig?.appName,
                    shareUrl: viewModel.sdkConfig?.shareUrl,
                    placesApiKey: viewModel.sdkConfig?.placesApiKey,
                    claim: claim
                )
            case .milestoneCelebration:
                // Milestones are parked (backend never sends them); fall back to dashboard.
                Color.clear.onAppear { viewModel.showDashboardAfterCelebration() }
            case .howItWorks:
                AvafliV2HowItWorksView(
                    accent: accent,
                    logoUrl: logoUrl,
                    day1Entries: viewModel.displayLadder.first ?? 10,
                    visitMode: viewModel.activeGiveawayConfig?.streakMode == "visit",
                    onDone: { viewModel.hideHowItWorks() },
                    onClose: { viewModel.requestDismiss() }
                )
            }
        }
        .overlay(alignment: .top) {
            // Transient dashboard notice (duplicate same-day entry, claim
            // transport failure). Non-blocking: floats over the dashboard,
            // which stays fully interactive beneath it.
            if let notice = viewModel.dashboardNotice, case .streak = viewModel.state {
                AvafliV2NoticeBanner(
                    message: notice.message,
                    retryTitle: notice.showsRetry ? AvafliV2Strings.retryAction : nil,
                    onRetry: { viewModel.retryDailyClaim() },
                    onDismiss: { viewModel.dismissDashboardNotice() }
                )
                .padding(.horizontal, 20)
                .padding(.top, 68)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.dashboardNotice)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(AvafliV2Strings.emptyHeadline)
                .font(AvafliV2Font.inter(20, .bold))
                .foregroundColor(.white)
            Text(AvafliV2Strings.emptyBody)
                .font(AvafliV2Font.inter(14))
                .foregroundColor(AvafliV2Color.textTertiary)
            AvafliV2PillButton(accent: accent, title: AvafliV2Strings.close) {
                viewModel.requestDismiss()
            }
            .frame(width: 220)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Backend geo-fence rejection — the person needs to know WHY there is
    /// nothing here, not a generic "check back soon".
    private var geoBlockedState: some View {
        VStack(spacing: 12) {
            Text(AvafliV2Strings.geoBlockedHeadline)
                .font(AvafliV2Font.inter(20, .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Text(AvafliV2Strings.geoBlockedBody)
                .font(AvafliV2Font.inter(14))
                .foregroundColor(AvafliV2Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            AvafliV2PillButton(accent: accent, title: AvafliV2Strings.close) {
                viewModel.requestDismiss()
            }
            .frame(width: 220)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Silent token refresh failed — a dead session, not an empty catalogue.
    /// RETRY re-runs the registration handshake and reloads.
    private var sessionExpiredState: some View {
        VStack(spacing: 12) {
            Text(AvafliV2Strings.sessionExpired)
                .font(AvafliV2Font.inter(20, .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            AvafliV2PillButton(accent: accent, title: AvafliV2Strings.sessionExpiredRetry) {
                viewModel.retryAfterSessionExpiry()
            }
            .frame(width: 220)
            .padding(.top, 12)
            Button(action: { viewModel.requestDismiss() }) {
                Text(AvafliV2Strings.closeLowercase)
                    .font(AvafliV2Font.inter(14))
                    .foregroundColor(AvafliV2Color.textTertiary)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cold-start skeleton

/// Cold start (nothing cached to paint from): a SKELETON of the dashboard
/// rather than a centered spinner.
///
/// The drawer auto-opens ahead of its sequential network calls (registerDevice
/// → getActiveGiveaway → claim). A bare spinner made that wait read as "nothing
/// is here yet"; blocking out the real layout — header, prize card, streak
/// tiles, come-back bar, pill — in the drawer's own gunmetal reads as the
/// content arriving, at identical latency. The warm path never gets here at
/// all: a cached giveaway + streak paints the real dashboard immediately (see
/// `AvafliExperienceViewModel.hydrateFromCache`).
struct AvafliV2LoadingView: View {
    /// Half-period of the breath: 0.45 → 0.85 over ~900ms, then back.
    private static let pulseHalfPeriod: Double = 0.9

    var body: some View {
        // Self-driving pulse (the same clock the confetti runs on). An implicit
        // `repeatForever` animation freezes on its target value here — the
        // skeleton mounts inside the drawer's own slide-up transaction, which
        // swallows the repeat — so the opacity is computed from the timeline
        // instead. One shared value keeps every block in phase, so the screen
        // reads as one surface breathing, not a field of blinking rectangles.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            skeleton.opacity(Self.pulseOpacity(at: timeline.date))
        }
    }

    /// A sine is its own ease-in-out autoreverse: 0.45 ↔ 0.85, one full breath
    /// every `2 * pulseHalfPeriod`.
    static func pulseOpacity(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let phase = (sin(t * .pi / pulseHalfPeriod - .pi / 2) + 1) / 2
        return 0.45 + 0.40 * phase
    }

    private var skeleton: some View {
        VStack(spacing: 15) {
            AvafliV2TabGrabber().padding(.top, 15)

            // Header: "?" circle • logo • "X" circle.
            HStack {
                block(36, 36, radius: 18)
                Spacer()
                block(140, 34)
                Spacer()
                block(36, 36, radius: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)

            // Prize card.
            block(nil, 200, radius: 10)
                .padding(.horizontal, 22)
                .padding(.top, 15)

            // Streak rail: three tiles.
            HStack {
                block(106, 134, radius: 10)
                Spacer()
                block(106, 134, radius: 10)
                Spacer()
                block(106, 134, radius: 10)
            }
            .padding(.horizontal, 22)

            // Come-back bar (full-bleed, like the real one).
            block(nil, 71, radius: 0)

            // CTA pill.
            block(nil, 54, radius: 27)
                .padding(.horizontal, 30)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AvafliV2Color.gunmetal)
    }

    /// A blocked-out element: 8% white on the drawer's gunmetal.
    private func block(_ width: CGFloat?, _ height: CGFloat, radius: CGFloat = 6) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.white.opacity(0.08))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

// MARK: - New-user capture ("VISIT. EARN. WIN.")

struct AvafliV2CaptureView: View {
    /// Offline fallback only. The backend normally ships a publisher-named string
    /// ("I agree to receive marketing emails from Acme") in
    /// `copy.emailCapture.emailConsentText`, and stores that same string as the
    /// audit record — so what we render and what we file away cannot disagree.
    /// This literal is what we show when no config has been fetched yet.
    static let defaultMarketingConsentText = "I agree to receive marketing emails from this app"

    let accent: Color
    let logoUrl: String?
    let rulesUrl: String?
    let giveaway: GiveawayConfig?
    let isSubmitting: Bool
    /// Server-driven marketing-consent copy; nil falls back to `defaultMarketingConsentText`.
    let marketingConsentText: String?
    /// Server-driven age-gate copy (publisher config). When present and non-empty
    /// it is rendered verbatim; otherwise the label is BUILT from `ageGateMinAge`.
    let ageGateText: String?
    /// Server-driven minimum age used to build the fallback age-gate label when
    /// `ageGateText` is absent. Nil → 18. NEVER hardcode 18 when config says otherwise.
    let ageGateMinAge: Int?
    /// Partner-authenticated email (AvafliUser.email). Non-nil AND well-formed →
    /// the field renders pre-filled and READ-ONLY: Avafli links accounts across
    /// devices by email, so a free-typed address lets a user attach themselves to
    /// someone else's record. Malformed or nil → the editable field, unchanged.
    let prefilledEmail: String?
    /// Inline submit-failure copy from the view model (a failed network submit
    /// keeps the user here with this error and lets them retry).
    var submitError: String? = nil
    /// (email, ageConfirmed, marketingConsent)
    let onSubmit: (String, Bool, Bool) -> Void
    let onInfo: () -> Void
    let onClose: () -> Void

    @State private var email = ""
    /// Set once editing has ended (or the keyboard's go/return was tapped) so
    /// the inline invalid-email error never fires while the user is typing
    /// their first characters.
    @State private var emailTouched = false
    @FocusState private var emailFocused: Bool
    /// Unchecked by default — the age gate requires an affirmative action.
    @State private var isAdult = false
    /// Marketing opt-in. This governs ONLY the publisher marketing to this
    /// person — it has nothing to do with contacting them if they win, which
    /// happens regardless. Declining does not block entry, so it is deliberately
    /// excluded from `canSubmit`. UNCHECKED by default (changed Aug 2026):
    /// pre-ticked consent boxes are invalid under GDPR and disfavored by US
    /// state regulators; consent must be an affirmative act.
    @State private var wantsMarketing = false

    /// Basic shape check only — the server revalidates. Its job here is to decide
    /// pre-fill vs editable, so a partner bug degrades to the normal typed flow
    /// instead of locking a garbage value into a read-only field.
    private var lockedEmail: String? {
        guard let e = prefilledEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              e.contains("@"), e.contains("."), e.count >= 6, e.count <= 254
        else { return nil }
        return e
    }

    private var day1Entries: Int { giveaway?.streakLadder.first ?? 10 }

    /// The age-gate checkbox label. Publisher-provided `ageGateText` wins when
    /// present and non-empty; otherwise the label is built from `ageGateMinAge`
    /// (default 18) — the 18 is never hardcoded when config says otherwise.
    private var ageGateLabel: String {
        if let text = ageGateText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        let minAge = ageGateMinAge ?? 18
        return "I confirm I am \(minAge) years of age or older"
    }
    private var typedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSubmit: Bool {
        isAdult && (lockedEmail != nil || AvafliV2FieldValidation.isValidEmail(typedEmail))
    }

    /// The inline error under the email field: a failed submit's message wins;
    /// otherwise the invalid-email error, shown only once the field has been
    /// touched (editing ended with a non-empty value) — never while the user
    /// is typing their first characters.
    private var emailError: String? {
        if let submitError { return submitError }
        guard lockedEmail == nil else { return nil }
        if emailTouched, !typedEmail.isEmpty, !AvafliV2FieldValidation.isValidEmail(typedEmail) {
            return AvafliV2Strings.invalidEmail
        }
        return nil
    }

    /// Anchor id for the scroll-to-focused-email behavior.
    private static let emailAnchor = "avafli-capture-email"

    /// The legal sentence with "Official Rules" and "Privacy Policy" as
    /// underlined tappable links — the ONE legal surface on this screen since
    /// 2.9.2 (the separate links row is gone here). "Official Rules" opens
    /// `rulesUrl` (giveaway rulesUrl falling back to the sdkConfig one);
    /// "Privacy Policy" opens the actual privacy policy
    /// (`AvafliConstants.privacyURL` — no server field carries one). Since
    /// 2.9.4 both open IN-APP: the taps travel through the environment's
    /// OpenURLAction, which the experience root intercepts into the legal
    /// webview sheet. A missing rulesUrl leaves that phrase underlined but
    /// inert, matching the old row's no-op behavior.
    private var legalText: AttributedString {
        var text = AttributedString("Your email lets us contact you if you win. By entering you agree to the Official Rules & Privacy Policy")
        let destinations: [(phrase: String, url: URL?)] = [
            ("Official Rules", rulesUrl.flatMap { URL(string: $0) }),
            ("Privacy Policy", URL(string: AvafliConstants.privacyURL)),
        ]
        for (phrase, url) in destinations {
            guard let range = text.range(of: phrase) else { continue }
            text[range].underlineStyle = .single
            if let url {
                text[range].link = url
            }
        }
        return text
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 2.9: flat dark background — the SAME color as the streak
            // dashboard drawer (gunmetal), replacing the old blue radial glow.
            AvafliV2Color.gunmetal.ignoresSafeArea()

            GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    AvafliV2Header(logoUrl: logoUrl, onInfo: onInfo, onClose: onClose)
                        .padding(.top, 18)

                    VStack(spacing: 4) {
                        // 2.9.3: "EARN." (with its period) renders in the
                        // publisher's PRIMARY brand color; "VISIT." and
                        // "WIN." stay white (Joe's Figma). The segments
                        // without an explicit color inherit the VStack's
                        // white below.
                        (Text("VISIT. ") + Text("EARN.").foregroundColor(accent) + Text(" WIN."))
                            .font(AvafliV2Font.inter(40, .black))
                            .kerning(-1.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("VISIT DAILY.  EARN ENTRIES.  WIN BIG!")
                            .font(AvafliV2Font.inter(15, .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)

                    prizeStrip

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            emailField
                                .id(Self.emailAnchor)
                            if let emailError {
                                Text(emailError)
                                    .font(AvafliV2Font.inter(13))
                                    .foregroundColor(AvafliV2Color.errorRed)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 4)
                                    .transition(.opacity)
                            }
                        }

                        checkbox(ageGateLabel, isOn: isAdult) {
                            isAdult.toggle()
                        }

                        checkbox(marketingConsentText ?? Self.defaultMarketingConsentText, isOn: wantsMarketing) {
                            wantsMarketing.toggle()
                        }

                        AvafliV2PillButton(
                            accent: accent,
                            title: "CLAIM MY \(day1Entries) ENTRIES",
                            isLoading: isSubmitting
                        ) {
                            onSubmit(lockedEmail ?? email.trimmingCharacters(in: .whitespacesAndNewlines), isAdult, wantsMarketing)
                        }
                        .opacity(canSubmit ? 1 : 0.5)
                        .disabled(!canSubmit || isSubmitting)
                    }
                    .padding(.horizontal, 22)

                    // Pushes the legal block to the drawer's bottom edge (the
                    // content VStack is pinned to at least the visible height
                    // below). On short screens or with the keyboard up the
                    // spacer collapses to its minimum gap and the page simply
                    // scrolls — the block never overlaps the CLAIM pill.
                    Spacer(minLength: 24)

                    VStack(spacing: 3) {
                        // 2.9.2: ONE legal surface on this screen — the sentence
                        // itself carries the tappable Official Rules / Privacy
                        // Policy links; the separate OFFICIAL RULES • PRIVACY
                        // POLICY row is gone (capture screen only — every other
                        // screen keeps its AvafliV2LegalLinks row).
                        Text(legalText)
                            .font(AvafliV2Font.inter(12))
                            .foregroundColor(AvafliV2Color.textTertiary)
                            .tint(AvafliV2Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Text("Powered by © Avafli")
                            .font(AvafliV2Font.inter(12))
                            .foregroundColor(AvafliV2Color.textTertiary)
                    }
                    .padding(.bottom, 24)
                }
                // Bottom-anchored legal block: the content is at least as tall
                // as the visible area, so the Spacer above the legal block can
                // expand and pin it to the bottom. Taller-than-screen content
                // (small devices, large type, keyboard padding) exceeds the
                // minimum and scrolls exactly as before.
                .frame(minHeight: geo.size.height)
                // Keyboard-aware: the whole page (fields + CLAIM pill) stays
                // scrollable and reachable with the keyboard up.
                .avafliKeyboardAvoiding()
            }
            .onChange(of: emailFocused) { focused in
                if focused {
                    AvafliKeyboardScroll.scrollAction(proxy)(Self.emailAnchor)
                }
            }
            }
            }
        }
    }

    /// The one checkbox treatment on this screen. Both the age gate and the email
    /// consent row go through it so they are identical by construction — box size,
    /// tint, spacing and tap target can't drift apart.
    private func checkbox(_ label: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                // 2.9.3: publisher-primary tint (Joe's Figma) — checked is an
                // accent-filled box with a contrasting check mark; unchecked
                // keeps an accent-tinted outline.
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(accent.opacity(isOn ? 1 : 0.8), lineWidth: 1.5)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(AvafliV2Accent.contrastingMark(on: accent))
                            .opacity(isOn ? 1 : 0)
                    )
                    .frame(width: 20, height: 20)
                Text(label)
                    .font(AvafliV2Font.inter(14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// PRIZE-derived white strip (Joe's Day-1 examples):
    /// cash → "$1,000.00 CASH PRIZE"; other → "Win a $500 Amazon Gift Card" + value.
    private var prizeStrip: some View {
        let description = giveaway?.prizeDescription ?? ""
        let value = Int(giveaway?.prizeValue ?? 0)
        let isCash = AvafliV2PrizeText.isCash(description: description)
        return VStack(spacing: 0) {
            Text(AvafliV2PrizeText.stripHeadline(description: description, value: value))
                .font(AvafliV2Font.inter(isCash ? 24 : 23, .black))
                .kerning(-0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // The value subtitle is redundant when the prize name already
            // states the amount ("$500 Amazon Gift Card").
            if !isCash && AvafliV2PrizeText.showsValueLine(description: description, value: value) {
                Text("$\(value.formatted()).00 Value!")
                    .font(AvafliV2Font.inter(16))
            }
        }
        .foregroundColor(AvafliV2Color.gunmetal)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    private var emailField: some View {
        HStack(spacing: 10) {
            Image("avafli-mail", bundle: .module)
                .resizable().scaledToFit()
                .frame(width: 22, height: 18)
                .foregroundColor(AvafliV2Color.gunmetal.opacity(0.6))
            if let locked = lockedEmail {
                // Read-only, but VISIBLE: the user must see exactly which address
                // they are consenting for. Text, not a disabled TextField, so no
                // keyboard affordance appears.
                Text(locked)
                    .font(AvafliV2Font.inter(16))
                    .foregroundColor(AvafliV2Color.gunmetal)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(AvafliV2Color.gunmetal.opacity(0.45))
                    .accessibilityLabel("Email provided by this app")
            } else {
                TextField("Enter your email address", text: $email)
                    .font(AvafliV2Font.inter(16))
                    .foregroundColor(AvafliV2Color.gunmetal)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
                    .submitLabel(.go)
                    .onSubmit { emailTouched = true }
                    .onChange(of: emailFocused) { focused in
                        // Editing ended with something typed → the field is
                        // "touched" and the inline error may show.
                        if !focused, !typedEmail.isEmpty { emailTouched = true }
                    }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.75), lineWidth: 2))
        )
    }
}

// MARK: - Return-user dashboard (Day 2+ drawer)

struct AvafliV2DashboardView: View {
    let accent: Color
    let logoUrl: String?
    let rulesUrl: String?
    let giveaway: GiveawayConfig?
    let streakDay: Int
    let totalEntries: Int
    let entriesToday: Int
    let ladder: [Int]
    let claimedToday: Bool
    let onInfo: () -> Void
    let onClose: () -> Void
    var onWinnerTap: (() -> Void)? = nil
    /// "WE HAVE A WINNER!" banner gate — server flag
    /// sdkConfig.experience.winnerBannerEnabled. DEFAULT OFF (absent/false =
    /// hidden) so the GOT IT pill stays above the fold on small screens; the
    /// banner (and the winners dialog behind its + button) only appears when
    /// an admin turned the flag on AND the giveaway carries a latestWinner.
    var showWinnerBanner: Bool = false
    /// Soft email-verification nudge: a persistent, dismissible chip pinned near
    /// the top of the dashboard while a freshly-typed email is unverified. Never
    /// blocks the streak content beneath it.
    var showVerifyEmailChip: Bool = false
    var onVerifyEmailTap: (() -> Void)? = nil
    /// Reveal flow (Day 2+): the claim already succeeded server-side; the UI
    /// mounts pinned to yesterday's numbers and the celebration (tile check +
    /// confetti + totals update, bar → "N ENTRIES ADDED") fires on its own a
    /// beat later — Joe's Slice prototype has no claim tap and no modal.
    var pendingClaimEntries: Int? = nil
    var revealed = true

    private var visitMode: Bool { giveaway?.streakMode == "visit" }
    // Pinned while today is unclaimed OR the reveal hasn't played — matching
    // the router. Without the claimedToday clause the current tile animates
    // at claim-response time, ~1s BEFORE the count-up/toast beat.
    private var preReveal: Bool { !revealed && (pendingClaimEntries != nil || !claimedToday) }

    private func ladderValue(day: Int) -> Int {
        AvafliV2Ladder.entries(day: day, ladder: ladder, milestones: giveaway?.milestones)
    }

    private var nextEntries: Int { ladderValue(day: streakDay + 1) }

    private var railEntries: [AvafliV2RailEntry] {
        var entries: [AvafliV2RailEntry] = []
        let maxDay = max(31, streakDay + 2)
        let milestoneDays: [Int: Int] = Dictionary(
            uniqueKeysWithValues: (giveaway?.milestones ?? []).map { ($0.day, $0.bonusEntries) }
        )
        for day in 1...maxDay {
            let state: AvafliV2RailEntry.TileState =
                day < streakDay ? .completed :
                (day == streakDay ? (preReveal ? .ready : .active) : .locked)
            entries.append(.init(id: "day-\(day)", kind: .day(day: day, entries: ladderValue(day: day), state: state)))
            if let bonus = milestoneDays[day] {
                let label: String
                switch day {
                case 7: label = "1 WEEK"
                case 14: label = "2 WEEK"
                case 21: label = "3 WEEK"
                case 29, 30: label = "1 MONTH"
                default: label = "DAY \(day)"
                }
                let footnote = day == streakDay ? "STARTING TOMORROW" : "STARTING AT \(visitMode ? "VISIT" : "DAY") \(day + 1)"
                entries.append(.init(id: "power-\(day)", kind: .powerUp(label: label, bonus: bonus, footnote: footnote)))
            }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 15) {
            AvafliV2TabGrabber().padding(.top, 15)
            AvafliV2Header(logoUrl: logoUrl, onInfo: onInfo, onClose: onClose)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 15) {
                    if showVerifyEmailChip, let onVerifyEmailTap {
                        AvafliV2VerifyEmailChip(accent: accent, onTap: onVerifyEmailTap)
                            .padding(.horizontal, 22)
                    }
                    if showWinnerBanner, giveaway?.latestWinner != nil, let onWinnerTap {
                        AvafliV2WinnerBanner(onTap: onWinnerTap)
                    }
                    AvafliV2PrizeCard(
                        accent: accent,
                        streakDay: preReveal ? max(streakDay - 1, 1) : streakDay,
                        totalEntries: totalEntries,
                        prizeImageUrl: giveaway?.prizeImageUrl,
                        prizeValue: Int(giveaway?.prizeValue ?? 0),
                        prizeDescription: giveaway?.prizeDescription ?? "",
                        visitMode: visitMode
                    )
                    .padding(.horizontal, 22)

                    AvafliV2StreakRail(
                        accent: accent,
                        entries: railEntries,
                        activeID: "day-\(streakDay)",
                        visitMode: visitMode
                    )

                    AvafliV2ComeBackBar(
                        accent: accent,
                        nextEntries: nextEntries,
                        visitMode: visitMode,
                        // Celebration open: the bar's FIRST visible frame is
                        // the toast — "YOU'RE IN!" on Day 1, "YOU'RE ON A
                        // ROLL!" on Day 2+ — which holds a beat and slides
                        // once to the resting pitch. Non-celebration opens
                        // rest on the pitch with no toast.
                        celebrating: pendingClaimEntries != nil,
                        firstDay: streakDay <= 1,
                        claimedEntries: pendingClaimEntries ?? entriesToday
                    )

                    VStack(spacing: 6) {
                        // Always GOT IT (Slice prototype) — the celebration
                        // plays on its own; the pill only ever closes.
                        AvafliV2PillButton(accent: accent, title: "GOT IT") { onClose() }
                            .padding(.horizontal, 30)
                        AvafliV2LegalLinks(rulesUrl: rulesUrl)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(AvafliV2Color.gunmetal)
    }
}

// MARK: - Verify-email chip (soft gate)

/// Subtle, persistent, tappable pill nudging the user to verify a freshly-typed
/// email. Uses the publisher accent (tinted, not filled — a gentle nudge, not an
/// error), sits inline in the dashboard flow, and never covers streak content.
struct AvafliV2VerifyEmailChip: View {
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 14, weight: .bold))
                Text(AvafliV2Strings.verifyEmailChip)
                    .font(AvafliV2Font.inter(13, .bold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundColor(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(accent.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AvafliV2Strings.verifyEmailChip)
    }
}

// MARK: - How it works

struct AvafliV2HowItWorksView: View {
    let accent: Color
    let logoUrl: String?
    let day1Entries: Int
    var visitMode = false
    let onDone: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                AvafliV2Header(logoUrl: logoUrl, showsBack: true, onBack: onDone, onInfo: {}, onClose: onClose)
                    .padding(.top, 18)

                Text("HOW IT WORKS")
                    .font(AvafliV2Font.inter(26, .black))
                    .kerning(-0.78)
                    .foregroundColor(AvafliV2Color.gunmetal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 39)
                    .background(Color.white.opacity(0.5))

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        item(number: "1", title: "ENTER ONCE",
                             body: "Submit your email to receive \(day1Entries) entries instantly and start your streak.")
                        item(number: "2", title: visitMode ? "KEEP VISITING" : "VISIT EVERY DAY",
                             body: visitMode
                                ? "Simply open the app whenever you like. Your entries are added automatically—no forms or extra steps."
                                : "Simply open the app each day. Your entries are added automatically—no forms or extra steps.")
                        item(number: "3", title: "KEEP YOUR STREAK GROWING",
                             body: visitMode
                                ? "Earn more entries with every visit. The more you come back, the bigger your rewards!"
                                : "Earn more entries with every consecutive visit. The longer your streak, the bigger your daily rewards!")
                    }
                    .padding(.horizontal, 26)

                    Text(visitMode
                        ? "Every visit counts - your streak never resets."
                        : "Don’t miss a day - your streak resets if you do.")
                        .font(AvafliV2Font.inter(20, .bold))
                        .kerning(-0.6)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 22)

                    AvafliV2PillButton(accent: accent, title: "GOT IT - START MY STREAK") { onDone() }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    // (2.9.5: the muted "Privacy choices" fine-print link is
                    // gone — the Privacy Policy links on the capture sentence
                    // and the legal rows keep the delete path findable, all
                    // routing into the in-app privacy webview.)
                }
            }
        }
        .background(AvafliV2Color.panel.ignoresSafeArea())
    }

    private func item(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number).")
                .font(AvafliV2Font.inter(18, .black))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AvafliV2Font.inter(18, .black))
                Text(body)
                    .font(AvafliV2Font.inter(16))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundColor(.white)
    }
}


// MARK: - Delete-my-data confirmation (experience root)

/// The destructive delete-my-data confirmation (and its in-flight / failed /
/// deleted states) — same scrim-plus-card treatment as the winners dialog.
/// Mounted at the experience ROOT since 2.9.4 so the privacy webview's
/// winr://delete bridge can raise it from ANY screen; renders nothing while
/// the coordinator is idle.
struct AvafliV2OptOutDialog: View {
    @ObservedObject var optOut: AvafliV2OptOutCoordinator

    var body: some View {
        ZStack {
            if optOut.phase != .idle {
                dialog
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: optOut.phase)
    }

    private var dialog: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { optOut.cancel() }

            VStack(spacing: 14) {
                if case .done = optOut.phase {
                    Text(AvafliV2Strings.optOutSuccess)
                        .font(AvafliV2Font.inter(18, .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 24)
                } else {
                    Text(AvafliV2Strings.optOutTitle)
                        .font(AvafliV2Font.inter(18, .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Text(AvafliV2Strings.optOutBody)
                        .font(AvafliV2Font.inter(14))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if case let .failed(message) = optOut.phase {
                        Text(message)
                            .font(AvafliV2Font.inter(13))
                            .foregroundColor(AvafliV2Color.errorRed)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AvafliV2PillButton(
                        accent: AvafliV2Color.errorRed,
                        title: AvafliV2Strings.optOutConfirm,
                        isLoading: optOut.phase == .inFlight
                    ) {
                        optOut.confirm()
                    }
                    .padding(.top, 4)

                    Button(action: { optOut.cancel() }) {
                        Text(AvafliV2Strings.optOutCancel)
                            .font(AvafliV2Font.inter(14))
                            .foregroundColor(AvafliV2Color.textTertiary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .disabled(optOut.phase == .inFlight)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(AvafliV2Color.deepCharcoal)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .padding(.horizontal, 24)
        }
    }


}


/// Verification code entry — shown when the typed email matches an EXISTING
/// account and the OTP gate is on. One numeric field, auto-submits at 6 digits.
struct AvafliV2CodeEntryView: View {
    let accent: Color
    let logoUrl: String?
    let rulesUrl: String?
    let email: String
    /// Headline / subtitle default to the adoption copy; the soft email-
    /// verification flow reuses this same screen with its own copy.
    var headline: String = "CHECK YOUR EMAIL"
    var subtitle: String? = nil
    let isVerifying: Bool
    let errorText: String?
    let onSubmit: (String) -> Void
    let onResend: () -> Void
    let onInfo: () -> Void
    let onClose: () -> Void

    @State private var code = ""
    @FocusState private var codeFocused: Bool

    private static let codeAnchor = "avafli-code-field"

    private var resolvedSubtitle: String {
        subtitle ?? "This email is already part of an Avafli streak. Enter the 6-digit code we sent to \(email) to pick it up on this device."
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 2.9.3: flat dark background — same as the capture screen and
            // streak dashboard (gunmetal), replacing the last remaining blue
            // radial top glow (Ryan: gone from EVERY screen).
            AvafliV2Color.gunmetal.ignoresSafeArea()
            ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    AvafliV2Header(logoUrl: logoUrl, onInfo: onInfo, onClose: onClose)
                        .padding(.top, 18)

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(AvafliV2Font.inter(28, .black))
                            .foregroundColor(.white)
                        Text(resolvedSubtitle)
                            .font(AvafliV2Font.inter(14))
                            .foregroundColor(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 26)

                    VStack(spacing: 14) {
                        TextField("••••••", text: $code)
                            .font(AvafliV2Font.inter(22, .bold))
                            .foregroundColor(AvafliV2Color.gunmetal)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)   // keyboard offers the code from Mail
                            .multilineTextAlignment(.center)
                            .focused($codeFocused)
                            .padding(.horizontal, 20)
                            .frame(height: 54)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                            .id(Self.codeAnchor)
                            .onChange(of: code) { newValue in
                                let digits = newValue.filter(\.isNumber)
                                if digits.count > 6 { code = String(digits.prefix(6)) }
                                if digits.count == 6 && !isVerifying { onSubmit(String(digits.prefix(6))) }
                            }

                        if let errorText {
                            Text(errorText)
                                .font(AvafliV2Font.inter(13))
                                .foregroundColor(AvafliV2Color.errorRed)
                                .multilineTextAlignment(.center)
                        }

                        AvafliV2PillButton(accent: accent, title: "VERIFY", isLoading: isVerifying) {
                            let digits = code.filter(\.isNumber)
                            if digits.count == 6 { onSubmit(digits) }
                        }
                        .disabled(isVerifying)

                        Button(action: onResend) {
                            // Two-tone: the question reads as copy, the underlined
                            // action reads as a control.
                            (Text("Didn't get it? ")
                                .foregroundColor(.white.opacity(0.65))
                             + Text("Send a new code")
                                .foregroundColor(Color(red: 0.5, green: 0.69, blue: 1.0))
                                .fontWeight(.bold)
                                .underline())
                                .font(AvafliV2Font.inter(14))
                        }
                    }
                    .padding(.horizontal, 22)

                    Spacer(minLength: 40)

                    // Same legal footer as the capture screen — one consent flow,
                    // one footer; without it the sheet trails off into a void.
                    AvafliV2LegalLinks(rulesUrl: rulesUrl, showPoweredBy: true)
                        .padding(.bottom, 24)
                }
                .frame(minHeight: UIScreen.main.bounds.height * 0.6)
                // Keyboard-aware: field, VERIFY pill, and resend link all stay
                // reachable with the number pad up.
                .avafliKeyboardAvoiding()
            }
            .onChange(of: codeFocused) { focused in
                if focused {
                    AvafliKeyboardScroll.scrollAction(proxy)(Self.codeAnchor)
                }
            }
            }
        }
    }
}
