//
//  AvafliV2ClaimReview.swift
//  AvafliSDK
//
//  Review screen — "ALMOST DONE!" (2.9.3): ONE optional likeness/promo
//  checkbox (submit is always enabled), SUBMIT PRIZE CLAIM, and the
//  "secure and encrypted" lock note. No step indicator (matches the SUBMIT
//  frame). The "By submitting, you agree to the …" sentence and its
//  Official Rules / Privacy Policy links are GONE (Ryan's call, Joe's
//  updated Figma) — this screen carries no legal links at all.
//

import SwiftUI

struct AvafliClaimReviewView: View {
    let accent: Color
    /// Resolved publisher/app name for the likeness copy (sdkConfig.appName,
    /// else the host app's display name). nil → generic wording.
    let publisherName: String?
    @Binding var form: AvafliPrizeClaimForm
    @ObservedObject var viewModel: AvafliExperienceViewModel

    var body: some View {
        AvafliClaimStepPage(
            accent: accent,
            title: "ALMOST DONE!",
            subtitle: "Please review and submit to claim your prize.",
            ctaTitle: "SUBMIT PRIZE CLAIM",
            // 2.9: the likeness/promo checkbox is OPTIONAL — SUBMIT is always
            // enabled (the steps already validated their required fields).
            ctaEnabled: true,
            ctaLoading: viewModel.isSubmittingClaim,
            onCTA: { viewModel.submitPrizeClaim(form) },
            footer: AnyView(lockNote)
        ) {
            AvafliClaimConsentRow(
                accent: accent,
                isOn: $form.authorizesLikeness,
                text: Text(Self.likenessConsentText(publisherName: publisherName))
            )
            .padding(.horizontal, 12)
            .padding(.top, 44)
            .padding(.bottom, 12)

            if let error = viewModel.claimSubmitError {
                Text(error)
                    .font(AvafliV2Font.inter(13, .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
        }
    }

    /// The likeness/promo checkbox copy — names the actual publisher/app
    /// when known (2.9.3), falling back to the old generic wording.
    static func likenessConsentText(publisherName: String?) -> String {
        let who = publisherName ?? "this app's publisher"
        return "I authorize \(who) and its promotional partners to use my name, city, profile photo, and likeness for winner announcements and promotional purposes. (Optional)"
    }

    /// Gunmetal rounded note under the CTA, accent lock + 14pt copy.
    private var lockNote: some View {
        HStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundColor(accent)
            Text("Your information is secure and encrypted.")
                .font(AvafliV2Font.inter(14))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(AvafliV2Color.gunmetal))
        .padding(.horizontal, 12)
        .padding(.top, 30)
    }
}

/// A single consent checkbox row (accent square check + wrapping label) —
/// carried over unchanged in structure from the Light form, sized up to the
/// review frame's larger type.
struct AvafliClaimConsentRow: View {
    let accent: Color
    @Binding var isOn: Bool
    let text: Text

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn ? accent : Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(isOn ? accent : Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(isOn ? 1 : 0)
                    )
                    .frame(width: 24, height: 24)
                text
                    .font(AvafliV2Font.inter(16))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
