//
//  AvafliV2LegalRoutingTests.swift
//  AvafliSDKTests
//
//  The 2.9.4 in-app legal webview plumbing, exercised as pure functions:
//
//  - AvafliV2LegalRouting.privacyPolicyURL: the ?app=1 append (the flag that
//    makes sdk.avafli.com/sdk/privacy render its delete-my-data section),
//    including bases that already carry a query or already carry app=1.
//  - AvafliV2LegalRouting.sheet(for:rulesUrl:): which tapped URLs open the
//    in-app sheet (and with which title) vs. keep the system behavior.
//  - AvafliV2LegalBridge.decision(for:): the winr://delete native bridge the
//    webview's navigation delegate acts on.
//

import XCTest
@testable import AvafliSDK

final class AvafliV2LegalRoutingTests: XCTestCase {

    // MARK: - Privacy URL construction (?app=1)

    func testPrivacyURLAppendsAppFlagToBareURL() {
        XCTAssertEqual(
            AvafliV2LegalRouting.privacyPolicyURL(base: "https://sdk.avafli.com/sdk/privacy")?.absoluteString,
            "https://sdk.avafli.com/sdk/privacy?app=1"
        )
    }

    func testPrivacyURLDefaultsToTheHardcodedConstant() {
        XCTAssertEqual(
            AvafliV2LegalRouting.privacyPolicyURL()?.absoluteString,
            AvafliConstants.privacyURL + "?app=1"
        )
    }

    func testPrivacyURLExtendsAnExistingQuery() {
        XCTAssertEqual(
            AvafliV2LegalRouting.privacyPolicyURL(base: "https://sdk.avafli.com/sdk/privacy?lang=en")?.absoluteString,
            "https://sdk.avafli.com/sdk/privacy?lang=en&app=1"
        )
    }

    func testPrivacyURLNeverDoublesTheAppParam() {
        XCTAssertEqual(
            AvafliV2LegalRouting.privacyPolicyURL(base: "https://sdk.avafli.com/sdk/privacy?app=1")?.absoluteString,
            "https://sdk.avafli.com/sdk/privacy?app=1"
        )
    }

    func testPrivacyURLGarbageBaseReturnsNil() {
        XCTAssertNil(AvafliV2LegalRouting.privacyPolicyURL(base: "not a url ://"))
    }

    // MARK: - Sheet routing (which taps open in-app)

    func testRulesURLTapOpensTheRulesSheetUnmodified() throws {
        let rules = "https://example.com/giveaway/rules"
        let sheet = try XCTUnwrap(
            AvafliV2LegalRouting.sheet(for: XCTUnwrap(URL(string: rules)), rulesUrl: rules)
        )
        XCTAssertEqual(sheet.title, "Official Rules")
        // The rules page has no app=1 contract — the URL loads as-is.
        XCTAssertEqual(sheet.url.absoluteString, rules)
    }

    func testPrivacyURLTapOpensThePrivacySheetWithAppFlag() throws {
        let sheet = try XCTUnwrap(
            AvafliV2LegalRouting.sheet(
                for: XCTUnwrap(URL(string: AvafliConstants.privacyURL)),
                rulesUrl: "https://example.com/rules"
            )
        )
        XCTAssertEqual(sheet.title, "Privacy Policy")
        XCTAssertEqual(sheet.url.absoluteString, AvafliConstants.privacyURL + "?app=1")
    }

    func testPrivacyRoutingDoesNotNeedARulesURL() throws {
        let sheet = AvafliV2LegalRouting.sheet(
            for: try XCTUnwrap(URL(string: AvafliConstants.privacyURL)),
            rulesUrl: nil
        )
        XCTAssertEqual(sheet?.title, "Privacy Policy")
    }

    func testUnrelatedURLKeepsSystemBehavior() throws {
        XCTAssertNil(
            AvafliV2LegalRouting.sheet(
                for: try XCTUnwrap(URL(string: "https://example.com/somewhere")),
                rulesUrl: "https://example.com/rules"
            )
        )
    }

    func testNilRulesURLDoesNotMatchArbitraryURLs() throws {
        XCTAssertNil(
            AvafliV2LegalRouting.sheet(
                for: try XCTUnwrap(URL(string: "https://example.com/rules")),
                rulesUrl: nil
            )
        )
    }

    // MARK: - winr://delete + avafli://delete bridge decisions

    func testWinrDeleteInvokesTheDeleteFlow() {
        // The legacy scheme stays accepted (internal-only, harmless) so older
        // privacy-page revisions keep working after the rebrand.
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "winr://delete")),
            .invokeDelete
        )
    }

    func testAvafliDeleteInvokesTheDeleteFlow() {
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "avafli://delete")),
            .invokeDelete
        )
    }

    func testBridgeIsCaseInsensitive() {
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "WINR://DELETE")),
            .invokeDelete
        )
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "Avafli://DELETE")),
            .invokeDelete
        )
    }

    func testPathFormOfTheBridgeAlsoInvokes() {
        // winr:///delete parses with an empty host and "/delete" as the path.
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "winr:///delete")),
            .invokeDelete
        )
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "avafli:///delete")),
            .invokeDelete
        )
    }

    func testUnknownBridgeSchemeNavigationIsCancelledQuietly() {
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "winr://something-else")),
            .cancel
        )
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "avafli://something-else")),
            .cancel
        )
    }

    func testHTTPSNavigationIsAllowed() {
        // External links inside the legal pages load in the webview normally.
        XCTAssertEqual(
            AvafliV2LegalBridge.decision(for: URL(string: "https://sdk.avafli.com/sdk/privacy?app=1")),
            .allow
        )
    }

    func testNilURLIsAllowed() {
        XCTAssertEqual(AvafliV2LegalBridge.decision(for: nil), .allow)
    }
}
