import XCTest
@testable import AvafliSDK

final class EmailValidationTests: XCTestCase {

    // The SDK's email validation pattern:
    // ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$
    // Exercised through the shared validator (AvafliV2FieldValidation), which is
    // what the capture screen's inline error + CTA gating actually use.
    private func isEmailValid(_ email: String) -> Bool {
        AvafliV2FieldValidation.isValidEmail(email)
    }

    // MARK: - Valid emails

    func testSimpleEmail() {
        XCTAssertTrue(isEmailValid("user@example.com"))
    }

    func testEmailWithDots() {
        XCTAssertTrue(isEmailValid("first.last@example.com"))
    }

    func testEmailWithPlus() {
        XCTAssertTrue(isEmailValid("user+tag@example.com"))
    }

    func testEmailWithNumbers() {
        XCTAssertTrue(isEmailValid("user123@test456.org"))
    }

    func testEmailWithHyphenDomain() {
        XCTAssertTrue(isEmailValid("user@my-domain.com"))
    }

    func testEmailWithUnderscore() {
        XCTAssertTrue(isEmailValid("user_name@example.com"))
    }

    func testEmailWithPercent() {
        XCTAssertTrue(isEmailValid("user%name@example.com"))
    }

    func testEmailWithSubdomain() {
        XCTAssertTrue(isEmailValid("user@mail.example.co.uk"))
    }

    func testEmailWithLongTLD() {
        XCTAssertTrue(isEmailValid("user@example.museum"))
    }

    // MARK: - Invalid emails

    func testEmptyString() {
        XCTAssertFalse(isEmailValid(""))
    }

    func testNoAtSign() {
        XCTAssertFalse(isEmailValid("userexample.com"))
    }

    func testNoDomain() {
        XCTAssertFalse(isEmailValid("user@"))
    }

    func testNoUser() {
        XCTAssertFalse(isEmailValid("@example.com"))
    }

    func testNoTLD() {
        XCTAssertFalse(isEmailValid("user@example"))
    }

    func testSingleCharTLD() {
        XCTAssertFalse(isEmailValid("user@example.c"))
    }

    func testDoubleAt() {
        XCTAssertFalse(isEmailValid("user@@example.com"))
    }

    func testSpaces() {
        XCTAssertFalse(isEmailValid("user @example.com"))
    }

    func testTrailingSpace() {
        XCTAssertFalse(isEmailValid("user@example.com "))
    }

    func testLeadingSpace() {
        XCTAssertFalse(isEmailValid(" user@example.com"))
    }

    // MARK: - Consent gate (email required before claiming)

    func testEmailStorageRoundTrip() throws {
        let suiteName = "test.email.validation"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storage = UserDefaultsStorage(defaults: defaults)

        // Unique key per run: the host-app container persists across test runs.
        let key = "winr.com.test.user.\(UUID().uuidString).email"
        defer { try? storage.remove(for: key) }

        // No email stored → no consent
        let initial: String? = try storage.load(String.self, for: key)
        XCTAssertNil(initial)

        // Store email → consent granted
        try storage.save("test@example.com", for: key)
        let stored: String? = try storage.load(String.self, for: key)
        XCTAssertEqual(stored, "test@example.com")
    }
}
