//
//  AvafliV2EmailVerificationTests.swift
//  AvafliSDKTests
//
//  The 2.7.0 "verify your email" soft-verification affordance:
//
//  1. The chip-visibility rule — the persistent "Verify your email" chip shows
//     on the dashboard ONLY when the backend reports an explicit
//     `emailVerified == false` (a freshly-typed, unconfirmed email); it stays
//     hidden for verified / partner-passed / adoption-verified / no-email users
//     (where the field is absent) and for an explicit `true`.
//  2. The wire contract — `emailVerified` decodes off the status and submitEmail
//     responses, and the two new callables encode their envelopes correctly.
//
//  This is a SOFT gate: nothing here blocks daily play — it only drives the UI
//  nudge and the confirm/resend calls that establish draw eligibility.
//

import XCTest
@testable import AvafliSDK

final class AvafliV2EmailVerificationTests: XCTestCase {

    // MARK: - Chip visibility rule

    /// The load-bearing rule: only an explicit `false` shows the chip.
    func testChipShowsOnlyForExplicitFalse() {
        XCTAssertTrue(
            AvafliExperienceViewModel.showsVerifyEmailChip(emailVerified: false),
            "A freshly-typed, unconfirmed email (emailVerified == false) must show the chip"
        )
    }

    func testChipHiddenWhenVerified() {
        XCTAssertFalse(
            AvafliExperienceViewModel.showsVerifyEmailChip(emailVerified: true),
            "A verified email must not show the chip"
        )
    }

    func testChipHiddenWhenAbsent() {
        // Absent covers verified / partner-passed / adoption-verified / no email.
        XCTAssertFalse(
            AvafliExperienceViewModel.showsVerifyEmailChip(emailVerified: nil),
            "An absent emailVerified must never show the chip"
        )
    }

    // MARK: - Wire contract: emailVerified decodes off the status response

    func testGetActiveGiveawayDecodesUnverifiedFalse() throws {
        let json = """
        { "emailVerified": false }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: json)
        XCTAssertEqual(response.emailVerified, false)
        XCTAssertTrue(AvafliExperienceViewModel.showsVerifyEmailChip(emailVerified: response.emailVerified))
    }

    func testGetActiveGiveawayAbsentEmailVerifiedIsNil() throws {
        // A response with no emailVerified key (verified/partner/adoption/no-email).
        let json = """
        { "claimedToday": false }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: json)
        XCTAssertNil(response.emailVerified)
        XCTAssertFalse(AvafliExperienceViewModel.showsVerifyEmailChip(emailVerified: response.emailVerified))
    }

    func testSubmitEmailResponseDecodesEmailVerifiedAndSent() throws {
        let json = """
        {
            "success": true,
            "emailVerified": false,
            "emailVerificationSent": true
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubmitEmailResponse.self, from: json)
        XCTAssertEqual(response.emailVerified, false)
        XCTAssertEqual(response.emailVerificationSent, true)
    }

    // MARK: - New callable envelopes

    func testConfirmEmailVerificationRequestEncoding() throws {
        let request = ConfirmEmailVerificationRequest(code: "123456")
        XCTAssertEqual(request.path, "confirmEmailVerification")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["code"] as? String, "123456")
    }

    func testConfirmEmailVerificationResponseDecoding() throws {
        let json = """
        { "verified": true }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ConfirmEmailVerificationResponse.self, from: json)
        XCTAssertTrue(response.verified)
    }

    func testResendEmailVerificationRequestEncoding() throws {
        let request = ResendEmailVerificationRequest()
        XCTAssertEqual(request.path, "resendEmailVerification")
        XCTAssertEqual(request.method, "POST")
        // No arguments — an empty `data` envelope.
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNotNil(json?["data"])
    }

    func testResendEmailVerificationResponseDecoding() throws {
        let json = """
        { "sent": true }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ResendEmailVerificationResponse.self, from: json)
        XCTAssertTrue(response.sent)
    }

    // MARK: - Reused code-error taxonomy

    /// Email verification reuses the adoption three-way error mapping, so a bad
    /// code surfaces the same inline copy the code screen already shows.
    func testConfirmFailuresReuseAdoptionErrorTaxonomy() {
        XCTAssertEqual(
            AvafliExperienceViewModel.codeErrorMessage(for: AvafliError.internalError("This code has expired")),
            AvafliV2Strings.codeExpired
        )
        XCTAssertEqual(
            AvafliExperienceViewModel.codeErrorMessage(for: AvafliError.internalError("Too many attempts")),
            AvafliV2Strings.codeTooManyAttempts
        )
        XCTAssertEqual(
            AvafliExperienceViewModel.codeErrorMessage(for: AvafliError.internalError("nope")),
            AvafliV2Strings.codeIncorrect
        )
    }
}
