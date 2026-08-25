//
//  AvafliBranding.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//
//  Branding is configured server-side only:
//  - Starter plan: white-label set by Avafli admin team
//  - Growth/Enterprise: customized via publisher dashboard
//
//  Publishers cannot set branding via code. The SDK fetches
//  branding from the server and falls back to built-in defaults
//  if no server config is available (e.g., first launch offline).
//

import Foundation
import SwiftUI

public struct AvafliBranding {
    // TEXT
    public let primaryColor: Color
    public let secondaryTextColor: Color
    public let mutedTextColor: Color

    // BACKGROUNDS
    public let backgroundColor: Color
    public let cardBackgroundColor: Color
    public let cardBorderColor: Color

    // BUTTONS
    public let primaryButtonColor: Color
    public let primaryButtonTextColor: Color
    public let secondaryButtonColor: Color
    public let secondaryButtonTextColor: Color

    // INPUTS
    public let inputFieldBackgroundColor: Color
    public let inputFieldBorderColor: Color
    public let inputFieldPlaceholderColor: Color

    // EXTRA ACCENT
    public let accentGlowColor: Color

    // GLOBAL RADIUS + LOGO
    public let cornerRadius: CGFloat
    public let logo: AvafliLogo
    public let logoTwo: AvafliLogo?

    // CONFIGURABLE LOGO SIZES
    public let primaryLogoSize: CGSize
    public let secondaryLogoSize: CGSize?

    // DESIGNATED INITIALIZER (internal — not for publisher use)
    public init(
        primaryColor: Color,
        secondaryTextColor: Color,
        mutedTextColor: Color,
        backgroundColor: Color,
        cardBackgroundColor: Color,
        cardBorderColor: Color,
        primaryButtonColor: Color,
        primaryButtonTextColor: Color,
        secondaryButtonColor: Color,
        secondaryButtonTextColor: Color,
        inputFieldBackgroundColor: Color,
        inputFieldBorderColor: Color,
        inputFieldPlaceholderColor: Color,
        accentGlowColor: Color,
        cornerRadius: CGFloat,
        logo: AvafliLogo,
        logoTwo: AvafliLogo? = nil,
        primaryLogoSize: CGSize,
        secondaryLogoSize: CGSize,
    ) {
        self.primaryColor = primaryColor
        self.secondaryTextColor = secondaryTextColor
        self.mutedTextColor = mutedTextColor
        self.backgroundColor = backgroundColor
        self.cardBackgroundColor = cardBackgroundColor
        self.cardBorderColor = cardBorderColor
        self.primaryButtonColor = primaryButtonColor
        self.primaryButtonTextColor = primaryButtonTextColor
        self.secondaryButtonColor = secondaryButtonColor
        self.secondaryButtonTextColor = secondaryButtonTextColor
        self.inputFieldBackgroundColor = inputFieldBackgroundColor
        self.inputFieldBorderColor = inputFieldBorderColor
        self.inputFieldPlaceholderColor = inputFieldPlaceholderColor
        self.accentGlowColor = accentGlowColor
        self.cornerRadius = cornerRadius
        self.logo = logo
        self.logoTwo = logoTwo
        self.primaryLogoSize = primaryLogoSize
        self.secondaryLogoSize = secondaryLogoSize
    }
}

// MARK: - Server-Driven Branding

extension AvafliBranding {
    /// Built-in default branding used when no server config is available.
    /// This is the Avafli standard dark theme — the baseline white-label look.
    static let `default` = AvafliBranding(
        primaryColor: .white,
        secondaryTextColor: .white.opacity(0.96),
        mutedTextColor: .white.opacity(0.74),
        backgroundColor: Color(hex: "#020617"),
        cardBackgroundColor: Color(hex: "#020818"),
        cardBorderColor: Color.white.opacity(0.16),
        primaryButtonColor: Color(hex: "#0284FF"),
        primaryButtonTextColor: .white,
        secondaryButtonColor: Color.white.opacity(0.06),
        secondaryButtonTextColor: .white.opacity(0.92),
        inputFieldBackgroundColor: Color.white.opacity(0.03),
        inputFieldBorderColor: Color.white.opacity(0.18),
        inputFieldPlaceholderColor: .white.opacity(0.55),
        accentGlowColor: Color(hex: "#0EA5E9"),
        cornerRadius: 24,
        logo: .system("gift.fill"),
        logoTwo: nil,
        primaryLogoSize: CGSize(width: 100, height: 52),
        secondaryLogoSize: CGSize(width: 40, height: 18)
    )

    /// Build branding entirely from server SDK config.
    /// Server values override defaults; missing fields fall back to the built-in default.
    static func from(serverConfig: SDKBrandingConfig?) -> AvafliBranding {
        guard let server = serverConfig else { return .default }

        let base = AvafliBranding.default

        let primary = server.primaryColor.flatMap { Color(hex: $0) } ?? base.primaryButtonColor
        let secondary = server.secondaryColor.flatMap { Color(hex: $0) } ?? base.secondaryButtonColor
        let bg = server.backgroundColor.flatMap { Color(hex: $0) } ?? base.backgroundColor

        // Derive card and input colors from the background
        let cardBg = bg.opacity(0.96)
        let cardBorder = Color.white.opacity(0.16)
        let inputBg = Color.white.opacity(0.03)
        let inputBorder = Color.white.opacity(0.18)

        let logo: AvafliLogo = server.logoUrl.flatMap { url in
            URL(string: url).map { AvafliLogo.remote(url: $0) }
        } ?? base.logo

        return AvafliBranding(
            primaryColor: .white,
            secondaryTextColor: .white.opacity(0.96),
            mutedTextColor: .white.opacity(0.74),
            backgroundColor: bg,
            cardBackgroundColor: cardBg,
            cardBorderColor: cardBorder,
            primaryButtonColor: primary,
            primaryButtonTextColor: .white,
            secondaryButtonColor: secondary,
            secondaryButtonTextColor: .white.opacity(0.92),
            inputFieldBackgroundColor: inputBg,
            inputFieldBorderColor: inputBorder,
            inputFieldPlaceholderColor: .white.opacity(0.55),
            accentGlowColor: secondary,
            cornerRadius: 24,
            logo: logo,
            logoTwo: nil,
            primaryLogoSize: CGSize(width: 100, height: 52),
            secondaryLogoSize: CGSize(width: 40, height: 18)
        )
    }
}

// MARK: - Hex helper

public extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")

        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r = Double((int & 0xFF0000) >> 16) / 255.0
        let g = Double((int & 0x00FF00) >> 8) / 255.0
        let b = Double(int & 0x0000FF) / 255.0

        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}
