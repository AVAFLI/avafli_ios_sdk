//
//  AvafliV2Theme.swift
//  AvafliSDK
//
//  Design system for the V2 experience — tokens, fonts, and assets extracted
//  from Joe's Figma (Avafli-High-V2). Everything here is intentionally HARDCODED
//  to the design except the publisher-configurable primary color: publishers can
//  customize ONLY their logo, prize image, and primary color.
//

import SwiftUI
import CoreText

// MARK: - Colors (Figma design tokens)

enum AvafliV2Color {
    /// background/primary — the drawer + tile background ("gunmetal").
    static let gunmetal = Color(red: 0x1D / 255, green: 0x23 / 255, blue: 0x30 / 255)
    /// black (deep charcoal) — header circle buttons.
    static let deepCharcoal = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x12 / 255)
    /// Modal panel background.
    static let panel = Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x19 / 255)
    /// Modal hairline border.
    static let panelBorder = Color(red: 0x51 / 255, green: 0x51 / 255, blue: 0x51 / 255)
    /// Avafli brand blue — the DEFAULT primary when a publisher hasn't set one.
    static let avafliBlue = Color(red: 0x26 / 255, green: 0x8F / 255, blue: 0xFF / 255)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.75)
    static let textTertiary = Color.white.opacity(0.6)
    static let foregroundSecondary = Color.white.opacity(0.5)
    /// Inline validation / error text (the code-entry error red).
    static let errorRed = Color(red: 1, green: 0.42, blue: 0.39)
}

/// The publisher's primary color (branding.primaryColor) with the Avafli-blue default.
/// Drives: CTA buttons, streak-tile outlines/glow, accent text, power-up tiles.
struct AvafliV2Accent {
    let color: Color

    init(hex: String?) {
        if let hex, let parsed = Self.parse(hex: hex) {
            color = parsed
        } else {
            color = AvafliV2Color.avafliBlue
        }
    }

    private static func parse(hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    /// White or near-black (gunmetal) — whichever contrasts against `accent`.
    /// Used for marks drawn ON an accent-filled surface (e.g. the capture
    /// screen's checkbox check) so a light publisher primary doesn't produce
    /// a white-on-white check. Relative-luminance cut at 0.6.
    static func contrastingMark(on accent: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(accent).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.6 ? AvafliV2Color.gunmetal : .white
    }
}

// MARK: - Fonts (Inter + Oswald, bundled)

enum AvafliV2Font {
    /// Registers the bundled Inter/Oswald faces with CoreText. Idempotent.
    /// Called from Avafli.configure — SDKs can't rely on the host app's Info.plist.
    static func registerIfNeeded() {
        struct Once { static var done = false }
        guard !Once.done else { return }
        Once.done = true
        let files = [
            "inter-v20-latin-regular", "inter-v20-latin-500", "inter-v20-latin-600",
            "inter-v20-latin-700", "inter-v20-latin-800", "inter-v20-latin-900",
            "oswald-v57-latin-500", "oswald-v57-latin-700",
        ]
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .black: name = "Inter-Black"
        case .heavy: name = "Inter-ExtraBold"
        case .bold: name = "Inter-Bold"
        case .semibold: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return .custom(name, size: size)
    }

    static func oswald(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Oswald-Bold" : "Oswald-Medium", size: size)
    }
}

// MARK: - Bundled images

enum AvafliV2Asset {
    static func image(_ name: String) -> Image {
        if let ui = UIImage(named: name, in: .module, compatibleWith: nil) {
            return Image(uiImage: ui)
        }
        // Resource may land with its extension-stripped name only; fall back to path lookup.
        if let path = Bundle.module.path(forResource: name, ofType: "png"),
           let ui = UIImage(contentsOfFile: path) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "questionmark")
    }

    /// Default prize hero (money pile) — used when the publisher hasn't set a prize image.
    static var cashHero: Image { image("cash-hero-single") }
    static var confetti: Image { image("confetti-frame") }
    static var checkModal: Image { image("check-modal-frame") }
    static var checkTileActive: Image { image("check-tile-active-frame") }
    static var checkTileCompleted: Image { image("check-tile-completed") }
    static var trophy: Image { image("trophy") }
    static var winnerModalBg: Image { image("winner-modal-bg") }
}


// MARK: - Prize text derivation (capture strip / prize card / winner claim)

/// Shared prize-derived copy rules: cash prizes read "$1,000.00 CASH PRIZE";
/// other prizes read "Win a {Description}" with an optional value line that is
/// suppressed when the description already states the amount.
enum AvafliV2PrizeText {
    static func isCash(description: String) -> Bool {
        description.isEmpty || description.lowercased().contains("cash")
    }

    /// "a" vs "an", keyed off the LEADING token: "$500 Amazon…" reads
    /// "a five-hundred…", so any non-letter start takes "a"; only a leading
    /// vowel sound takes "an".
    static func article(for description: String) -> String {
        guard let first = description.trimmingCharacters(in: .whitespaces).first,
              first.isLetter else { return "a" }
        return "AEIOU".contains(first.uppercased()) ? "an" : "a"
    }

    /// Whether the "$X.00 VALUE!" line should render (redundant when the prize
    /// name already states the amount, e.g. "$500 Amazon Gift Card").
    static func showsValueLine(description: String, value: Int) -> Bool {
        value > 0
            && !description.contains("$\(value.formatted())")
            && !description.contains("$\(value)")
    }

    /// The white-strip headline (Day-1 capture + winner splash):
    /// cash → "$1,000.00 CASH PRIZE"; other → "Win a $500 Amazon Gift Card".
    static func stripHeadline(description: String, value: Int) -> String {
        isCash(description: description)
            ? "$\(value.formatted()).00 CASH PRIZE"
            : "Win \(article(for: description)) \(description)"
    }
}

// MARK: - Ladder math (mirrors the backend exactly)

enum AvafliV2Ladder {
    /// Explicit ladder values cover days 1..ladder.count; beyond that the daily
    /// increment is the bonusEntries of the LATEST passed milestone (the
    /// "+25 EVERY DAY!" accelerators). No milestones → flat at the ladder top.
    static func entries(day: Int, ladder: [Int], milestones: [MilestoneConfigAPI]?) -> Int {
        guard !ladder.isEmpty else { return 10 }
        if day <= ladder.count { return ladder[max(0, day - 1)] }
        let ms = (milestones ?? []).sorted { $0.day < $1.day }
        var value = ladder[ladder.count - 1]
        for d in (ladder.count + 1)...day {
            var rate = 0
            for m in ms where m.day < d { rate = m.bonusEntries }
            value += rate
        }
        return value
    }
}
