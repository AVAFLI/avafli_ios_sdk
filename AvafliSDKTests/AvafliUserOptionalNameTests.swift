import XCTest
@testable import AvafliSDK

/// firstName/lastName are optional on AvafliUser (2.6.3). A publisher can build a
/// user from whatever identity data they have — even just an id — and the SDK
/// captures the rest (email via its capture screen, name at prize-claim). These
/// pin that the id-only user constructs, is NOT a guest, and that the guest
/// sentinel semantics (guest is id-empty) are unaffected.
final class AvafliUserOptionalNameTests: XCTestCase {

    func testIdOnlyUserConstructsWithEmptyNames() {
        let user = AvafliUser(id: "user_123")
        XCTAssertEqual(user.id, "user_123")
        XCTAssertEqual(user.firstName, "")
        XCTAssertEqual(user.lastName, "")
        XCTAssertNil(user.phone)
        XCTAssertNil(user.email)
    }

    func testIdOnlyUserIsNotGuest() {
        // A non-empty id but absent names must NOT be treated as a guest —
        // guest is defined solely by an empty id.
        XCTAssertFalse(AvafliUser(id: "user_123").isGuest)
    }

    func testGuestSentinelStillGuest() {
        XCTAssertTrue(AvafliUser.guest.isGuest)
        XCTAssertTrue(AvafliUser(id: "").isGuest)
    }

    func testConfigureAcceptsIdOnlyUser() {
        // configure() must accept an id-only user without throwing/validation
        // rejection. The config simply holds the user.
        let config = AvafliConfiguration(
            apiKey: "winr_live_test",
            environment: .production,
            bundleId: "com.example.myapp",
            user: AvafliUser(id: "user_123")
        )
        XCTAssertEqual(config.user.id, "user_123")
        XCTAssertFalse(config.user.isGuest)
    }
}
