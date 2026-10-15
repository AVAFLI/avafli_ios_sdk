//
//  AvafliV2ClaimTests.swift
//  AvafliSDKTests
//
//  Fast tests for the winner prize-claim helpers: form validation, the shared
//  prize-text derivation, the award-date display, and the PrizeClaimBlock
//  decode contract (mirrors functions/src/types.ts exactly).
//

import XCTest
import UIKit
@testable import AvafliSDK

final class AvafliV2ClaimTests: XCTestCase {

    // MARK: - Form validation

    /// Every step's required fields filled.
    private var validForm: AvafliPrizeClaimForm {
        var form = AvafliPrizeClaimForm()
        form.firstName = "Catherine"
        form.lastName = "Cinosta"
        form.street = "5 Haide Pl."
        form.city = "Brooklyn"
        form.state = "New York"
        form.zip = "11737"
        return form
    }

    func testValidFormPasses() {
        XCTAssertTrue(validForm.isValid)
    }

    func testOptionalFieldsAreNotRequired() {
        var form = validForm
        form.phone = ""
        form.apt = ""
        form.photoBase64 = nil
        XCTAssertTrue(form.isValid)
    }

    func testMissingRequiredFieldsFail() {
        for keyPath in [\AvafliPrizeClaimForm.firstName, \.lastName, \.street, \.city, \.state] {
            var form = validForm
            form[keyPath: keyPath] = "   "
            XCTAssertFalse(form.isValid, "Blank \(keyPath) must invalidate the form")
        }
    }

    // MARK: Per-step validity (stepped flow)

    func testStepOneRequiresFirstAndLastName() {
        var form = AvafliPrizeClaimForm()
        XCTAssertFalse(form.isStep1Valid)
        form.firstName = "Catherine"
        XCTAssertFalse(form.isStep1Valid)
        form.lastName = "Cinosta"
        XCTAssertTrue(form.isStep1Valid)
        // Phone stays optional at the step level.
        form.phone = ""
        XCTAssertTrue(form.isStep1Valid)
    }

    func testStepTwoRequiresFullAddress() {
        var form = AvafliPrizeClaimForm()
        form.street = "5 Haide Pl."
        form.city = "Brooklyn"
        form.state = "New York"
        form.zip = "11737"
        XCTAssertTrue(form.isStep2Valid)
        for keyPath in [\AvafliPrizeClaimForm.street, \.city, \.state] {
            var broken = form
            broken[keyPath: keyPath] = "  "
            XCTAssertFalse(broken.isStep2Valid, "Blank \(keyPath) must invalidate step 2")
        }
        var badZip = form
        badZip.zip = "1173"
        XCTAssertFalse(badZip.isStep2Valid)
        // Apartment stays optional at the step level.
        form.apt = ""
        XCTAssertTrue(form.isStep2Valid)
    }

    func testLikenessConsentDefaultsToUnchecked() {
        // 2.9: the ONE remaining review checkbox (likeness/promo) defaults to
        // UNCHECKED — consent must be an affirmative act.
        XCTAssertFalse(AvafliPrizeClaimForm().authorizesLikeness)
    }

    func testLikenessConsentIsOptionalForSubmit() {
        // 2.9: submit is never gated on the likeness/promo checkbox.
        var form = validForm
        form.authorizesLikeness = false
        XCTAssertTrue(form.isValid)
        form.authorizesLikeness = true
        XCTAssertTrue(form.isValid)
    }

    // MARK: Likeness copy names the publisher (2.9.3)

    func testPublisherNameResolutionPrefersServerFedAppName() {
        XCTAssertEqual(AvafliV2PublisherName.resolve(sdkAppName: "Rumble", host: "HostApp"), "Rumble")
        // Blank server value falls through to the host app's display name.
        XCTAssertEqual(AvafliV2PublisherName.resolve(sdkAppName: "   ", host: "HostApp"), "HostApp")
        XCTAssertEqual(AvafliV2PublisherName.resolve(sdkAppName: nil, host: "HostApp"), "HostApp")
        // Nothing anywhere → nil (generic copy).
        XCTAssertNil(AvafliV2PublisherName.resolve(sdkAppName: nil, host: nil))
        XCTAssertNil(AvafliV2PublisherName.resolve(sdkAppName: "", host: "  "))
    }

    func testLikenessConsentCopyNamesThePublisher() {
        let named = AvafliClaimReviewView.likenessConsentText(publisherName: "Rumble")
        XCTAssertEqual(
            named,
            "I authorize Rumble and its promotional partners to use my name, city, profile photo, and likeness for winner announcements and promotional purposes. (Optional)"
        )
        // No resolvable name → the old generic wording.
        XCTAssertTrue(
            AvafliClaimReviewView.likenessConsentText(publisherName: nil)
                .hasPrefix("I authorize this app's publisher and its promotional partners")
        )
    }

    func testZipValidation() {
        XCTAssertTrue(AvafliPrizeClaimForm.isValidZip("11737"))
        XCTAssertTrue(AvafliPrizeClaimForm.isValidZip(" 11737 "))   // trimmed
        XCTAssertFalse(AvafliPrizeClaimForm.isValidZip("1173"))     // too short
        XCTAssertFalse(AvafliPrizeClaimForm.isValidZip("117378"))   // too long
        XCTAssertFalse(AvafliPrizeClaimForm.isValidZip("1173a"))    // non-digit
        XCTAssertFalse(AvafliPrizeClaimForm.isValidZip(""))
    }

    func testDisplayNameIsFirstNamePlusLastInitial() {
        XCTAssertEqual(validForm.displayName, "Catherine C.")
        var form = validForm
        form.lastName = ""
        form.firstName = "Sam"
        XCTAssertEqual(form.displayName, "Sam")
    }

    /// The official rules promise "50 states and the District of Columbia".
    func testFiftyStatesPlusDC() {
        XCTAssertEqual(AvafliPrizeClaimForm.usStates.count, 51)
        XCTAssertEqual(Set(AvafliPrizeClaimForm.usStates).count, 51)
        XCTAssertTrue(AvafliPrizeClaimForm.usStates.contains("District of Columbia"))
        // Alphabetical placement: between Delaware and Florida.
        XCTAssertEqual(AvafliPrizeClaimForm.usStates, AvafliPrizeClaimForm.usStates.sorted())
    }

    // MARK: - Prize text derivation (shared with capture strip / prize card)

    func testCashPrizeStripHeadline() {
        XCTAssertEqual(
            AvafliV2PrizeText.stripHeadline(description: "Cash Prize", value: 1000),
            "$1,000.00 CASH PRIZE"
        )
        // Empty description defaults to cash.
        XCTAssertEqual(
            AvafliV2PrizeText.stripHeadline(description: "", value: 500),
            "$500.00 CASH PRIZE"
        )
    }

    func testNonCashStripHeadlineUsesArticle() {
        XCTAssertEqual(
            AvafliV2PrizeText.stripHeadline(description: "Apple Watch Ultra 3", value: 799),
            "Win an Apple Watch Ultra 3"
        )
        XCTAssertEqual(
            AvafliV2PrizeText.stripHeadline(description: "PlayStation 5", value: 500),
            "Win a PlayStation 5"
        )
        // Leading non-letter ("$500 …" reads "a five-hundred…") takes "a".
        XCTAssertEqual(
            AvafliV2PrizeText.stripHeadline(description: "$500 Amazon Gift Card", value: 500),
            "Win a $500 Amazon Gift Card"
        )
    }

    func testValueLineSuppressedWhenDescriptionStatesAmount() {
        XCTAssertFalse(AvafliV2PrizeText.showsValueLine(description: "$500 Amazon Gift Card", value: 500))
        XCTAssertTrue(AvafliV2PrizeText.showsValueLine(description: "Apple Watch Ultra 3", value: 799))
        XCTAssertFalse(AvafliV2PrizeText.showsValueLine(description: "Apple Watch", value: 0))
    }

    // MARK: - Award date display

    func testMonthYearDisplayFromISO() {
        XCTAssertEqual(
            AvafliClaimDates.monthYearDisplay(fromISO: "2026-08-04T12:34:56Z"),
            "AUGUST, 2026"
        )
        XCTAssertEqual(
            AvafliClaimDates.monthYearDisplay(fromISO: "2026-08-04T12:34:56.789Z"),
            "AUGUST, 2026"
        )
        XCTAssertEqual(
            AvafliClaimDates.monthYearDisplay(fromISO: "2026-12-31"),
            "DECEMBER, 2026"
        )
    }

    func testMonthYearDisplayFallsBackToNow() {
        let now = DateComponents(
            calendar: .init(identifier: .gregorian), year: 2026, month: 8, day: 4
        ).date!
        XCTAssertEqual(AvafliClaimDates.monthYearDisplay(fromISO: nil, now: now), "AUGUST, 2026")
        XCTAssertEqual(AvafliClaimDates.monthYearDisplay(fromISO: "garbage", now: now), "AUGUST, 2026")
    }

    // MARK: - PrizeClaimBlock decode contract

    func testPrizeClaimBlockDecodesPending() throws {
        let json = """
        {
            "status": "pending",
            "giveawayId": "gw_123",
            "prizeDescription": "Cash Prize",
            "prizeValue": 1000
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(PrizeClaimBlock.self, from: json)
        XCTAssertTrue(block.isPending)
        XCTAssertEqual(block.giveawayId, "gw_123")
        XCTAssertNil(block.maskedEmail)   // older backends omit it
        XCTAssertNil(block.claimNumber)
        XCTAssertNil(block.submittedAt)
    }

    func testPrizeClaimBlockDecodesMaskedEmail() throws {
        let json = """
        {
            "status": "pending",
            "giveawayId": "gw_123",
            "prizeDescription": "Cash Prize",
            "prizeValue": 1000,
            "maskedEmail": "d********r@winr.example.com"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(PrizeClaimBlock.self, from: json)
        XCTAssertEqual(block.maskedEmail, "d********r@winr.example.com")
    }

    func testPrizeClaimBlockDecodesSubmitted() throws {
        let json = """
        {
            "status": "submitted",
            "giveawayId": "gw_123",
            "prizeDescription": "Cash Prize",
            "prizeValue": 1000,
            "claimNumber": "9823457758",
            "submittedAt": "2026-08-04T12:00:00Z"
        }
        """.data(using: .utf8)!
        let block = try JSONDecoder().decode(PrizeClaimBlock.self, from: json)
        XCTAssertFalse(block.isPending)
        XCTAssertEqual(block.claimNumber, "9823457758")
    }

    func testGetActiveGiveawayResponseDecodesWithoutPrizeClaim() throws {
        // The block is optional — existing responses must keep decoding.
        let json = """
        { "giveaway": null, "claimedToday": false }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: json)
        XCTAssertNil(response.prizeClaim)
    }

    func testSubmitPrizeClaimRequestBodyOmitsEmptyOptionals() throws {
        let request = SubmitPrizeClaimRequest(
            giveawayId: "gw_123",
            firstName: "Catherine",
            lastName: "Cinosta",
            phone: nil,
            street: "5 Haide Pl.",
            apt: nil,
            city: "Brooklyn",
            state: "New York",
            zip: "11737",
            country: "United States",
            photoBase64: nil,
            promoConsentGranted: false
        )
        XCTAssertEqual(request.path, "submitPrizeClaim")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(envelope["data"] as? [String: Any])
        XCTAssertEqual(data["giveawayId"] as? String, "gw_123")
        XCTAssertEqual(data["country"] as? String, "United States")
        // The promo/likeness consent is ALWAYS sent, even when declined.
        XCTAssertEqual(data["promoConsentGranted"] as? Bool, false)
        XCTAssertNil(data["phone"])
        XCTAssertNil(data["apt"])
        XCTAssertNil(data["photoBase64"])
        XCTAssertNil(data["story"])
    }

    func testSubmitPrizeClaimRequestIncludesPromoConsent() throws {
        let request = SubmitPrizeClaimRequest(
            giveawayId: "gw_123",
            firstName: "Catherine",
            lastName: "Cinosta",
            phone: nil,
            street: "5 Haide Pl.",
            apt: nil,
            city: "Brooklyn",
            state: "New York",
            zip: "11737",
            country: "United States",
            photoBase64: nil,
            promoConsentGranted: true
        )
        let body = try XCTUnwrap(request.body)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(envelope["data"] as? [String: Any])
        XCTAssertEqual(data["promoConsentGranted"] as? Bool, true)
        // The story no longer rides the submit payload (2.9) — it goes through
        // attachClaimStory AFTER submit.
        XCTAssertNil(data["story"])
    }

    // MARK: - attachClaimStory (2.9 — post-submit story)

    func testAttachClaimStoryRequestShape() throws {
        let request = AttachClaimStoryRequest(story: "I'm going to pay off my car!")
        XCTAssertEqual(request.path, "attachClaimStory")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try XCTUnwrap(envelope["data"] as? [String: Any])
        XCTAssertEqual(data["story"] as? String, "I'm going to pay off my car!")
        let response = try JSONDecoder().decode(
            AttachClaimStoryResponse.self,
            from: #"{ "saved": true }"#.data(using: .utf8)!
        )
        XCTAssertTrue(response.saved)
    }

    // MARK: - Share actions (2.9 — honest per-platform behavior)

    func testTweetIntentURLEncodesText() throws {
        let url = try XCTUnwrap(AvafliShareActions.tweetIntentURL(
            text: "I just won $1,000.00 CASH PRIZE in Solitaire! https://example.com/app"
        ))
        XCTAssertEqual(url.host, "twitter.com")
        XCTAssertEqual(url.path, "/intent/tweet")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "text" })?.value,
            "I just won $1,000.00 CASH PRIZE in Solitaire! https://example.com/app"
        )
    }

    func testFacebookSharerURLRequiresShareUrl() throws {
        XCTAssertNil(AvafliShareActions.facebookSharerURL(shareUrl: nil))
        XCTAssertNil(AvafliShareActions.facebookSharerURL(shareUrl: ""))
        let url = try XCTUnwrap(AvafliShareActions.facebookSharerURL(shareUrl: "https://example.com/app"))
        XCTAssertEqual(url.host, "www.facebook.com")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "u" })?.value,
            "https://example.com/app"
        )
    }

    // MARK: - Share-link UTM tagging

    func testTaggedShareUrlAppendsToPlainURL() {
        XCTAssertEqual(
            AvafliShareActions.taggedShareUrl("https://example.com/app", network: "x"),
            "https://example.com/app?utm_source=x&utm_medium=avafli_share"
        )
    }

    func testTaggedShareUrlAppendsToURLWithExistingQuery() {
        XCTAssertEqual(
            AvafliShareActions.taggedShareUrl("https://example.com/app?ref=abc", network: "facebook"),
            "https://example.com/app?ref=abc&utm_source=facebook&utm_medium=avafli_share"
        )
    }

    func testTaggedShareUrlLeavesExistingUtmSourceUntouched() {
        let url = "https://example.com/app?utm_source=publisher&utm_medium=email"
        XCTAssertEqual(AvafliShareActions.taggedShareUrl(url, network: "x"), url)
    }

    func testTaggedShareUrlPassesThroughNilAndEmpty() {
        XCTAssertNil(AvafliShareActions.taggedShareUrl(nil, network: "x"))
        XCTAssertEqual(AvafliShareActions.taggedShareUrl("", network: "x"), "")
    }

    func testUtmSourcePerNetwork() {
        XCTAssertEqual(AvafliShareActions.utmSource(for: .x), "x")
        XCTAssertEqual(AvafliShareActions.utmSource(for: .facebook), "facebook")
        XCTAssertEqual(AvafliShareActions.utmSource(for: .instagram), "instagram")
        XCTAssertEqual(AvafliShareActions.utmSource(for: .snapchat), "snapchat")
        XCTAssertEqual(AvafliShareActions.utmSource(for: .tiktok), "tiktok")
    }

    // MARK: - sdkConfig shareUrl (optional — safe against current prod)

    func testSDKConfigDecodesWithoutShareUrl() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertNil(config.shareUrl)
    }

    func testSDKConfigDecodesShareUrl() throws {
        let json = #"{ "shareUrl": "https://example.com/get-the-app" }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertEqual(config.shareUrl, "https://example.com/get-the-app")
    }

    // MARK: - sdkConfig placesApiKey (optional — safe against current prod)

    func testSDKConfigDecodesWithoutPlacesApiKey() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertNil(config.placesApiKey)
    }

    func testSDKConfigDecodesPlacesApiKey() throws {
        let json = #"{ "placesApiKey": "AIza-test-key" }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertEqual(config.placesApiKey, "AIza-test-key")
    }

    // MARK: - sdkConfig experience.winnerBannerEnabled (optional — DEFAULT OFF)
    // Aug 31 GTM decision: the "WE HAVE A WINNER!" banner shows ONLY when the
    // admin flipped the flag to true. The dashboard gates on the exact
    // expression `experience?.winnerBannerEnabled == true`, so absent, null,
    // and false must all evaluate to hidden — same contract as the Android,
    // web, and Flutter SDKs.

    func testWinnerBannerFlagDecodesTrue() throws {
        let json = #"{ "experience": { "winnerBannerEnabled": true } }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertEqual(config.experience?.winnerBannerEnabled, true)
        XCTAssertTrue(config.experience?.winnerBannerEnabled == true)
    }

    func testWinnerBannerFlagDecodesFalse() throws {
        let json = #"{ "experience": { "winnerBannerEnabled": false } }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertEqual(config.experience?.winnerBannerEnabled, false)
        XCTAssertFalse(config.experience?.winnerBannerEnabled == true)
    }

    func testWinnerBannerFlagAbsentFromExperienceHidesBanner() throws {
        // Current prod configs carry experience without the new key.
        let json = #"{ "experience": { "autoOpenEnabled": true } }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertNil(config.experience?.winnerBannerEnabled)
        XCTAssertFalse(config.experience?.winnerBannerEnabled == true)
        XCTAssertEqual(config.experience?.autoOpenEnabled, true)
    }

    func testWinnerBannerFlagAbsentExperienceHidesBanner() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertNil(config.experience)
        XCTAssertFalse(config.experience?.winnerBannerEnabled == true)
    }

    func testWinnerBannerFlagJSONNullHidesBanner() throws {
        let json = #"{ "experience": { "winnerBannerEnabled": null } }"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(SDKConfigResponse.self, from: json)
        XCTAssertNil(config.experience?.winnerBannerEnabled)
        XCTAssertFalse(config.experience?.winnerBannerEnabled == true)
    }

    // MARK: - Places address-component mapping (pure)

    private func component(
        _ type: String, long: String, short: String? = nil
    ) -> AvafliPlaceAddressComponent {
        AvafliPlaceAddressComponent(longText: long, shortText: short ?? long, types: [type])
    }

    func testPlacesMapperMapsFullUSAddress() {
        let mapped = AvafliPlacesAddressMapper.address(from: [
            component("street_number", long: "1600"),
            component("route", long: "Amphitheatre Parkway"),
            component("locality", long: "Mountain View"),
            component("administrative_area_level_1", long: "California", short: "CA"),
            component("postal_code", long: "94043"),
            component("country", long: "United States", short: "US"),
        ])
        XCTAssertEqual(mapped.street, "1600 Amphitheatre Parkway")
        XCTAssertEqual(mapped.city, "Mountain View")
        // shortText expands to the full name the State menu uses.
        XCTAssertEqual(mapped.state, "California")
        XCTAssertEqual(mapped.zip, "94043")
    }

    func testPlacesMapperExpandsEveryMenuStateAndPassesThroughUnmapped() {
        // Every USPS code round-trips to a name that exists in the State
        // menu's options — a filled state always renders like a picked one.
        let codes = [
            "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA",
            "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD", "MA",
            "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY",
            "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX",
            "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        ]
        XCTAssertEqual(codes.count, AvafliPrizeClaimForm.usStates.count)
        for code in codes {
            let expanded = AvafliPlacesAddressMapper.expandedStateName(code)
            XCTAssertNotEqual(expanded, code, "\(code) should expand to a full name")
            XCTAssertTrue(
                AvafliPrizeClaimForm.usStates.contains(expanded),
                "\(code) expanded to \(expanded), which is not a State menu option"
            )
        }
        XCTAssertEqual(AvafliPlacesAddressMapper.expandedStateName("NY"), "New York")

        // Unmapped codes (territories) pass through so the field still fills.
        XCTAssertEqual(AvafliPlacesAddressMapper.expandedStateName("PR"), "PR")
        XCTAssertEqual(AvafliPlacesAddressMapper.expandedStateName("GU"), "GU")
        XCTAssertEqual(AvafliPlacesAddressMapper.expandedStateName(""), "")
    }

    func testPlacesMapperCityFallsBackToSublocalityThenPostalTown() {
        // No locality → sublocality_level_1 (e.g. Brooklyn).
        let sublocality = AvafliPlacesAddressMapper.address(from: [
            component("route", long: "Bedford Avenue"),
            component("sublocality_level_1", long: "Brooklyn"),
            component("administrative_area_level_1", long: "New York", short: "NY"),
        ])
        XCTAssertEqual(sublocality.city, "Brooklyn")

        // Neither locality nor sublocality → postal_town.
        let postalTown = AvafliPlacesAddressMapper.address(from: [
            component("postal_town", long: "Springfield")
        ])
        XCTAssertEqual(postalTown.city, "Springfield")

        // locality wins over the fallbacks when present.
        let locality = AvafliPlacesAddressMapper.address(from: [
            component("sublocality_level_1", long: "Brooklyn"),
            component("locality", long: "New York"),
        ])
        XCTAssertEqual(locality.city, "New York")
    }

    func testPlacesMapperHandlesMissingComponents() {
        // Route only — no street number, no zip, no state.
        let routeOnly = AvafliPlacesAddressMapper.address(from: [
            component("route", long: "Main Street")
        ])
        XCTAssertEqual(routeOnly.street, "Main Street")
        XCTAssertEqual(routeOnly.city, "")
        XCTAssertEqual(routeOnly.state, "")
        XCTAssertEqual(routeOnly.zip, "")

        // Empty component list — everything blank, nothing crashes.
        let empty = AvafliPlacesAddressMapper.address(from: [])
        XCTAssertEqual(empty, AvafliAutocompletedAddress(street: "", city: "", state: "", zip: ""))
    }

    // MARK: - adoptionPending (optional — safe against current prod)

    func testRegisterResponseDecodesAdoptionPending() throws {
        let json = """
        { "token": "t", "refreshToken": "r", "uuid": "u", "adoptionPending": true }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertEqual(response.adoptionPending, true)
    }

    func testRegisterResponseDecodesWithoutAdoptionPending() throws {
        let json = """
        { "token": "t", "refreshToken": "r", "uuid": "u" }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertNil(response.adoptionPending)
    }

    func testRestageAdoptionRequestShape() throws {
        let request = RestageAdoptionRequest()
        XCTAssertEqual(request.path, "restageAdoption")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNotNil(envelope["data"])
        let response = try JSONDecoder().decode(
            RestageAdoptionResponse.self,
            from: #"{ "sent": true }"#.data(using: .utf8)!
        )
        XCTAssertTrue(response.sent)
    }

    // MARK: - Photo downscale

    func testPhotoDownscaleCapsLongEdge() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let scaled = AvafliClaimPhoto.downscaled(big, longEdge: 1200)
        XCTAssertEqual(max(scaled.size.width, scaled.size.height), 1200, accuracy: 1)
        XCTAssertEqual(min(scaled.size.width, scaled.size.height), 600, accuracy: 1)

        // Already-small images pass through untouched.
        let small = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { _ in }
        XCTAssertEqual(AvafliClaimPhoto.downscaled(small, longEdge: 1200).size, small.size)
    }
}
