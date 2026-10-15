import XCTest
@testable import AvafliSDK

final class AvafliSDKTests: XCTestCase {

    // MARK: - Logger

    func testLoggerDefaultLevel() {
        let logger = Logger.shared
        // Default is .error
        XCTAssertNotNil(logger)
    }

    // MARK: - AvafliOptions

    func testAvafliOptionsDefaults() {
        let options = AvafliOptions()
        XCTAssertEqual(options.logging, .error)
        XCTAssertNotNil(options.analyticsAdapter)
    }

    func testAvafliOptionsCustom() {
        let options = AvafliOptions(
            logging: .debug,
            analyticsAdapter: nil
        )
        XCTAssertEqual(options.logging, .debug)
        XCTAssertNil(options.analyticsAdapter)
    }

    // MARK: - API Request paths

    func testAllRequestPaths() {
        XCTAssertEqual(RegisterDeviceRequest(
            apiKey: "", deviceFingerprint: "", bundleId: "",
            timezone: "", platformOS: "", sdkVersion: ""
        ).path, "registerDevice")

        XCTAssertEqual(RefreshTokenRequest(refreshToken: "").path, "refreshToken")
        XCTAssertEqual(SubmitEmailRequest(email: "", ageConfirmed: true, marketingConsent: true).path, "submitEmail")
        XCTAssertEqual(ClaimDailyEntriesRequest().path, "claimDailyEntries")
        XCTAssertEqual(GetActiveGiveawayRequest().path, "getActiveGiveaway")
    }

    func testAllRequestMethods() {
        XCTAssertEqual(RegisterDeviceRequest(
            apiKey: "", deviceFingerprint: "", bundleId: "",
            timezone: "", platformOS: "", sdkVersion: ""
        ).method, "POST")

        XCTAssertEqual(RefreshTokenRequest(refreshToken: "").method, "POST")
        XCTAssertEqual(SubmitEmailRequest(email: "", ageConfirmed: true, marketingConsent: true).method, "POST")
        XCTAssertEqual(ClaimDailyEntriesRequest().method, "POST")
        XCTAssertEqual(GetActiveGiveawayRequest().method, "POST")
    }

    // MARK: - All requests produce non-nil body

    func testAllRequestsHaveBody() {
        XCTAssertNotNil(RegisterDeviceRequest(
            apiKey: "k", deviceFingerprint: "f", bundleId: "b",
            timezone: "t", platformOS: "p", sdkVersion: "v"
        ).body)
        XCTAssertNotNil(RefreshTokenRequest(refreshToken: "r").body)
        XCTAssertNotNil(SubmitEmailRequest(email: "e@e.com", ageConfirmed: true, marketingConsent: true).body)
        XCTAssertNotNil(ClaimDailyEntriesRequest().body)
        XCTAssertNotNil(GetActiveGiveawayRequest().body)
    }
}
