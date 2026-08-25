//
//  AvafliV2ClaimStep2.swift
//  AvafliSDK
//
//  Step 2 of 4 — "WHERE SHOULD WE SEND YOUR PRIZE?": street, apt, city,
//  State picker + 5-digit zip side by side, Country locked to United States.
//

import SwiftUI

struct AvafliClaimStep2View: View {
    let accent: Color
    @Binding var form: AvafliPrizeClaimForm
    /// Present only when sdkConfig.placesApiKey is configured — the street
    /// field then offers Google Places suggestions. nil → plain typing.
    var placesService: AvafliPlacesAutocompleteService? = nil
    let onContinue: () -> Void

    var body: some View {
        AvafliClaimStepPage(
            accent: accent,
            title: "WHERE SHOULD WE\nSEND YOUR PRIZE?",
            ctaEnabled: form.isStep2Valid,
            onCTA: onContinue
        ) {
            VStack(spacing: 21) {
                if let placesService {
                    AvafliClaimAutocompleteStreetField(
                        label: "Street Address",
                        text: $form.street,
                        service: placesService,
                        onSelect: { fill($0) }
                    )
                } else {
                    AvafliClaimStepField(
                        label: "Street Address",
                        text: $form.street,
                        contentType: .streetAddressLine1
                    )
                }
                AvafliClaimStepField(
                    label: "Apartment, Suite, etc. (optional)",
                    text: $form.apt,
                    contentType: .streetAddressLine2
                )
                AvafliClaimStepField(
                    label: "City",
                    text: $form.city,
                    contentType: .addressCity
                )
                HStack(alignment: .top, spacing: 13) {
                    AvafliClaimStepMenuField(
                        label: "State",
                        options: AvafliPrizeClaimForm.usStates,
                        selection: $form.state
                    )
                    .frame(maxWidth: .infinity)
                    // 2.9 fix: the zip box was 101pt wide — with the field's
                    // 25pt inner padding each side that left ~51pt for five
                    // 20pt digits, clipping the value. 130pt fits all five.
                    AvafliClaimStepField(
                        label: "Zip Code",
                        text: $form.zip,
                        keyboard: .numberPad,
                        contentType: .postalCode
                    )
                    .frame(width: 130)
                    .onChange(of: form.zip) { newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(5))
                        if digits != newValue { form.zip = digits }
                    }
                }
                // US-only sweepstakes — the country row renders like the frame's
                // dropdown but is fixed.
                AvafliClaimStepLockedField(
                    label: "Country",
                    value: form.country,
                    dimmed: false,
                    showsChevron: true
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 28)
        }
    }

    /// Fills the form from a picked suggestion. Empty mapped values leave the
    /// existing field content alone; everything stays hand-editable.
    private func fill(_ address: AvafliAutocompletedAddress) {
        if !address.street.isEmpty { form.street = address.street }
        if !address.city.isEmpty { form.city = address.city }
        if !address.state.isEmpty { form.state = address.state }
        if !address.zip.isEmpty {
            form.zip = String(address.zip.filter(\.isNumber).prefix(5))
        }
    }
}
