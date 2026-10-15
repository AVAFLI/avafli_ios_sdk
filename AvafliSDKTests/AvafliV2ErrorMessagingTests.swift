//
//  AvafliV2ErrorMessagingTests.swift
//  AvafliSDKTests
//
//  The 2.6.0 user-facing error messaging (the Master Field List's
//  "User Message (UI)" column):
//
//  1. AvafliV2Strings — the mandated copy, word for word. These strings are a
//     product/legal contract; a drive-by rewording must fail a test.
//  2. AvafliV2FieldValidation — name / phone / email rules behind the inline
//     errors.
//  3. AvafliPrizeClaimForm step-1 validity + phone normalization on the wire.
//  4. URLSessionNetworkClient.isGeoBlockedError — recognizing the backend
//     geo-fence rejection (gatekeeper.ts enforceGeoFence messages).
//  5. AvafliExperienceViewModel.claimFailureResolution — the claim-failure
//     policy. The load-bearing rule: NO resolution fabricates a local
//     success; a transport failure resolves to the honest unclaimed
//     dashboard + connection notice.
//

import XCTest
@testable import AvafliSDK

// MARK: - Mandated copy

final class AvafliV2StringsTests: XCTestCase {

    func testMandatedCopyIsExact() {
        XCTAssertEqual(AvafliV2Strings.invalidEmail, "Please enter a valid email address.")
        XCTAssertEqual(AvafliV2Strings.invalidFirstName, "Please enter a valid first name.")
        XCTAssertEqual(AvafliV2Strings.invalidLastName, "Please enter a valid last name.")
        XCTAssertEqual(AvafliV2Strings.invalidPhone, "Please enter a valid 10-digit mobile number.")
        XCTAssertEqual(
            AvafliV2Strings.alreadyEnteredToday,
            "You've already entered today. Come back tomorrow to keep your streak going!"
        )
        XCTAssertEqual(AvafliV2Strings.geoBlockedHeadline, "Not available in your location")
        XCTAssertEqual(
            AvafliV2Strings.geoBlockedBody,
            "This promotion is only available to users located in the United States. Please check your location settings or try again from an eligible location."
        )
        XCTAssertEqual(AvafliV2Strings.sessionExpired, "Your session has expired. Please try again.")
        XCTAssertEqual(
            AvafliV2Strings.claimNotRecorded,
            "We couldn't record today's entry. Check your connection and try again."
        )
        XCTAssertEqual(
            AvafliV2Strings.emailSubmitFailed,
            "Something went wrong sending your email. Please try again."
        )
    }
}

// MARK: - Field validation

final class AvafliV2NameValidationTests: XCTestCase {

    func testOrdinaryNamesPass() {
        for name in ["Catherine", "Mary Jane", "O'Brien", "Jean-Luc", "St. John", "Anne Marie"] {
            XCTAssertTrue(AvafliV2FieldValidation.isValidName(name), "\(name) must be valid")
        }
    }

    func testUnicodeLettersPass() {
        for name in ["José", "Renée", "Björk", "Nguyễn", "Søren", "D’Angelo"] {
            XCTAssertTrue(AvafliV2FieldValidation.isValidName(name), "\(name) must be valid")
        }
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertTrue(AvafliV2FieldValidation.isValidName("  Catherine  "))
    }

    func testBlankNamesFail() {
        XCTAssertFalse(AvafliV2FieldValidation.isValidName(""))
        XCTAssertFalse(AvafliV2FieldValidation.isValidName("   "))
    }

    func testDigitsAndSymbolsFail() {
        for name in ["Bob123", "!!!", "Jane@Doe", "First_Last", "a,b"] {
            XCTAssertFalse(AvafliV2FieldValidation.isValidName(name), "\(name) must be invalid")
        }
    }

    func testPunctuationAloneIsNotAName() {
        for name in [".", "--", "' '", "-.-"] {
            XCTAssertFalse(AvafliV2FieldValidation.isValidName(name), "\(name) must be invalid")
        }
    }

    func testFiftyCharacterCap() {
        let fifty = String(repeating: "a", count: 50)
        XCTAssertTrue(AvafliV2FieldValidation.isValidName(fifty))
        XCTAssertFalse(AvafliV2FieldValidation.isValidName(fifty + "a"))
    }
}

final class AvafliV2PhoneValidationTests: XCTestCase {

    func testTenDigitsPass() {
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone("5551234567"), "5551234567")
    }

    func testFormattingIsStripped() {
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone("(555) 123-4567"), "5551234567")
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone("555.123.4567"), "5551234567")
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone(" 555 123 4567 "), "5551234567")
    }

    func testLeadingCountryOneKeepsLastTen() {
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone("15551234567"), "5551234567")
        XCTAssertEqual(AvafliV2FieldValidation.normalizedUSPhone("+1 (555) 123-4567"), "5551234567")
    }

    func testWrongLengthsFail() {
        XCTAssertNil(AvafliV2FieldValidation.normalizedUSPhone("555123456"))      // 9
        XCTAssertNil(AvafliV2FieldValidation.normalizedUSPhone("55512345678"))    // 11, no leading 1
        XCTAssertNil(AvafliV2FieldValidation.normalizedUSPhone("555555555555"))   // 12
        XCTAssertNil(AvafliV2FieldValidation.normalizedUSPhone("call me"))
        XCTAssertNil(AvafliV2FieldValidation.normalizedUSPhone(""))
    }
}

// MARK: - Claim form step 1 (names + optional phone)

final class AvafliV2ClaimStep1ValidationTests: XCTestCase {

    private var form: AvafliPrizeClaimForm {
        var f = AvafliPrizeClaimForm()
        f.firstName = "Catherine"
        f.lastName = "Cinosta"
        return f
    }

    func testBlankPhoneStaysOptional() {
        var f = form
        f.phone = ""
        XCTAssertTrue(f.isPhoneEmptyOrValid)
        XCTAssertTrue(f.isStep1Valid)
        XCTAssertNil(f.normalizedPhone, "Blank phone must send nil on the wire")
    }

    func testTypedPhoneMustBeTenDigits() {
        var f = form
        f.phone = "555-123"
        XCTAssertFalse(f.isPhoneEmptyOrValid)
        XCTAssertFalse(f.isStep1Valid, "An invalid non-blank phone must block continue")
        f.phone = "+1 (555) 123-4567"
        XCTAssertTrue(f.isStep1Valid)
        XCTAssertEqual(f.normalizedPhone, "5551234567", "Wire format is the bare 10 digits")
    }

    func testInvalidNamesBlockStepOne() {
        var f = form
        f.firstName = "Bob123"
        XCTAssertFalse(f.isStep1Valid)
        f.firstName = "Catherine"
        f.lastName = String(repeating: "x", count: 51)
        XCTAssertFalse(f.isStep1Valid)
    }

    func testInvalidPhoneAlsoBlocksFinalSubmit() {
        var f = form
        f.street = "5 Haide Pl."
        f.city = "Brooklyn"
        f.state = "New York"
        f.zip = "11737"
        XCTAssertTrue(f.isValid)
        f.phone = "12345"
        XCTAssertFalse(f.isValid, "Step-1 rules must hold at SUBMIT too")
    }
}

// MARK: - Geo-block detection (NetworkClient)

final class AvafliGeoBlockedErrorMappingTests: XCTestCase {

    /// The exact backend messages from functions/src/gatekeeper.ts.
    private let nonUS =
        "This promotion is only available to users located in one of the 50 United States or Washington, D.C."
    private let unverified =
        "We couldn't verify your location. This promotion is only available in the United States."

    func testBothBackendGeoMessagesAreRecognized() {
        XCTAssertTrue(URLSessionNetworkClient.isGeoBlockedError(message: nonUS))
        XCTAssertTrue(URLSessionNetworkClient.isGeoBlockedError(message: unverified))
    }

    func testRecognitionSurvivesCallableEnvelopeWrapping() {
        // The 403 branch checks the RAW body string, which is the callable
        // JSON envelope — the contains-check must still hit.
        let body = #"{"error":{"message":"\#(nonUS)","status":"PERMISSION_DENIED"}}"#
        XCTAssertTrue(URLSessionNetworkClient.isGeoBlockedError(message: body))
    }

    func testOtherErrorsAreNotGeoBlocks() {
        XCTAssertFalse(URLSessionNetworkClient.isGeoBlockedError(message: "API key suspended or revoked"))
        XCTAssertFalse(URLSessionNetworkClient.isGeoBlockedError(message: "Already claimed daily entries today"))
        XCTAssertFalse(URLSessionNetworkClient.isGeoBlockedError(message: "internal"))
        XCTAssertFalse(URLSessionNetworkClient.isGeoBlockedError(message: ""))
    }

    func testSuspendedDetectionUnaffected() {
        XCTAssertTrue(URLSessionNetworkClient.isSuspendedError(message: "Publisher account suspended"))
        XCTAssertFalse(URLSessionNetworkClient.isSuspendedError(message: nonUS))
    }
}

// MARK: - Claim failure policy (no fabricated success, ever)

final class AvafliClaimFailureResolutionTests: XCTestCase {

    private typealias Resolution = AvafliExperienceViewModel.ClaimFailureResolution

    private func resolve(_ error: Error, auto: Bool = true, hasRegistered: Bool = true) -> Resolution {
        AvafliExperienceViewModel.claimFailureResolution(for: error, auto: auto, hasRegistered: hasRegistered)
    }

    // The 2.6.0 fix: a transport failure used to fake a local success and
    // celebrate an entry that was never recorded. It must now resolve to the
    // honest unclaimed dashboard + connection notice — for BOTH auto and
    // manual claims.
    func testTransportFailureNeverFabricatesSuccess() {
        let urlError = URLError(.notConnectedToInternet)
        XCTAssertEqual(resolve(urlError, auto: true), .connectionNotice)
        XCTAssertEqual(resolve(urlError, auto: false), .connectionNotice)

        let wrapped = AvafliError.network(URLError(.timedOut))
        XCTAssertEqual(resolve(wrapped, auto: true), .connectionNotice)
        XCTAssertEqual(resolve(wrapped, auto: false), .connectionNotice)
    }

    func testAlreadyClaimedShowsTheNotice() {
        let error = AvafliError.internalError("Already claimed daily entries today")
        XCTAssertEqual(resolve(error, auto: true), .alreadyClaimedNotice)
        XCTAssertEqual(resolve(error, auto: false), .alreadyClaimedNotice)
    }

    func testGeoBlockGetsTheDedicatedState() {
        XCTAssertEqual(resolve(AvafliError.geoBlocked, auto: true), .geoBlocked)
        XCTAssertEqual(resolve(AvafliError.geoBlocked, auto: false), .geoBlocked)
    }

    func testDeadSessionGetsTheRetryState() {
        XCTAssertEqual(resolve(AvafliError.authenticationRequired, hasRegistered: true), .sessionExpired)
    }

    func testUnregisteredAuthFailureIsNotASessionExpiry() {
        // A fresh install that never completed the handshake must not see
        // "Your session has expired" — it takes the normal rejection path.
        XCTAssertEqual(resolve(AvafliError.authenticationRequired, auto: true, hasRegistered: false), .silentUnclaimed)
    }

    func testAutoBackendRejectionStaysSilent() {
        XCTAssertEqual(resolve(AvafliError.internalError("consent required"), auto: true), .silentUnclaimed)
        XCTAssertEqual(resolve(AvafliError.serviceUnavailable, auto: true), .silentUnclaimed)
    }

    func testManualBackendRejectionSurfacesTheErrorState() {
        XCTAssertEqual(resolve(AvafliError.internalError("consent required"), auto: false), .surfaceError)
    }
}
