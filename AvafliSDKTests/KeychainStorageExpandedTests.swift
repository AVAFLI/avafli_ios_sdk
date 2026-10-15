import XCTest
@testable import AvafliSDK

final class KeychainStorageExpandedTests: XCTestCase {

    let keychain = KeychainStorage(service: "com.winr.sdk.tests.expanded")

    override func tearDown() {
        keychain.deleteAll()
        super.tearDown()
    }

    // MARK: - Token persistence

    func testTokenPersistsAcrossLoads() {
        keychain.saveToken("persistent-token")
        XCTAssertEqual(keychain.loadToken(), "persistent-token")
        XCTAssertEqual(keychain.loadToken(), "persistent-token") // second load
    }

    // MARK: - Secure deletion

    func testDeleteTokenClearsAuthAndRefreshAndExpiry() {
        keychain.saveToken("auth-token")
        keychain.saveRefreshToken("refresh-token")
        keychain.deleteToken()

        XCTAssertNil(keychain.loadToken())
        XCTAssertNil(keychain.loadRefreshToken())
        XCTAssertTrue(keychain.isTokenExpired())
    }

    func testDeleteTokenDoesNotClearUUID() {
        keychain.saveToken("token")
        keychain.saveUUID("uuid-keep")
        keychain.deleteToken()

        XCTAssertNil(keychain.loadToken())
        XCTAssertEqual(keychain.loadUUID(), "uuid-keep")
    }

    func testDeleteAllClearsUUIDToo() {
        keychain.saveUUID("uuid-clear")
        keychain.deleteAll()
        XCTAssertNil(keychain.loadUUID())
    }

    // MARK: - Overwrite semantics

    func testOverwriteToken() {
        keychain.saveToken("v1")
        keychain.saveToken("v2")
        XCTAssertEqual(keychain.loadToken(), "v2")
    }

    func testOverwriteUUID() {
        keychain.saveUUID("uuid1")
        keychain.saveUUID("uuid2")
        XCTAssertEqual(keychain.loadUUID(), "uuid2")
    }

    // MARK: - Token expiry

    func testFreshTokenNotExpired() {
        keychain.saveToken("fresh")
        XCTAssertFalse(keychain.isTokenExpired())
    }

    func testNoTokenMeansExpired() {
        XCTAssertTrue(keychain.isTokenExpired())
    }

    // MARK: - Empty/nil returns

    func testLoadNonexistentTokenReturnsNil() {
        XCTAssertNil(keychain.loadToken())
    }

    func testLoadNonexistentRefreshReturnsNil() {
        XCTAssertNil(keychain.loadRefreshToken())
    }

    func testLoadNonexistentUUIDReturnsNil() {
        XCTAssertNil(keychain.loadUUID())
    }

    // MARK: - Special characters

    func testTokenWithSpecialCharacters() {
        let token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature+/="
        keychain.saveToken(token)
        XCTAssertEqual(keychain.loadToken(), token)
    }

    func testUUIDFormat() {
        let uuid = "550E8400-E29B-41D4-A716-446655440000"
        keychain.saveUUID(uuid)
        XCTAssertEqual(keychain.loadUUID(), uuid)
    }

    // MARK: - Independent service namespaces

    func testDifferentServicesAreIndependent() {
        let kc1 = KeychainStorage(service: "com.winr.sdk.test.ns1")
        let kc2 = KeychainStorage(service: "com.winr.sdk.test.ns2")
        defer { kc1.deleteAll(); kc2.deleteAll() }

        kc1.saveToken("token-ns1")
        kc2.saveToken("token-ns2")

        XCTAssertEqual(kc1.loadToken(), "token-ns1")
        XCTAssertEqual(kc2.loadToken(), "token-ns2")
    }

    // MARK: - Delete idempotency

    func testDeleteAllTwiceDoesNotCrash() {
        keychain.saveToken("t")
        keychain.deleteAll()
        keychain.deleteAll() // should not crash
        XCTAssertNil(keychain.loadToken())
    }

    func testDeleteTokenOnEmptyDoesNotCrash() {
        keychain.deleteToken() // nothing stored
        XCTAssertNil(keychain.loadToken())
    }
}
