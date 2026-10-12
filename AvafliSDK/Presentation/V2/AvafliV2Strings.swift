//
//  AvafliV2Strings.swift
//  AvafliSDK
//
//  Every user-facing error / notice string in the V2 experience, in one place
//  (the "User Message (UI)" column of the Master Field List). Views never
//  inline this copy — they reference these constants, so wording changes
//  happen here and nowhere else. Raw backend messages and
//  AvafliError.errorDescription are for logs only and are NEVER rendered to
//  users.
//

import Foundation

enum AvafliV2Strings {

    // MARK: - Email capture

    /// Inline error under the email field (after touch or a submit attempt).
    static let invalidEmail = "Please enter a valid email address."
    /// The submit network call failed — the user stays on the capture screen.
    static let emailSubmitFailed = "Something went wrong sending your email. Please try again."

    // MARK: - Winner claim form (step 1)

    static let invalidFirstName = "Please enter a valid first name."
    static let invalidLastName = "Please enter a valid last name."
    static let invalidPhone = "Please enter a valid 10-digit mobile number."

    // MARK: - Prize claim: email-ownership code (3.2.0)

    /// Subtitle on the claim code screen. The SDK never holds the raw address
    /// — `maskedEmail` is the backend-masked one from the prizeClaim block.
    static func claimCodeSubtitle(maskedEmail: String?) -> String {
        let masked = maskedEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "Enter the 6-digit code we sent to \(masked.isEmpty ? "your email" : masked)"
    }
    /// Small inline status while the send is in flight / after a real send.
    static let claimCodeSending = "Sending your code…"
    static let claimCodeSent = "Code sent"
    static let claimCodeRetry = "Try again"
    /// The resend action while its cooldown is running.
    static func claimCodeResendCountdown(seconds: Int) -> String {
        let s = max(seconds, 0)
        return "Send a new code in \(s / 60):\(String(format: "%02d", s % 60))"
    }
    /// Help line under the resend action; the second half is a mailto link.
    static let claimCodeHelp = "Can't get to this email? "
    static let claimCodeHelpLink = "Contact info@avafli.com"
    static let claimCodeHelpMailto = "mailto:info@avafli.com"
    /// `code_mismatch`. Without a count the adoption mismatch copy is used.
    static func claimCodeMismatch(attemptsRemaining: Int?) -> String {
        guard let left = attemptsRemaining else { return codeIncorrect }
        return "That code didn't match. \(left) \(left == 1 ? "try" : "tries") left."
    }
    /// `fresh_code_sent` normally shows the server's own message; this is the
    /// fallback when that message is empty.
    static let claimCodeFreshSent = "That code can no longer be used, so we sent you a new one. Check your email."
    static func claimCodeResendCooldown(seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Please wait a moment before requesting another code." }
        return "Please wait \(seconds) \(seconds == 1 ? "second" : "seconds") before requesting another code."
    }
    static let claimCodeSendLimit = "You've requested several codes. Please try again in a little while, or contact info@avafli.com."
    static let claimCodeSendFailed = "We couldn't send your code just now. Please try again in a minute."
    static let claimCodeNoEmailOnFile = "We don't have an email on file for this account. Contact info@avafli.com to claim your prize."
    static let claimCodeUnreachable = "We couldn't reach the server. Check your connection and try again."

    // MARK: - Adoption code entry

    /// Three-way code-error taxonomy, matched across the SDKs. The backend sends
    /// distinguishable failures (a `deadline-exceeded` "expired" error, a
    /// `resource-exhausted` "too many attempts" error, and a generic mismatch);
    /// the SDK maps them to these constants — raw backend text is never rendered.
    /// The code screen stays up throughout, so all three point at "Send a new code".
    static let codeExpired = "That code expired. Tap \"Send a new code\" to get a fresh one."
    static let codeTooManyAttempts = "Too many attempts. Tap \"Send a new code\" to get a fresh one."
    static let codeIncorrect = "That code didn't match. Check the email and try again."
    /// A failed resend keeps the code screen up with this inline error.
    static let resendFailed = "Couldn't send a new code. Check your connection and try again."
    /// Subtitle on the code screen when an ABANDONED adoption is re-staged
    /// (`adoptionPending` on the register response → restageAdoption re-sends
    /// a fresh code). The SDK never stored the typed email, so the copy names
    /// the inbox generically.
    static let adoptionReentrySubtitle = "Let's pick up where you left off. We just sent a fresh 6-digit code to your email — enter it to finish linking your streak."

    // MARK: - Email verification (soft gate — dismissible, never blocks play)

    /// Persistent dashboard chip shown while a freshly-typed email is unverified.
    static let verifyEmailChip = "Verify your email"
    /// Header + subtitle on the verification screen (reuses the adoption code UI).
    static let verifyEmailHeader = "Verify your email"
    static let verifyEmailSubtitle = "Enter the 6-digit code we sent to your inbox so you're eligible to win."
    /// Brief transient confirmation after a successful verification.
    static let verifyEmailSuccess = "Email verified ✓"

    // MARK: - Dashboard notices (transient, non-blocking)

    /// The backend rejected a claim as already-claimed when local state
    /// thought today was still open (e.g. another device claimed first).
    static let alreadyEnteredToday = "You've already entered today. Come back tomorrow to keep your streak going!"
    /// Transport failure during the daily claim — shown with a retry
    /// affordance; the dashboard stays honestly UNCLAIMED.
    static let claimNotRecorded = "We couldn't record today's entry. Check your connection and try again."
    static let retryAction = "TRY AGAIN"

    // MARK: - Geo-blocked state

    static let geoBlockedHeadline = "Not available in your location"
    static let geoBlockedBody = "This promotion is only available to users located in the United States. Please check your location settings or try again from an eligible location."

    // MARK: - Session expired state

    static let sessionExpired = "Your session has expired. Please try again."
    static let sessionExpiredRetry = "RETRY"

    // MARK: - RTD opt-out (delete-my-data confirmation)

    // (2.9.5: the "Privacy choices" entry-point string is gone with its
    // how-it-works link — the delete path is reached through the Privacy
    // Policy webview's own delete section via the winr://delete bridge.)
    static let optOutTitle = "Delete my data & stop participating"
    /// 3.2.0: deletion blocks this email and device for 24 hours, not forever
    /// (Rules §9, Terms §5.2, Privacy §6).
    static let optOutBody = "This permanently erases your information and ends your participation. Entries and streaks are forfeited and cannot be restored. You can join again as a new participant after 24 hours."
    static let optOutConfirm = "DELETE MY DATA"
    static let optOutCancel = "Cancel"
    /// Brief success state shown before the experience dismisses itself.
    static let optOutSuccess = "Your data has been deleted."
    /// The opt-out network call failed — the user stays on the confirmation
    /// step and can retry. We never pretend the deletion succeeded.
    static let optOutFailed = "Something went wrong. Please check your connection and try again."

    // MARK: - Generic friendly empty state (all other errors collapse here)

    static let emptyHeadline = "Nothing to see here yet"
    static let emptyBody = "Check back soon for your next chance to win!"
    static let close = "CLOSE"
    static let closeLowercase = "Close"
}

// MARK: - Field validation

/// Client-side field validation shared by the capture screen and the winner
/// claim form. The server revalidates everything; these rules exist so the
/// user hears about a problem inline instead of via a failed round-trip.
enum AvafliV2FieldValidation {

    /// The SDK's canonical email shape check (same pattern the tests have
    /// always asserted): local@domain.tld with a 2+ letter TLD.
    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Names: non-empty when trimmed, at most 50 characters, containing only
    /// unicode letters, spaces, apostrophes (straight or curly), hyphens, and
    /// periods — and at least one actual letter ("--" is not a name).
    static func isValidName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50 else { return false }
        guard name.contains(where: { $0.isLetter }) else { return false }
        let allowedPunctuation: Set<Character> = [" ", "'", "\u{2019}", "-", "."]
        return name.allSatisfy { $0.isLetter || allowedPunctuation.contains($0) }
    }

    /// US 10-digit mobile normalization: strip every non-digit; an 11-digit
    /// value with a leading country "1" keeps its last 10. Returns the bare
    /// 10 digits, or nil when the input can't normalize to exactly 10.
    /// Blank input returns nil — OPTIONAL fields must check for blank first.
    static func normalizedUSPhone(_ raw: String) -> String? {
        var digits = raw.filter { $0.isNumber }
        if digits.count == 11, digits.first == "1" {
            digits.removeFirst()
        }
        return digits.count == 10 ? String(digits) : nil
    }
}
