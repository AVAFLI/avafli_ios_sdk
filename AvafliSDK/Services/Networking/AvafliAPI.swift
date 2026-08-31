//
//  AvafliAPI.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

// MARK: - Register Device

struct RegisterDeviceRequest: APIRequest {
    typealias Response = RegisterDeviceResponse

    let apiKey: String
    let deviceFingerprint: String
    let bundleId: String
    let timezone: String
    let platformOS: String
    let sdkVersion: String

    var path: String { "registerDevice" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode([
            "data": [
                "apiKey": apiKey,
                "deviceFingerprint": deviceFingerprint,
                "bundleId": bundleId,
                "timezone": timezone,
                "platformOS": platformOS,
                "sdkVersion": sdkVersion
            ]
        ])
    }
}

struct RegisterDeviceResponse: Decodable {
    let token: String
    let refreshToken: String
    let uuid: String
    let giveaway: GiveawayConfig?
    let claimedToday: Bool?
    let streakDay: Int?
    let totalEntries: Int?
    let sdkConfig: SDKConfigResponse?
    /// True when this device/person has opted out (RTD) — never auto-present.
    let optedOut: Bool?
    /// Present only when this person is the drawn winner of one of this
    /// publisher's giveaways (winner prize-claim flow).
    let prizeClaim: PrizeClaimBlock?
    /// Soft email-verification signal. `false` = the user typed a brand-new email
    /// that hasn't been confirmed yet (show the "Verify your email" chip). ABSENT
    /// for verified users, partner-passed emails, adoption-verified users, and
    /// users with no email — only an explicit `false` counts as "unverified".
    /// Never gates play; affects prize-draw eligibility only (server-side).
    let emailVerified: Bool?
    /// True when this device started a verification-gated adoption (typed an
    /// existing account's email, was sent a 6-digit code) but never finished it.
    /// The next open calls `restageAdoption` and re-shows the code screen with
    /// "pick up where you left off" copy. OPTIONAL — absent from current prod.
    let adoptionPending: Bool?
}

// MARK: - SDK Config (server-driven copy & branding)

struct SDKConfigResponse: Codable {
    let branding: SDKBrandingConfig?
    let copy: SDKCopyConfig?
    let media: SDKMediaConfig?  // NEW
    /// Publisher/app display name (server-fed). Used wherever copy names the
    /// publisher — e.g. the claim review's likeness checkbox. OPTIONAL —
    /// absent falls back to the host app's bundle display name.
    let appName: String?
    let rulesUrl: String?
    let ageGateEnabled: Bool?
    let ageGateMinAge: Int?
    /// Experience behavior (V2 auto-open flow). Absent → SDK defaults apply.
    let experience: ExperienceConfig?
    /// Publisher share link (app-store / landing page) used by the winner
    /// share step's social actions. OPTIONAL — absent from current prod; the
    /// share actions degrade to text-only when missing.
    let shareUrl: String?
    /// Google Places API key (Places API New) for claim-address autocomplete.
    /// OPTIONAL — absent means the street field stays a plain text field.
    let placesApiKey: String?
}

/// Server-driven experience behavior flags.
struct ExperienceConfig: Codable {
    /// Auto-present the experience on the first app-open of the day (default true).
    let autoOpenEnabled: Bool?
    /// How many times an unregistered (no-email) user sees the auto-presented
    /// experience before it goes quiet (default 3 — MVP decision).
    let unregisteredImpressionCap: Int?
    /// Dismissal requires an explicit tap; never auto-fade (default true).
    let requireDismissClick: Bool?
    /// Show the "WE HAVE A WINNER!" banner on the dashboard. DEFAULT OFF —
    /// absent/false hides it (Aug 31 GTM decision: keeps the GOT IT button
    /// above the fold on mobile). Admins enable it per publisher when there's
    /// a winner worth showcasing.
    let winnerBannerEnabled: Bool?
}

struct SDKBrandingConfig: Codable {
    let primaryColor: String?
    let secondaryColor: String?
    let backgroundColor: String?
    let logoUrl: String?
    let fontFamily: String?
}

struct SDKCopyConfig: Codable {
    // Nested per-screen copy (new format from backend)
    let emailCapture: EmailCaptureCopy?
    let streakDashboard: StreakDashboardCopy?
    let alreadyClaimed: AlreadyClaimedCopy?
    let bonusEntries: BonusEntriesCopy?
    let dailyConfirmed: DailyConfirmedCopy?
    let milestone: MilestoneCopy?
    let completed: CompletedCopy?
    let error: ErrorCopy?
    let howItWorks: HowItWorksCopy?
    let loading: LoadingCopy?
    
    // Flat fields for backward compat (old SDK versions)
    let welcomeTitle: String?
    let welcomeSubtitle: String?
    let dailyClaimButton: String?
    let streakMessage: String?
    let emailConsentText: String?
    let ageGateText: String?
    let rulesLinkText: String?
}

struct EmailCaptureCopy: Codable {
    let prizeHeadline: String?   // NEW — overrides auto-generated prize text
    let title: String?           // "WIN $500 CASH!"
    let subtitle: String?        // "Just submit this entry form for your FREE chance to win."
    let emailLabel: String?      // "Email"
    let emailPlaceholder: String?// "Ex. johndoe@gmail.com"
    let ageGateText: String?     // "I confirm I am 18 years of age or older"
    let submitButton: String?    // "ENTER NOW"
    let rulesPrefix: String?     // "By entering, you agree to the"
    let rulesLinkText: String?   // "Official Rules"
    let emailConsentText: String?// "Get notified about prizes and rewards"
}

struct StreakDashboardCopy: Codable {
    let prizeHeadline: String?   // NEW — overrides "WIN $500 CASH!" text
    let streakMessage: String?
    let upcomingLabel: String?
    let claimButton: String?
    let dayRewardLabel: String?  // "Day {day} reward" — {day} replaced at runtime
    let claimDescription: String?// "Claim {entries} entries for today's visit..."
    let entriesLabel: String?
    let bonusProgressLabel: String?
    let weekLabel: String?
    let monthLabel: String?
    let bonusEarnedText: String?
}

struct AlreadyClaimedCopy: Codable {
    let title: String?
    let subtitle: String?
    let doneButton: String?
}

struct BonusEntriesCopy: Codable {
    let title: String?
    let subtitle: String?        // "Watch a short video to double today's entries!"
    let prizeHeadline: String?   // Overrides auto-generated "WIN $X CASH!" text
    let confirmedLabel: String?  // Overrides "Entries Confirmed" label
    let watchButton: String?     // "WATCH AD TO DOUBLE ENTRIES"
    let skipText: String?        // "No thanks, continue with {entries} entries"
}

struct DailyConfirmedCopy: Codable {
    let title: String?           // "Entries Claimed!"
    let subtitle: String?        // "+{entries} entries added"
    let totalLabel: String?      // "Total Entries"
    let continueButton: String?  // "Continue"
}

struct MilestoneCopy: Codable {
    let title: String?
    let subtitle: String?        // "Day {day} streak — +{bonus} bonus entries!"
    let continueButton: String?
}

struct CompletedCopy: Codable {
    let title: String?
    let subtitle: String?        // "+{total} entries added to this month's drawing."
    let closeButton: String?
}

struct ErrorCopy: Codable {
    let title: String?
    let subtitle: String?
    let closeButton: String?
}

struct HowItWorksCopy: Codable {
    let title: String?
    let subtitle: String?
    let step1Title: String?
    let step1Desc: String?
    let step2Title: String?
    let step2Desc: String?
    let step3Title: String?
    let step3Desc: String?
    let step4Title: String?
    let step4Desc: String?
    let tipText: String?
    let gotItButton: String?
}

struct LoadingCopy: Codable {
    let text: String?
}

// MARK: - Media Configuration

struct SDKMediaConfig: Codable {
    let emailCapture: ScreenMedia?
    let streakDashboard: ScreenMedia?
    let bonusEntries: ScreenMedia?
    let dailyConfirmed: ScreenMedia?
    let milestone: ScreenMedia?
    let completed: ScreenMedia?
    let howItWorks: ScreenMedia?
}

struct ScreenMedia: Codable {
    let imageUrl: String?
    let lottieUrl: String?
}

// MARK: - Refresh Token

struct RefreshTokenRequest: APIRequest {
    typealias Response = RefreshTokenResponse

    let refreshToken: String

    var path: String { "refreshToken" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode(["data": ["refreshToken": refreshToken]])
    }
}

struct RefreshTokenResponse: Decodable {
    let token: String
    let refreshToken: String
    let expiresIn: Int
}

struct GiveawayConfig: Codable {
    let id: String
    let title: String
    let prizeDescription: String
    let prizeValue: Double
    let streakLadder: [Int]
    let doublingEnabled: Bool
    let maxDailyBaseEntries: Int
    let rulesUrl: String
    let startDate: String
    let endDate: String
    let streakConfig: StreakConfigAPI
    let milestones: [MilestoneConfigAPI]?
    /// Publisher-configurable prize art for the V2 prize card. Absent → the SDK
    /// renders the bundled default cash hero with "WIN $X" overlay.
    let prizeImageUrl: String?
    /// "daily" (default) = consecutive-day streak that resets on a miss.
    /// "visit" = visit-count streak for low-frequency apps; never resets.
    let streakMode: String?
    /// Most recent drawn winner for this giveaway chain — drives the
    /// "WE HAVE A WINNER!" banner + winners dialog. Absent → no banner. Since
    /// the Aug 31 GTM decision the banner ALSO requires the admin-set
    /// sdkConfig.experience.winnerBannerEnabled flag (default off).
    let latestWinner: GiveawayWinner?

    init(
        id: String, title: String, prizeDescription: String, prizeValue: Double,
        streakLadder: [Int], doublingEnabled: Bool, maxDailyBaseEntries: Int,
        rulesUrl: String, startDate: String, endDate: String,
        streakConfig: StreakConfigAPI, milestones: [MilestoneConfigAPI]? = nil,
        prizeImageUrl: String? = nil,
        streakMode: String? = nil, latestWinner: GiveawayWinner? = nil
    ) {
        self.id = id; self.title = title; self.prizeDescription = prizeDescription
        self.prizeValue = prizeValue; self.streakLadder = streakLadder
        self.doublingEnabled = doublingEnabled; self.maxDailyBaseEntries = maxDailyBaseEntries
        self.rulesUrl = rulesUrl; self.startDate = startDate; self.endDate = endDate
        self.streakConfig = streakConfig; self.milestones = milestones
        self.prizeImageUrl = prizeImageUrl
        self.streakMode = streakMode; self.latestWinner = latestWinner
    }
}

struct GiveawayWinner: Codable {
    let name: String          // display name, e.g. "Catherine C."
    let location: String?     // e.g. "Brooklyn, New York"
    let avatarUrl: String?
    let awardedAt: String?    // "yyyy-MM-dd"

    /// "August 20, 2026" — falls back to the raw string if not yyyy-MM-dd.
    var awardedAtDisplay: String? {
        guard let awardedAt else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: awardedAt) else { return awardedAt }
        let out = DateFormatter()
        out.dateFormat = "MMMM d, yyyy"
        out.locale = Locale(identifier: "en_US_POSIX")
        return out.string(from: date)
    }
}

struct StreakConfigAPI: Codable {
    let weeklyResetDay: Int
    let monthlyResetDay: Int
    // Legacy fields (kept for backward compat)
    let weeklyBonusThreshold: Int?
    let weeklyBonusEntries: Int?
    let monthlyBonusThreshold: Int?
    let monthlyBonusEntries: Int?
    // New monthly milestone tiers
    let monthlyMilestones: [MilestoneConfigAPI]?
}

// MARK: - Submit Email

struct SubmitEmailRequest: APIRequest {
    typealias Response = SubmitEmailResponse

    let email: String
    /// State of the "I confirm I am 18 years of age or older" checkbox. Always sent —
    /// the backend uses its PRESENCE to tell a 2.4.0+ client from a legacy one.
    let ageConfirmed: Bool
    /// State of the marketing-consent checkbox: the publisher's permission to send
    /// marketing email. Declining blocks neither entry nor winner contact.
    let marketingConsent: Bool

    init(email: String, ageConfirmed: Bool, marketingConsent: Bool) {
        self.email = email
        self.ageConfirmed = ageConfirmed
        self.marketingConsent = marketingConsent
    }

    var path: String { "submitEmail" }
    var method: String { "POST" }
    var body: Data? {
        let data: [String: Any] = [
            "email": email,
            "ageConfirmed": ageConfirmed,
            "marketingConsent": marketingConsent
        ]
        return try? JSONSerialization.data(withJSONObject: ["data": data])
    }
}

struct SubmitEmailResponse: Decodable {
    let success: Bool
    /// When the email matched an existing account under this publisher (another
    /// device/SDK), the backend adopts that canonical user so the streak follows
    /// the person across devices. If `adopted` is true, switch to these
    /// credentials. Absent on a normal first-time submit.
    let adopted: Bool?
    /// The typed email matches an EXISTING account and the OTP gate is on: no
    /// merge happened. Show the 6-digit code screen and call verifyAdoptionCode.
    let verificationRequired: Bool?
    let uuid: String?
    let token: String?
    let refreshToken: String?
    /// Soft email-verification signal for a freshly-typed email. `false` = not yet
    /// confirmed (show the "Verify your email" chip). ABSENT for verified /
    /// partner-passed / adoption-verified / no-email users. See RegisterDeviceResponse.
    let emailVerified: Bool?
    /// The backend just dispatched a verification code to the typed inbox.
    let emailVerificationSent: Bool?
}

/// Completes a verification-gated adoption with the emailed 6-digit code.
/// The response is the same shape as an adopted SubmitEmailResponse.
struct VerifyAdoptionCodeRequest: APIRequest {
    typealias Response = SubmitEmailResponse
    let code: String
    var path: String { "verifyAdoptionCode" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONSerialization.data(withJSONObject: ["data": ["code": code]])
    }
}

/// Re-stages an abandoned verification-gated adoption (`adoptionPending` on the
/// register response): the backend re-sends a fresh 6-digit code to the email
/// this device originally typed, and the SDK re-shows the code screen with
/// "pick up where you left off" copy. Mirrors verifyAdoptionCode's envelope.
struct RestageAdoptionRequest: APIRequest {
    typealias Response = RestageAdoptionResponse
    var path: String { "restageAdoption" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONSerialization.data(withJSONObject: ["data": [:] as [String: String]])
    }
}

struct RestageAdoptionResponse: Decodable {
    let sent: Bool
}

// MARK: - Email verification (soft gate)

/// Confirms a freshly-typed email with the 6-digit code sent to that inbox.
/// Mirrors the adoption code envelope, but this flow is a SOFT gate — it never
/// blocks play, it only makes the person eligible for the prize draw. Throws on
/// a bad code; the thrown message carries the "expired"/"attempts"/mismatch
/// keyword that `codeErrorMessage(for:)` maps to user copy.
struct ConfirmEmailVerificationRequest: APIRequest {
    typealias Response = ConfirmEmailVerificationResponse
    let code: String
    var path: String { "confirmEmailVerification" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONSerialization.data(withJSONObject: ["data": ["code": code]])
    }
}

struct ConfirmEmailVerificationResponse: Decodable {
    let verified: Bool
}

/// Re-sends the email-verification code to the inbox on file. No arguments.
struct ResendEmailVerificationRequest: APIRequest {
    typealias Response = ResendEmailVerificationResponse
    var path: String { "resendEmailVerification" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONSerialization.data(withJSONObject: ["data": [:] as [String: String]])
    }
}

struct ResendEmailVerificationResponse: Decodable {
    let sent: Bool
}

// MARK: - Submit User Profile

struct SubmitUserProfileRequest: APIRequest {
    typealias Response = SubmitUserProfileResponse
    
    let firstName: String?
    let lastName: String?
    let phone: String?
    let smsConsent: Bool
    let maidId: String?
    let publisherUserId: String?
    
    var path: String { "submitUserProfile" }
    var method: String { "POST" }
    var body: Data? {
        var data: [String: Any] = ["smsConsent": smsConsent]
        
        if let firstName = firstName {
            data["firstName"] = firstName
        }
        if let lastName = lastName {
            data["lastName"] = lastName
        }
        if let phone = phone {
            data["phone"] = phone
        }
        if let maidId = maidId {
            data["maidId"] = maidId
        }
        if let publisherUserId = publisherUserId {
            data["publisherUserId"] = publisherUserId
        }
        
        return try? JSONSerialization.data(withJSONObject: ["data": data])
    }
}

struct SubmitUserProfileResponse: Decodable {
    let success: Bool
}

// MARK: - Claim Daily Entries

struct ClaimDailyEntriesRequest: APIRequest {
    typealias Response = ClaimDailyEntriesResponse

    let timezone: String = TimeZone.current.identifier
    let platformOS: String = AvafliConstants.platformOS
    let sdkVersion: String = AvafliConstants.sdkVersion

    var path: String { "claimDailyEntries" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode([
            "data": [
                "timezone": timezone,
                "platformOS": platformOS,
                "sdkVersion": sdkVersion
            ]
        ])
    }
}

struct ClaimDailyEntriesResponse: Decodable {
    let entries: Int
    let streakDay: Int
    let totalEntries: Int
    let weeklyBonusEntries: Int?
    let monthlyBonusEntries: Int?
    let milestone: MilestoneAward?
    let monthlyCurrent: Int?
    let weeklyCurrent: Int?
    let lifetimeCount: Int?
    let monthlyMilestone: MilestoneAward?
}

/// Milestone award returned when a user hits a streak milestone day
struct MilestoneAward: Codable {
    let day: Int
    let bonusEntries: Int
    let badge: String?
}

/// Milestone configuration from giveaway
struct MilestoneConfigAPI: Codable {
    let day: Int
    let bonusEntries: Int
    let badge: String?
}

// MARK: - Register Push Token

struct RegisterPushTokenRequest: APIRequest {
    typealias Response = RegisterPushTokenResponse

    let token: String
    let platform: String

    var path: String { "registerPushToken" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode([
            "data": [
                "token": token,
                "platform": platform,
            ]
        ])
    }
}

struct RegisterPushTokenResponse: Decodable {
    let success: Bool
}

// MARK: - Get Active Giveaway

struct GetActiveGiveawayRequest: APIRequest {
    typealias Response = GetActiveGiveawayResponse

    var path: String { "getActiveGiveaway" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode(["data": [:] as [String: String]])
    }
}

struct GetActiveGiveawayResponse: Decodable {
    let giveaway: GiveawayConfig?
    let claimedToday: Bool?
    let streakDay: Int?
    let totalEntries: Int?
    let sdkConfig: SDKConfigResponse?
    let monthlyCurrent: Int?
    let weeklyCurrent: Int?
    let lifetimeCount: Int?
    /// Whether the backend has a confirmed email + consent for this user. Lets the
    /// email-capture gate recognize a user even if the local "submitted" flag was
    /// lost (e.g. app reinstall) — the backend is the source of truth.
    let emailConsentStatus: Bool?
    /// True when this person has opted out (RTD) — the SDK must never auto-present.
    let optedOut: Bool?
    /// Present only when this person is the drawn winner of one of this
    /// publisher's giveaways and the winner record is still claimable.
    /// `status == "pending"` drives the winner splash → claim form flow;
    /// `"submitted"` means the form was already sent (normal dashboard shows).
    let prizeClaim: PrizeClaimBlock?
    /// Soft email-verification signal. `false` = a brand-new typed email awaiting
    /// confirmation (show the "Verify your email" chip). ABSENT for verified /
    /// partner-passed / adoption-verified / no-email users. Never gates play.
    let emailVerified: Bool?
    /// Abandoned verification-gated adoption (see RegisterDeviceResponse).
    /// Decoded here too because an already-registered device refreshes via
    /// getActiveGiveaway and never re-runs registerDevice. OPTIONAL.
    let adoptionPending: Bool?
}

// MARK: - Prize Claim (winner flow)

/// FIXED API contract, mirroring `PrizeClaimBlock` in the backend's types.ts.
struct PrizeClaimBlock: Codable {
    let status: String            // "pending" | "submitted"
    let giveawayId: String
    let prizeDescription: String
    let prizeValue: Double
    /// Display-only masked winning email ("d********r@winr.example.com") for
    /// the claim form's locked field. Absent from older backends.
    let maskedEmail: String?
    let claimNumber: String?      // present when submitted
    let submittedAt: String?      // ISO date, when submitted

    var isPending: Bool { status == "pending" }

    // Lenient decode: a malformed block (null/missing prize fields from an
    // older winner doc) must degrade gracefully, never fail the whole
    // giveaway response and take the dashboard down with it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        giveawayId = try c.decodeIfPresent(String.self, forKey: .giveawayId) ?? ""
        prizeDescription = try c.decodeIfPresent(String.self, forKey: .prizeDescription) ?? "Your prize"
        prizeValue = try c.decodeIfPresent(Double.self, forKey: .prizeValue) ?? 0
        maskedEmail = try c.decodeIfPresent(String.self, forKey: .maskedEmail)
        claimNumber = try c.decodeIfPresent(String.self, forKey: .claimNumber)
        submittedAt = try c.decodeIfPresent(String.self, forKey: .submittedAt)
    }
}

struct SubmitPrizeClaimRequest: APIRequest {
    typealias Response = SubmitPrizeClaimResponse

    let giveawayId: String
    let firstName: String
    let lastName: String
    let phone: String?
    let street: String
    let apt: String?
    let city: String
    let state: String
    let zip: String
    let country: String
    let photoBase64: String?
    /// The OPTIONAL likeness/promo checkbox on the review screen ("ALMOST
    /// DONE!"). Always sent — submit is never gated on it (2.9 decision).
    /// The story no longer rides this payload — see AttachClaimStoryRequest.
    let promoConsentGranted: Bool

    var path: String { "submitPrizeClaim" }
    var method: String { "POST" }
    var body: Data? {
        var data: [String: Any] = [
            "giveawayId": giveawayId,
            "firstName": firstName,
            "lastName": lastName,
            "street": street,
            "city": city,
            "state": state,
            "zip": zip,
            "country": country,
            "promoConsentGranted": promoConsentGranted,
        ]
        if let phone, !phone.isEmpty { data["phone"] = phone }
        if let apt, !apt.isEmpty { data["apt"] = apt }
        if let photoBase64 { data["photoBase64"] = photoBase64 }
        return try? JSONSerialization.data(withJSONObject: ["data": data])
    }
}

struct SubmitPrizeClaimResponse: Decodable {
    let claimNumber: String
    let submittedAt: String   // ISO date
}

/// Attaches the optional "please share a little" story AFTER the claim was
/// submitted (2.9 — the share step moved post-submit, so the story can no
/// longer ride the submitPrizeClaim payload). Fire-and-forget from the SDK:
/// a failure never blocks or surfaces — the claim itself is already safe.
struct AttachClaimStoryRequest: APIRequest {
    typealias Response = AttachClaimStoryResponse
    let story: String
    var path: String { "attachClaimStory" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONSerialization.data(withJSONObject: ["data": ["story": story]])
    }
}

struct AttachClaimStoryResponse: Decodable {
    let saved: Bool
}

// MARK: - Opt Out (RTD — Right To Delete)

struct OptOutRequest: APIRequest {
    typealias Response = OptOutResponse

    var path: String { "optOut" }
    var method: String { "POST" }
    var body: Data? {
        try? JSONEncoder().encode(["data": [:] as [String: String]])
    }
}

struct OptOutResponse: Decodable {
    let success: Bool
    let optedOut: Bool
}
