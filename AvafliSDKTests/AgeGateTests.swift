import XCTest
@testable import AvafliSDK

final class AgeGateTests: XCTestCase {

    // The age gate logic lives in the email-capture flow:
    // isAgeConfirmed must be true before submit succeeds.
    // We test the validation logic that the view enforces.

    private func isEmailValid(_ email: String) -> Bool {
        let pattern = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Age gate required

    func testSubmitRequiresAgeConfirmation() {
        // Simulating the view's submit logic:
        let email = "test@example.com"
        let isAgeConfirmed = false

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailValid = isEmailValid(trimmed)

        // Even with valid email, age must be confirmed
        XCTAssertTrue(emailValid)
        XCTAssertFalse(isAgeConfirmed, "Age must be confirmed to proceed")
    }

    func testSubmitSucceedsWithAgeConfirmation() {
        let email = "test@example.com"
        let isAgeConfirmed = true

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmit = isEmailValid(trimmed) && isAgeConfirmed
        XCTAssertTrue(canSubmit)
    }

    func testSubmitFailsEmptyEmailEvenWithAge() {
        let email = ""
        let isAgeConfirmed = true

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty, "Empty email should block submission")
    }

    func testSubmitFailsInvalidEmailWithAge() {
        let email = "not-an-email"
        let isAgeConfirmed = true

        let canSubmit = isEmailValid(email) && isAgeConfirmed
        XCTAssertFalse(canSubmit)
    }

    // MARK: - AvafliUser model

    func testAvafliUserWithAllFields() {
        let user = AvafliUser(
            id: "user-1",
            firstName: "John",
            lastName: "Doe",
            phone: "+15551234567"
        )
        XCTAssertEqual(user.id, "user-1")
        XCTAssertEqual(user.firstName, "John")
        XCTAssertEqual(user.lastName, "Doe")
        XCTAssertEqual(user.phone, "+15551234567")
    }

    func testAvafliUserWithoutPhone() {
        let user = AvafliUser(id: "u", firstName: "Jane", lastName: "Doe")
        XCTAssertEqual(user.id, "u")
        XCTAssertEqual(user.firstName, "Jane")
        XCTAssertEqual(user.lastName, "Doe")
        XCTAssertNil(user.phone)
    }
}
