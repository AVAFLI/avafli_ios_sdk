//
//  AvafliV2Claim.swift
//  AvafliSDK
//
//  Winner prize-claim flow (Joe's stepped Figma design): winner splash →
//  4 form steps + review (AvafliV2ClaimSteps/) → confirmation with the
//  OFFICIAL WINNER card. Shown when prizeClaim.status == "pending".
//  This file keeps the shared pieces: form model, photo/date helpers,
//  splash, confirmation, and the flow root.
//

import SwiftUI
import PhotosUI

// MARK: - Form model + validation

/// The claim form's field values. Kept as a plain value type so validation is
/// unit-testable without any view machinery.
struct AvafliPrizeClaimForm {
    var firstName = ""
    var lastName = ""
    var phone = ""
    var street = ""
    var apt = ""
    var city = ""
    var state = ""
    var zip = ""
    /// Fixed — US-only sweepstakes.
    let country = "United States"
    /// JPEG base64 of the optional attached photo (already downscaled/capped).
    var photoBase64: String?
    // The optional "please share a little" story no longer lives on this form:
    // the share screen comes AFTER submit (2.9) and sends a typed story via
    // the attachClaimStory callable instead.

    /// The ONE remaining review-screen checkbox (2.9): the likeness/promo
    /// release. OPTIONAL — submit is never gated on it, and it defaults to
    /// UNCHECKED (consent must be an affirmative act, same reasoning as the
    /// capture screen's marketing checkbox). Sent as `promoConsentGranted`.
    /// The old "information is accurate" and "agree to Official Rules"
    /// checkboxes are gone; the rules/privacy links stay tappable.
    var authorizesLikeness = false

    func trimmed(_ keyPath: KeyPath<AvafliPrizeClaimForm, String>) -> String {
        self[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidZip(_ zip: String) -> Bool {
        let z = zip.trimmingCharacters(in: .whitespaces)
        return z.count == 5 && z.allSatisfy(\.isNumber)
    }

    // MARK: Per-step validity (stepped flow)

    /// Whether the OPTIONAL phone passes: blank is fine; anything typed must
    /// normalize to a US 10-digit number (leading country "1" allowed).
    var isPhoneEmptyOrValid: Bool {
        trimmed(\.phone).isEmpty || normalizedPhone != nil
    }

    /// The wire value for phone: the bare 10 digits, or nil when blank/invalid.
    var normalizedPhone: String? {
        AvafliV2FieldValidation.normalizedUSPhone(phone)
    }

    /// Step 1 "TELL US ABOUT YOURSELF": valid first + last name (unicode
    /// letters / spaces / apostrophes / hyphens / periods, max 50); phone stays
    /// OPTIONAL but must be a valid 10-digit US number when present. Email is
    /// server-side.
    var isStep1Valid: Bool {
        AvafliV2FieldValidation.isValidName(firstName)
            && AvafliV2FieldValidation.isValidName(lastName)
            && isPhoneEmptyOrValid
    }

    /// Step 2 "WHERE SHOULD WE SEND YOUR PRIZE?": full US shipping address.
    var isStep2Valid: Bool {
        !trimmed(\.street).isEmpty
            && !trimmed(\.city).isEmpty
            && !trimmed(\.state).isEmpty
            && Self.isValidZip(zip)
    }

    // Step 3 (photo) is fully optional — always advanceable. The story lives
    // on the POST-submit share screen (2.9) and never gates anything.

    /// SUBMIT enables when every required field across the steps is present
    /// and the zip is a 5-digit US code. Phone, apartment, photo, story, and
    /// the likeness/promo checkbox are all optional — the review screen's
    /// SUBMIT is always enabled once the steps validated.
    var isValid: Bool {
        isStep1Valid && isStep2Valid
    }

    /// "First L." — the public display name on the winner card.
    var displayName: String {
        let first = trimmed(\.firstName)
        let lastInitial = trimmed(\.lastName).first.map { " \($0)." } ?? ""
        return "\(first)\(lastInitial)"
    }

    static let usStates = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
        "Connecticut", "Delaware", "District of Columbia", "Florida",
        "Georgia", "Hawaii", "Idaho",
        "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana",
        "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada",
        "New Hampshire", "New Jersey", "New Mexico", "New York",
        "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
        "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota",
        "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington",
        "West Virginia", "Wisconsin", "Wyoming",
    ]
}

// MARK: - Photo + date helpers

enum AvafliClaimPhoto {
    static let maxBytes = 5 * 1024 * 1024

    /// Downscales so the long edge is ≤1200px, then JPEG-encodes, stepping the
    /// quality down until the payload fits the 5MB cap.
    static func base64Jpeg(from image: UIImage) -> String? {
        let scaled = downscaled(image, longEdge: 1200)
        var quality: CGFloat = 0.85
        var data = scaled.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxBytes, quality > 0.25 {
            quality -= 0.15
            data = scaled.jpegData(compressionQuality: quality)
        }
        guard let d = data, d.count <= maxBytes else { return nil }
        return d.base64EncodedString()
    }

    static func downscaled(_ image: UIImage, longEdge: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > longEdge, longest > 0 else { return image }
        let scale = longEdge / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

enum AvafliClaimDates {
    /// "AUGUST, 2026" from an ISO date string (falls back to the current date)
    /// — the winner card's award line.
    static func monthYearDisplay(fromISO iso: String?, now: Date = Date()) -> String {
        let date = iso.flatMap(parseISO) ?? now
        let out = DateFormatter()
        out.dateFormat = "MMMM, yyyy"
        out.locale = Locale(identifier: "en_US_POSIX")
        return out.string(from: date).uppercased()
    }

    private static func parseISO(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: value) { return d }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: value) { return d }
        let dayOnly = DateFormatter()
        dayOnly.dateFormat = "yyyy-MM-dd"
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        return dayOnly.date(from: value)
    }
}

// MARK: - Flow root

/// Resolves the publisher/app name used in user-facing copy (the likeness
/// checkbox, the share line): the server-fed `sdkConfig.appName` wins, else
/// the host app's bundle display name, else nil (callers fall back to
/// generic wording).
enum AvafliV2PublisherName {
    static func resolve(sdkAppName: String?, host: String? = hostAppName()) -> String? {
        if let name = sdkAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let host = host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            return host
        }
        return nil
    }

    /// The host app's user-visible name (Info.plist display name, falling
    /// back to the bundle name).
    static func hostAppName() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}

struct AvafliV2WinnerClaimFlow: View {
    @ObservedObject var viewModel: AvafliExperienceViewModel
    let accent: Color
    let logoUrl: String?
    /// Publisher/app display name from sdkConfig (OPTIONAL) — the review
    /// screen's likeness copy. Absent → host app's bundle display name.
    let appName: String?
    /// Publisher share link from sdkConfig (OPTIONAL) — the share screen's
    /// social actions.
    let shareUrl: String?
    /// Google Places key from sdkConfig (OPTIONAL) — street-field autocomplete
    /// on the address step. Absent → plain typing.
    var placesApiKey: String? = nil
    let claim: PrizeClaimBlock

    var body: some View {
        Group {
            switch viewModel.winnerClaimStep {
            case .splash:
                AvafliV2WinnerSplashView(
                    accent: accent,
                    logoUrl: logoUrl,
                    prizeHeadline: AvafliV2PrizeText.stripHeadline(
                        description: claim.prizeDescription,
                        value: Int(claim.prizeValue)
                    ),
                    onContinue: { viewModel.winnerClaimContinue() },
                    onClose: { viewModel.requestDismiss() }
                )
            case .form:
                AvafliV2ClaimStepsFlow(
                    accent: accent,
                    logoUrl: logoUrl,
                    publisherName: AvafliV2PublisherName.resolve(sdkAppName: appName),
                    placesApiKey: placesApiKey,
                    claim: claim,
                    viewModel: viewModel,
                    onClose: { viewModel.requestDismiss() }
                )
            case .share:
                // 2.9: "Please share a little" comes AFTER submit — the claim
                // is already safe on the backend, so closing loses nothing.
                AvafliV2ClaimShareScreen(
                    accent: accent,
                    logoUrl: logoUrl,
                    shareLine: shareLine,
                    shareUrl: shareUrl,
                    onStory: { viewModel.attachClaimStory($0) },
                    onDone: { viewModel.winnerShareDone() },
                    onClose: { viewModel.requestDismiss() }
                )
            case let .confirmation(claimNumber, submittedAt):
                AvafliV2ClaimConfirmationView(
                    accent: accent,
                    logoUrl: logoUrl,
                    form: viewModel.submittedClaimForm,
                    claimNumber: claimNumber,
                    submittedAt: submittedAt,
                    onDone: { viewModel.requestDismiss() }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.winnerClaimStep)
    }

    /// "I just won {prize} in {app}!" — the share screen's prefilled line.
    private var shareLine: String {
        let prize = AvafliV2PrizeText.stripHeadline(
            description: claim.prizeDescription,
            value: Int(claim.prizeValue)
        )
        let app = AvafliV2PublisherName.hostAppName()
        if let app { return "I just won \(prize) in \(app)!" }
        return "I just won \(prize)!"
    }
}

// MARK: - Shared chrome

/// Claim-flow header: publisher logo centered, X close only (no "?").
private struct AvafliClaimHeader: View {
    let logoUrl: String?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            logo
                .frame(height: 60)
                .frame(maxWidth: 210)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image("avafli-close", bundle: .module)
                        .resizable().scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AvafliV2Color.deepCharcoal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder private var logo: some View {
        if let logoUrl, let url = URL(string: logoUrl) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
        } else {
            Text("Avafli")
                .font(AvafliV2Font.inter(28, .black))
                .foregroundColor(.white)
        }
    }
}

/// Dark info card with a leading icon (shield/mail) — splash + confirmation.
/// 2.9.3: SOLID gunmetal-family card with a subtle border (Joe's frames
/// 5369:5594 / 5386:5807), replacing the translucent gray wash.
private struct AvafliClaimInfoCard<Icon: View, Content: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 14) {
            icon
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AvafliV2Color.gunmetal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 22)
    }
}

// MARK: - Winner splash ("CONGRATULATIONS!")

struct AvafliV2WinnerSplashView: View {
    let accent: Color
    let logoUrl: String?
    let prizeHeadline: String
    let onContinue: () -> Void
    let onClose: () -> Void

    /// One-shot: the confetti-burst GIF plays over the screen on mount (the
    /// you-won beat), then removes itself — matching the other SDKs, which
    /// all play drift + burst on the splash.
    @State private var bursting = true

    var body: some View {
        ZStack {
            AvafliV2Color.deepCharcoal

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    AvafliClaimHeader(logoUrl: logoUrl, onClose: onClose)
                        .padding(.top, 18)

                    trophyArt
                        .padding(.top, 4)

                    Text("CONGRATULATIONS!")
                        .font(AvafliV2Font.inter(34, .black))
                        .kerning(-1.0)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                    Text("YOU’RE OUR LATEST WINNER!")
                        .font(AvafliV2Font.inter(17, .black))
                        .kerning(-0.4)
                        .foregroundColor(accent)

                    Text("You’ve won:")
                        .font(AvafliV2Font.inter(14))
                        .foregroundColor(.white)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    // Full-width white strip with the prize-derived headline
                    // (same derivation as the Day-1 capture strip).
                    Text(prizeHeadline)
                        .font(AvafliV2Font.inter(28, .black))
                        .kerning(-0.8)
                        .foregroundColor(AvafliV2Color.gunmetal)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)

                    Text("To process your prize, we just need a few details.")
                        .font(AvafliV2Font.inter(15))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 16)

                    AvafliClaimInfoCard {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 26))
                            .foregroundColor(accent)
                    } content: {
                        Text("Your information is securely collected and only used to verify your prize and announce you as our winner.")
                            .font(AvafliV2Font.inter(13))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 14)

                    AvafliV2PillButton(accent: accent, title: "CONTINUE") { onContinue() }
                        .padding(.horizontal, 30)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                }
            }
            // Joe's dedicated Confetti overlay on the winner splash (frame
            // 5369:5594): the V2 celebration emitter falling over the whole
            // screen from appear. Decorative only — the Canvas never
            // intercepts touches (`allowsHitTesting(false)` in the emitter).
            // (The frame's "AVAFLI PRIZE CLAIM" caption was a canvas
            // label under the mock, NOT part of the UI — no bottom bar here.)
            .overlay(AvafliV2ConfettiView(style: .celebration, count: 32, speed: 0.85))
            .overlay {
                if bursting {
                    AvafliV2GifView("confetti-burst", onFinished: { bursting = false })
                        .frame(width: 280, height: 280)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Trophy over the gold-sparkle art (bundled winner-modal-bg + trophy).
    private var trophyArt: some View {
        ZStack {
            AvafliV2Asset.winnerModalBg
                .resizable().scaledToFill()
                .frame(width: 300, height: 260)
                .clipped()
                .rotationEffect(.degrees(-2))
            AvafliV2Asset.trophy
                .resizable().scaledToFit()
                .frame(height: 230)
        }
        .frame(height: 280)
    }
}

// MARK: - Confirmation ("YOUR PRIZE CLAIM HAS BEEN SUBMITTED")

struct AvafliV2ClaimConfirmationView: View {
    let accent: Color
    let logoUrl: String?
    let form: AvafliPrizeClaimForm?
    let claimNumber: String
    let submittedAt: String
    let onDone: () -> Void

    /// One-shot: the confetti-burst GIF plays over the screen on mount (the
    /// submitted-claim beat), then removes itself.
    @State private var bursting = true

    private enum Gold {
        static let text = Color(red: 0.72, green: 0.55, blue: 0.16)
        static let border = Color(red: 0.83, green: 0.68, blue: 0.28)
        static let creamTop = Color(red: 1.0, green: 0.98, blue: 0.92)
        static let creamBottom = Color(red: 0.95, green: 0.88, blue: 0.68)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AvafliV2Color.deepCharcoal.ignoresSafeArea()
            // Same gold-sparkle art as the splash/form screens, fading into
            // the dark body behind the header + title (Joe's frame).
            AvafliClaimSparkleBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    AvafliClaimHeader(logoUrl: logoUrl, onClose: onDone)
                        .padding(.top, 18)

                    Text("YOUR PRIZE CLAIM HAS BEEN SUBMITTED")
                        .font(AvafliV2Font.inter(26, .black))
                        .kerning(-0.7)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 20)
                    Text("Our team is reviewing your information. You’ll receive a confirmation email shortly.")
                        .font(AvafliV2Font.inter(15))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .padding(.top, 8)

                    AvafliClaimInfoCard {
                        // Mail icon inside an accent-ringed circle (Joe's
                        // "3-5 Business Days" note card).
                        ZStack {
                            Circle()
                                .stroke(accent, lineWidth: 1.5)
                                .frame(width: 46, height: 46)
                            Image("avafli-mail", bundle: .module)
                                .resizable().scaledToFit()
                                .frame(width: 24, height: 19)
                                .foregroundColor(accent)
                        }
                    } content: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Expect to receive your prize within")
                                .font(AvafliV2Font.inter(14))
                                .foregroundColor(.white)
                            Text("3-5 Business Days")
                                .font(AvafliV2Font.inter(18, .black))
                                .foregroundColor(accent)
                        }
                    }
                    .padding(.top, 22)

                    winnerCard
                        .padding(.horizontal, 34)
                        // Extra headroom for the trophy's overhang above the
                        // card's gold border.
                        .padding(.top, 62)

                    AvafliV2PillButton(accent: accent, title: "RETURN TO APP") { onDone() }
                        .padding(.horizontal, 30)
                        .padding(.top, 30)
                        .padding(.bottom, 34)
                }
            }
            // Same celebration treatment as the winner splash (Joe's frame
            // 5386:5807): the drifting confetti field, plus a one-shot
            // confetti-burst GIF on mount (prewarmed at the experience root).
            // Decorative only — neither layer intercepts touches. (The frame's
            // "AVAFLI PRIZE CLAIM" caption is a canvas label, not UI.)
            .overlay(AvafliV2ConfettiView(style: .celebration, count: 32, speed: 0.85))
            .overlay {
                if bursting {
                    AvafliV2GifView("confetti-burst", onFinished: { bursting = false })
                        .frame(width: 280, height: 280)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
    }

    /// The gold OFFICIAL WINNER keepsake card: cream/gold gradient, small
    /// trophy breaking the top border, serif name, award month + claim number.
    private var winnerCard: some View {
        VStack(spacing: 4) {
            HStack {
                Text("OFFICIAL").kerning(0.5)
                Spacer()
                Text("WINNER").kerning(0.5)
            }
            .font(AvafliV2Font.inter(16, .black))
            // 2.9.3: publisher PRIMARY accent (Joe's frame 5386:5807 —
            // Solitaire-branded, orange = accent). The card's gold body,
            // border, and award line stay gold.
            .foregroundColor(accent)
            .padding(.horizontal, 26)
            .padding(.top, 18)

            Text(form?.displayName ?? "Our Winner")
                .font(.system(size: 30, weight: .black, design: .serif))
                .foregroundColor(Color(red: 0.1, green: 0.09, blue: 0.07))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 20)
                // Clears the lower half of the overhanging trophy.
                .padding(.top, 16)

            if let form, !form.trimmed(\.city).isEmpty {
                Text("\(form.trimmed(\.city)), \(form.trimmed(\.state))")
                    .font(AvafliV2Font.inter(14))
                    .foregroundColor(Color(white: 0.45))
            }

            Text("\(AvafliClaimDates.monthYearDisplay(fromISO: submittedAt)) • \(claimNumber)")
                .font(AvafliV2Font.inter(11, .bold))
                .kerning(1.1)
                .foregroundColor(Gold.text)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [Gold.creamTop, Gold.creamBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Gold.border, lineWidth: 2))
        .overlay(alignment: .top) {
            // The trophy sits centered ON the gold border, half above it,
            // between OFFICIAL and WINNER (Joe's frame).
            AvafliV2Asset.trophy
                .resizable().scaledToFit()
                .frame(height: 90)
                .offset(y: -45)
        }
    }
}

// MARK: - PHPicker wrapper

struct AvafliPhotoPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let controller = PHPickerViewController(configuration: config)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [onPick] object, _ in
                DispatchQueue.main.async {
                    onPick(object as? UIImage)
                }
            }
        }
    }
}
