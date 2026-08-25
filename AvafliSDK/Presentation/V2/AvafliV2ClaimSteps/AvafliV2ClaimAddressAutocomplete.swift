//
//  AvafliV2ClaimAddressAutocomplete.swift
//  AvafliSDK
//
//  Google Places (API New) address autocomplete for the claim flow's street
//  field. Active ONLY when the publisher configures `sdkConfig.placesApiKey`;
//  without it the street field is the plain text field it always was. Every
//  failure path degrades silently to plain typing — autocomplete is sugar,
//  never a gate.
//
//  Wire calls (no SDK dependency — plain URLSession):
//    • POST https://places.googleapis.com/v1/places:autocomplete
//      body: { input, includedRegionCodes: ["us"],
//              includedPrimaryTypes: [street_address, premise, subpremise] }
//    • GET  https://places.googleapis.com/v1/places/{placeId}
//      X-Goog-FieldMask: addressComponents
//

import SwiftUI

// MARK: - Mapped address (pure, unit-testable)

/// The four claim-form fields an accepted suggestion fills. All values stay
/// hand-editable after the fill.
struct AvafliAutocompletedAddress: Equatable {
    var street: String
    var city: String
    var state: String
    var zip: String
}

/// One `addressComponents[]` entry from Place Details (Places API New shape).
struct AvafliPlaceAddressComponent: Decodable, Equatable {
    let longText: String?
    let shortText: String?
    let types: [String]?

    init(longText: String? = nil, shortText: String? = nil, types: [String]? = nil) {
        self.longText = longText
        self.shortText = shortText
        self.types = types
    }
}

/// Pure mapping from Google address components to the claim form's fields —
/// kept free of networking/view machinery so it is unit-testable.
enum AvafliPlacesAddressMapper {
    /// street = street_number + route; city = locality (falling back to
    /// sublocality_level_1, then postal_town); state = the 2-letter
    /// administrative_area_level_1 shortText expanded to the full name the
    /// State menu uses ("CA" → "California"); zip = postal_code.
    static func address(from components: [AvafliPlaceAddressComponent]) -> AvafliAutocompletedAddress {
        func first(_ type: String) -> AvafliPlaceAddressComponent? {
            components.first { $0.types?.contains(type) == true }
        }

        let streetNumber = first("street_number")?.longText ?? ""
        let route = first("route")?.longText ?? ""
        let street = [streetNumber, route]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let city = first("locality")?.longText
            ?? first("sublocality_level_1")?.longText
            ?? first("postal_town")?.longText
            ?? ""

        let state = expandedStateName(first("administrative_area_level_1")?.shortText ?? "")
        let zip = first("postal_code")?.longText ?? ""

        return AvafliAutocompletedAddress(street: street, city: city, state: state, zip: zip)
    }

    /// The full state name matching AvafliPrizeClaimForm.usStates (the State
    /// menu's options), so a filled state renders exactly like a picked one —
    /// same expansion as the Android/web SDKs. Unmapped codes (territories
    /// like "PR"/"GU") pass through as-is so the field still fills.
    static func expandedStateName(_ shortText: String) -> String {
        stateNamesByCode[shortText] ?? shortText
    }

    /// USPS code → full name, 50 states + DC (mirrors usStates exactly).
    private static let stateNamesByCode: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut",
        "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida",
        "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky",
        "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
        "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
        "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
        "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming",
    ]
}

// MARK: - Wire models

struct AvafliPlaceSuggestion: Equatable, Identifiable {
    let placeID: String
    let text: String
    var id: String { placeID }
}

private struct AvafliPlacesAutocompleteResponse: Decodable {
    struct Suggestion: Decodable {
        struct PlacePrediction: Decodable {
            struct FormattableText: Decodable {
                let text: String?
            }
            let placeId: String?
            let text: FormattableText?
        }
        let placePrediction: PlacePrediction?
    }
    let suggestions: [Suggestion]?
}

private struct AvafliPlaceDetailsResponse: Decodable {
    let addressComponents: [AvafliPlaceAddressComponent]?
}

// MARK: - Service

/// Thin URLSession wrapper around the two Places calls. Returns empty/nil on
/// ANY failure (bad key, offline, quota, decode) — the field then behaves like
/// the plain one.
final class AvafliPlacesAutocompleteService {
    static let maxSuggestions = 5

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    /// US street-level suggestions for the typed input (max 5).
    func suggestions(for input: String) async -> [AvafliPlaceSuggestion] {
        guard let url = URL(string: "https://places.googleapis.com/v1/places:autocomplete") else {
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        let body: [String: Any] = [
            "input": input,
            "includedRegionCodes": ["us"],
            "includedPrimaryTypes": ["street_address", "premise", "subpremise"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        request.httpBody = data

        guard let (responseData, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AvafliPlacesAutocompleteResponse.self, from: responseData)
        else { return [] }

        let suggestions = (decoded.suggestions ?? []).compactMap { suggestion -> AvafliPlaceSuggestion? in
            guard let prediction = suggestion.placePrediction,
                  let placeID = prediction.placeId, !placeID.isEmpty,
                  let text = prediction.text?.text, !text.isEmpty
            else { return nil }
            return AvafliPlaceSuggestion(placeID: placeID, text: text)
        }
        return Array(suggestions.prefix(Self.maxSuggestions))
    }

    /// Address components for a picked suggestion, mapped to the form fields.
    /// nil on any failure — the caller keeps the typed/suggestion text.
    func address(forPlaceID placeID: String) async -> AvafliAutocompletedAddress? {
        guard let encoded = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://places.googleapis.com/v1/places/\(encoded)")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("addressComponents", forHTTPHeaderField: "X-Goog-FieldMask")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AvafliPlaceDetailsResponse.self, from: data),
              let components = decoded.addressComponents
        else { return nil }

        return AvafliPlacesAddressMapper.address(from: components)
    }
}

// MARK: - Street field with suggestions

/// The claim step's street field with a Places suggestion list beneath it.
/// Same box styling as AvafliClaimStepField; the list pushes the fields below
/// it down (all inside the keyboard-padded scroll content, so suggestions
/// stay visible and tappable with the keyboard up). Debounced ~300ms via
/// Task cancellation; queries start at 3 typed characters.
struct AvafliClaimAutocompleteStreetField: View {
    let label: String
    @Binding var text: String
    let service: AvafliPlacesAutocompleteService
    /// Called with the mapped address after a suggestion resolves — the parent
    /// fills street/city/state/zip (all remain hand-editable).
    let onSelect: (AvafliAutocompletedAddress) -> Void

    @State private var suggestions: [AvafliPlaceSuggestion] = []
    @State private var searchTask: Task<Void, Never>?
    /// Value we last wrote programmatically (suggestion fill) — its onChange
    /// echo must not re-open the list.
    @State private var programmaticText: String?
    @FocusState private var isFocused: Bool
    @Environment(\.avafliScrollToField) private var scrollToField

    private var anchorID: String { "avafli-claim-field-\(label)" }
    private let minQueryLength = 3
    private let debounceNanoseconds: UInt64 = 300_000_000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AvafliClaimStepFieldLabel(label)
            TextField("", text: $text)
                .font(AvafliV2Font.inter(20))
                .foregroundColor(.white)
                .textContentType(.streetAddressLine1)
                .autocorrectionDisabled()
                .focused($isFocused)
                .padding(.horizontal, 25)
                .frame(height: 59)
                .background(AvafliClaimStepTheme.fieldBackground)
            if !suggestions.isEmpty {
                suggestionList
                    .transition(.opacity)
            }
        }
        .id(anchorID)
        .onChange(of: isFocused) { focused in
            if focused {
                scrollToField(anchorID)
            } else {
                clearSuggestions()
            }
        }
        .onChange(of: text) { newValue in
            if newValue == programmaticText {
                programmaticText = nil
                return
            }
            scheduleSearch(for: newValue)
        }
        .onDisappear { searchTask?.cancel() }
        .animation(.easeInOut(duration: 0.15), value: suggestions)
    }

    /// Dark card matching the field chrome: up to 5 rows + the required
    /// "powered by Google" attribution row.
    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    select(suggestion)
                } label: {
                    Text(suggestion.text)
                        .font(AvafliV2Font.inter(15))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Rectangle()
                    .fill(AvafliClaimStepTheme.fieldBorder.opacity(0.6))
                    .frame(height: 1)
            }
            Text("powered by Google")
                .font(AvafliV2Font.inter(11))
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
        }
        .background(AvafliClaimStepTheme.fieldBackground)
        .accessibilityLabel("Address suggestions")
    }

    // MARK: Behavior

    private func scheduleSearch(for input: String) {
        searchTask?.cancel()
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= minQueryLength else {
            clearSuggestions()
            return
        }
        let debounce = debounceNanoseconds
        searchTask = Task { [service] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            let results = await service.suggestions(for: query)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                suggestions = results
                if !results.isEmpty { scrollToField(anchorID) }
            }
        }
    }

    private func select(_ suggestion: AvafliPlaceSuggestion) {
        searchTask?.cancel()
        clearSuggestions()
        // Show the suggestion text immediately; details refine it when they land.
        programmaticText = suggestion.text
        text = suggestion.text
        Task { [service] in
            guard let address = await service.address(forPlaceID: suggestion.placeID) else { return }
            await MainActor.run {
                if !address.street.isEmpty {
                    programmaticText = address.street
                }
                onSelect(address)
            }
        }
    }

    private func clearSuggestions() {
        suggestions = []
    }
}
