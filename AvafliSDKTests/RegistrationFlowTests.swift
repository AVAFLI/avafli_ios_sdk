import XCTest
@testable import AvafliSDK

// MARK: - Mock Network Client

final class MockNetworkClient: NetworkClient {
    var responses: [String: Any] = [:]
    var sentRequests: [String] = []
    var errorToThrow: Error?

    func send<R: APIRequest>(_ request: R) async throws -> R.Response {
        sentRequests.append(request.path)
        if let error = errorToThrow {
            throw error
        }
        guard let response = responses[request.path] as? R.Response else {
            throw AvafliError.internalError("No mock response for \(request.path)")
        }
        return response
    }
}

// MARK: - Mock Storage

final class MockStorage: Storage {
    var store: [String: Data] = [:]

    func save<T: Codable>(_ value: T, for key: String) throws {
        store[key] = try JSONEncoder().encode(value)
    }

    func load<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = store[key] else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func remove(for key: String) throws {
        store.removeValue(forKey: key)
    }
}

// MARK: - Registration Flow Tests

final class RegistrationFlowTests: XCTestCase {

    // MARK: - RegisterDeviceRequest encoding

    func testRegisterDeviceRequestPath() {
        let request = RegisterDeviceRequest(
            apiKey: "pk_test_123",
            deviceFingerprint: "AAAA-BBBB",
            bundleId: "com.test.app",
            timezone: "America/New_York",
            platformOS: "iOS",
            sdkVersion: "1.0.0"
        )
        XCTAssertEqual(request.path, "registerDevice")
        XCTAssertEqual(request.method, "POST")
    }

    func testRegisterDeviceRequestBodyContainsAllFields() throws {
        let request = RegisterDeviceRequest(
            apiKey: "pk_test_123",
            deviceFingerprint: "AAAA-BBBB",
            bundleId: "com.test.app",
            timezone: "America/New_York",
            platformOS: "iOS",
            sdkVersion: "1.0.0"
        )
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: String]
        XCTAssertEqual(data?["apiKey"], "pk_test_123")
        XCTAssertEqual(data?["deviceFingerprint"], "AAAA-BBBB")
        XCTAssertEqual(data?["bundleId"], "com.test.app")
        XCTAssertEqual(data?["timezone"], "America/New_York")
        XCTAssertEqual(data?["platformOS"], "iOS")
        XCTAssertEqual(data?["sdkVersion"], "1.0.0")
    }

    // MARK: - RegisterDeviceResponse parsing

    func testRegisterDeviceResponseDecoding() throws {
        let json = """
        {
            "token": "jwt_abc123",
            "refreshToken": "rt_xyz789",
            "uuid": "user-uuid-001",
            "giveaway": {
                "id": "camp_1",
                "title": "Win $1000",
                "prizeDescription": "Cash prize",
                "prizeValue": 1000.0,
                "streakLadder": [10, 30, 60, 130, 240, 300],
                "doublingEnabled": true,
                "maxDailyBaseEntries": 300,
                "rulesUrl": "https://example.com/rules",
                "startDate": "2026-01-01",
                "endDate": "2026-12-31",
                "streakConfig": {
                    "weeklyResetDay": 0,
                    "monthlyResetDay": 1,
                    "weeklyBonusThreshold": 5,
                    "weeklyBonusEntries": 100,
                    "monthlyBonusThreshold": 20,
                    "monthlyBonusEntries": 500
                }
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertEqual(response.token, "jwt_abc123")
        XCTAssertEqual(response.refreshToken, "rt_xyz789")
        XCTAssertEqual(response.uuid, "user-uuid-001")
        XCTAssertEqual(response.giveaway?.id, "camp_1")
        XCTAssertEqual(response.giveaway?.streakLadder, [10, 30, 60, 130, 240, 300])
        XCTAssertEqual(response.giveaway?.doublingEnabled, true)
    }

    func testRegisterDeviceResponseWithoutGiveaway() throws {
        let json = """
        {
            "token": "jwt_abc",
            "refreshToken": "rt_xyz",
            "uuid": "user-001",
            "giveaway": null
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertNil(response.giveaway)
    }

    // MARK: - Token stored after registration

    func testTokensStoredInKeychainAfterRegistration() {
        let keychain = KeychainStorage(service: "com.winr.sdk.test.reg")
        defer { keychain.deleteAll() }

        keychain.saveToken("jwt_token_123")
        keychain.saveRefreshToken("rt_token_456")
        keychain.saveUUID("uuid_789")

        XCTAssertEqual(keychain.loadToken(), "jwt_token_123")
        XCTAssertEqual(keychain.loadRefreshToken(), "rt_token_456")
        XCTAssertEqual(keychain.loadUUID(), "uuid_789")
    }

    // MARK: - Submit Email Request

    func testSubmitEmailRequestEncoding() throws {
        let request = SubmitEmailRequest(email: "test@example.com", ageConfirmed: true, marketingConsent: true)
        XCTAssertEqual(request.path, "submitEmail")
        XCTAssertEqual(request.method, "POST")
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["email"] as? String, "test@example.com")
        XCTAssertEqual(data?["ageConfirmed"] as? Bool, true)
        XCTAssertEqual(data?["marketingConsent"] as? Bool, true)
        XCTAssertNil(data?["emailConsent"], "The wire field is marketingConsent; the old name must not be sent")
    }

    /// A user who unticks the marketing box still submits — the value just rides
    /// along as false. It governs marketing only; entry and winner contact are
    /// unaffected, which is why the CTA never consulted it.
    func testSubmitEmailRequestEncodesDeclinedMarketingConsent() throws {
        let request = SubmitEmailRequest(email: "test@example.com", ageConfirmed: true, marketingConsent: false)
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["marketingConsent"] as? Bool, false)
        XCTAssertEqual(data?["ageConfirmed"] as? Bool, true)
    }

    func testSubmitEmailResponseDecoding() throws {
        let json = """
        {"success": true}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubmitEmailResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertNil(response.adopted)
    }

    func testSubmitEmailResponseDecodingAdoptedIdentity() throws {
        // Cross-device adoption: backend hands back the canonical user's credentials.
        let json = """
        {
            "success": true,
            "adopted": true,
            "uuid": "canonical-uuid",
            "token": "canonical-jwt",
            "refreshToken": "canonical-rt"
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SubmitEmailResponse.self, from: json)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.adopted, true)
        XCTAssertEqual(response.uuid, "canonical-uuid")
        XCTAssertEqual(response.token, "canonical-jwt")
        XCTAssertEqual(response.refreshToken, "canonical-rt")
    }

    // MARK: - Submit User Profile Request

    func testSubmitUserProfileRequestEncoding() throws {
        let request = SubmitUserProfileRequest(
            firstName: "John",
            lastName: "Doe",
            phone: "+15551234567",
            smsConsent: true,
            // The SDK no longer collects advertising identifiers; the wire field
            // stays optional-absent for a future opt-in attribution feature.
            maidId: nil,
            publisherUserId: "pub-user-9"
        )
        XCTAssertEqual(request.path, "submitUserProfile")
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertEqual(data?["firstName"] as? String, "John")
        XCTAssertEqual(data?["lastName"] as? String, "Doe")
        XCTAssertEqual(data?["phone"] as? String, "+15551234567")
        XCTAssertEqual(data?["smsConsent"] as? Bool, true)
        XCTAssertNil(data?["maidId"])
        XCTAssertEqual(data?["publisherUserId"] as? String, "pub-user-9")
    }

    func testSubmitUserProfileOmitsNilFields() throws {
        let request = SubmitUserProfileRequest(
            firstName: nil,
            lastName: nil,
            phone: nil,
            smsConsent: false,
            maidId: nil,
            publisherUserId: nil
        )
        let body = try XCTUnwrap(request.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let data = json?["data"] as? [String: Any]
        XCTAssertNil(data?["firstName"])
        XCTAssertNil(data?["lastName"])
        XCTAssertNil(data?["phone"])
        XCTAssertNil(data?["maidId"])
        XCTAssertNil(data?["publisherUserId"])
        XCTAssertEqual(data?["smsConsent"] as? Bool, false)
    }
}
