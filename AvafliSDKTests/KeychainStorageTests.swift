//
//  KeychainStorageTests.swift
//  AvafliSDKTests
//
//  Created by Ryan Napolitano on 2/18/26.
//

import XCTest
@testable import AvafliSDK

final class KeychainStorageTests: XCTestCase {

    let keychain = KeychainStorage(service: "com.winr.sdk.tests")

    override func tearDown() {
        keychain.deleteAll()
        super.tearDown()
    }

    func testSaveAndLoadToken() {
        keychain.saveToken("test-token-123")
        XCTAssertEqual(keychain.loadToken(), "test-token-123")
    }

    func testSaveAndLoadUUID() {
        keychain.saveUUID("uuid-456")
        XCTAssertEqual(keychain.loadUUID(), "uuid-456")
    }

    func testSaveAndLoadRefreshToken() {
        keychain.saveRefreshToken("refresh-789")
        XCTAssertEqual(keychain.loadRefreshToken(), "refresh-789")
    }

    func testDeleteAllClearsEverything() {
        keychain.saveToken("token")
        keychain.saveRefreshToken("refresh")
        keychain.saveUUID("uuid")
        keychain.deleteAll()
        XCTAssertNil(keychain.loadToken())
        XCTAssertNil(keychain.loadRefreshToken())
        XCTAssertNil(keychain.loadUUID())
    }

    func testTokenExpiryDefaultsToExpired() {
        XCTAssertTrue(keychain.isTokenExpired())
    }

    func testFreshTokenIsNotExpired() {
        keychain.saveToken("fresh-token")
        XCTAssertFalse(keychain.isTokenExpired())
    }
}
