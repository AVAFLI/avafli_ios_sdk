//
//  AvafliV2ClaimStepsFlow.swift
//  AvafliSDK
//
//  Root of the stepped prize-claim form (Joe's Figma design): a persistent
//  gold-sparkle backdrop + header + animated step indicator, with the three
//  form steps and the review screen sliding horizontally beneath them
//  (push left on advance, push right on back). The "Please share a little"
//  screen moved AFTER submit (2.9) — see AvafliV2ClaimShareScreen.
//

import SwiftUI

/// The four screens of the stepped form. Raw value is the 1-based step number
/// (review has no "STEP N OF 3" row, matching the SUBMIT frame).
enum AvafliClaimFlowStep: Int, CaseIterable {
    case one = 1, two, three, review

    var indicatorStep: Int? { self == .review ? nil : rawValue }

    /// Form steps shown in the indicator (review excluded).
    static let totalFormSteps = 3
}

struct AvafliV2ClaimStepsFlow: View {
    let accent: Color
    let logoUrl: String?
    /// Resolved publisher/app name for the review screen's likeness copy.
    let publisherName: String?
    let claim: PrizeClaimBlock
    @ObservedObject var viewModel: AvafliExperienceViewModel
    let onClose: () -> Void

    /// Street-field autocomplete, present only when sdkConfig.placesApiKey is
    /// configured. Held at flow level so the service (and its URLSession use)
    /// survives step navigation.
    private let placesService: AvafliPlacesAutocompleteService?

    @State private var form: AvafliPrizeClaimForm
    /// The picked/taken photo, held at flow level so step 3 keeps its preview
    /// when the user navigates back and forth.
    @State private var photo: UIImage?
    @State private var step: AvafliClaimFlowStep = .one
    /// Direction of the last navigation — drives the slide edges.
    @State private var advancing = true

    init(
        accent: Color,
        logoUrl: String?,
        publisherName: String? = nil,
        placesApiKey: String? = nil,
        claim: PrizeClaimBlock,
        viewModel: AvafliExperienceViewModel,
        onClose: @escaping () -> Void
    ) {
        self.accent = accent
        self.logoUrl = logoUrl
        self.publisherName = publisherName
        self.placesService = placesApiKey.flatMap { key in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : AvafliPlacesAutocompleteService(apiKey: trimmed)
        }
        self.claim = claim
        self.viewModel = viewModel
        self.onClose = onClose
        _form = State(initialValue: viewModel.claimFormPrefill)
    }

    var body: some View {
        ZStack(alignment: .top) {
            AvafliV2Color.deepCharcoal.ignoresSafeArea()
            AvafliClaimSparkleBackdrop()

            VStack(spacing: 0) {
                AvafliClaimStepHeader(
                    logoUrl: logoUrl,
                    showsBack: step != .one,
                    onBack: goBack,
                    onClose: onClose
                )
                .padding(.top, 18)

                if let indicatorStep = step.indicatorStep {
                    AvafliClaimStepIndicator(accent: accent, current: indicatorStep)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                ZStack {
                    stepContent
                        .id(step)
                        .transition(slide)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
        }
    }

    // MARK: - Steps

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .one:
            AvafliClaimStep1View(
                accent: accent,
                form: $form,
                maskedEmail: claim.maskedEmail,
                onContinue: { go(to: .two) }
            )
        case .two:
            AvafliClaimStep2View(
                accent: accent,
                form: $form,
                placesService: placesService,
                onContinue: { go(to: .three) }
            )
        case .three:
            AvafliClaimStep3View(
                accent: accent,
                form: $form,
                photo: $photo,
                onContinue: { go(to: .review) }
            )
        case .review:
            AvafliClaimReviewView(
                accent: accent,
                publisherName: publisherName,
                form: $form,
                viewModel: viewModel
            )
        }
    }

    // MARK: - Navigation

    private func go(to next: AvafliClaimFlowStep) {
        advancing = next.rawValue > step.rawValue
        withAnimation(.easeInOut(duration: 0.3)) { step = next }
    }

    private func goBack() {
        guard let previous = AvafliClaimFlowStep(rawValue: step.rawValue - 1) else { return }
        go(to: previous)
    }

    /// Steps push left when advancing and right when going back.
    private var slide: AnyTransition {
        .asymmetric(
            insertion: .move(edge: advancing ? .trailing : .leading),
            removal: .move(edge: advancing ? .leading : .trailing)
        )
    }
}
