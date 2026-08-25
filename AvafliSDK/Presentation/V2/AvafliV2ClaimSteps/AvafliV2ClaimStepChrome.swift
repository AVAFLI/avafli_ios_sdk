//
//  AvafliV2ClaimStepChrome.swift
//  AvafliSDK
//
//  Shared chrome for the stepped prize-claim flow (Joe's Figma frames):
//  field colors, the persistent header (back chevron / publisher logo / close),
//  the "STEP N OF 4" label, and the 4 connected progress dots.
//

import SwiftUI

/// Field styling from the claim-step frames: #212832 fill, #3D424B border, r10.
enum AvafliClaimStepTheme {
    static let fieldFill = Color(red: 0x21 / 255, green: 0x28 / 255, blue: 0x32 / 255)
    static let fieldBorder = Color(red: 0x3D / 255, green: 0x42 / 255, blue: 0x4B / 255)

    static var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(fieldFill)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(fieldBorder, lineWidth: 1))
    }
}

/// Gold-sparkle full-bleed backdrop fading into the dark body, per the frames
/// (406pt tall, transparent → deepCharcoal). Shared by the claim steps and the
/// confirmation screen. The art lives in the .background of a clear frame so
/// scaledToFill's oversized width can't leak into the ZStack's layout.
struct AvafliClaimSparkleBackdrop: View {
    var body: some View {
        Color.clear
            .frame(height: 406)
            .frame(maxWidth: .infinity)
            .background(AvafliV2Asset.winnerModalBg.resizable().scaledToFill())
            .clipped()
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: AvafliV2Color.deepCharcoal.opacity(0.1), location: 0.05),
                        .init(color: AvafliV2Color.deepCharcoal.opacity(0.6), location: 0.6),
                        .init(color: AvafliV2Color.deepCharcoal, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
    }
}

/// Header shown on every step: centered publisher logo (210×60 per the frames)
/// with a back chevron on the left (steps 2+ / review) and the X close on the
/// right.
struct AvafliClaimStepHeader: View {
    let logoUrl: String?
    let showsBack: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            logo
                .frame(height: 60)
                .frame(maxWidth: 210)
            HStack {
                if showsBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(AvafliV2Color.deepCharcoal.opacity(0.85)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
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
                .accessibilityLabel("Close")
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

/// "STEP N OF {total}" + the row of connected dots: filled with the accent up
/// to the current step, outlined after it. The fill animates as the flow
/// advances. Total is 3 since 2.9 (the share screen moved after submit).
struct AvafliClaimStepIndicator: View {
    let accent: Color
    /// 1-based current step (1...total).
    let current: Int
    var total: Int = AvafliClaimFlowStep.totalFormSteps

    private let dotSize: CGFloat = 14
    private let lineWidth: CGFloat = 29

    var body: some View {
        VStack(spacing: 12) {
            Text("STEP \(current) OF \(total)")
                .font(AvafliV2Font.inter(17, .semibold))
                .kerning(-0.85)
                .foregroundColor(.white)
            HStack(spacing: 0) {
                ForEach(1...total, id: \.self) { index in
                    dot(filled: index <= current)
                    if index < total {
                        Rectangle()
                            .fill(accent)
                            .frame(width: lineWidth, height: 1.5)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: current)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current) of \(total)")
    }

    private func dot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? accent : AvafliV2Color.deepCharcoal.opacity(0.6))
            .overlay(Circle().stroke(accent, lineWidth: 1.5))
            .frame(width: dotSize, height: dotSize)
    }
}
