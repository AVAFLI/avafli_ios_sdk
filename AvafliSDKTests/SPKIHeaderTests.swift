//
//  SPKIHeaderTests.swift
//  AvafliSDKTests
//
//  Tests for ASN.1 SPKI header prepending logic used in certificate pinning.
//

import XCTest
import Security
import CommonCrypto
@testable import AvafliSDK

final class SPKIHeaderTests: XCTestCase {

    // MARK: - ASN.1 Header Selection

    func testRSA2048HeaderLength() {
        // RSA 2048 SPKI header is 24 bytes
        XCTAssertEqual(SPKIHeader.rsa2048.count, 24)
    }

    func testRSA4096HeaderLength() {
        // RSA 4096 SPKI header is 24 bytes (same prefix structure, different length fields)
        XCTAssertEqual(SPKIHeader.rsa4096.count, 24)
    }

    func testECP256HeaderLength() {
        // EC P-256 SPKI header is 26 bytes
        XCTAssertEqual(SPKIHeader.ecP256.count, 26)
    }

    func testECP384HeaderLength() {
        // EC P-384 SPKI header is 23 bytes
        XCTAssertEqual(SPKIHeader.ecP384.count, 23)
    }

    // MARK: - Header starts with SEQUENCE tag

    func testAllHeadersStartWithSequenceTag() {
        XCTAssertEqual(SPKIHeader.rsa2048[0], 0x30, "RSA 2048 header should start with SEQUENCE tag")
        XCTAssertEqual(SPKIHeader.rsa4096[0], 0x30, "RSA 4096 header should start with SEQUENCE tag")
        XCTAssertEqual(SPKIHeader.ecP256[0], 0x30, "EC P-256 header should start with SEQUENCE tag")
        XCTAssertEqual(SPKIHeader.ecP384[0], 0x30, "EC P-384 header should start with SEQUENCE tag")
    }

    // MARK: - RSA headers contain RSA OID

    func testRSAHeadersContainRSAOID() {
        // RSA OID: 1.2.840.113549.1.1.1 → 0x2a 0x86 0x48 0x86 0xf7 0x0d 0x01 0x01 0x01
        let rsaOID: [UInt8] = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
        XCTAssertTrue(containsSubsequence(SPKIHeader.rsa2048, rsaOID), "RSA 2048 header must contain RSA OID")
        XCTAssertTrue(containsSubsequence(SPKIHeader.rsa4096, rsaOID), "RSA 4096 header must contain RSA OID")
    }

    // MARK: - EC headers contain EC OID

    func testECHeadersContainECOID() {
        // EC public key OID: 1.2.840.10045.2.1 → 0x2a 0x86 0x48 0xce 0x3d 0x02 0x01
        let ecOID: [UInt8] = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]
        XCTAssertTrue(containsSubsequence(SPKIHeader.ecP256, ecOID), "EC P-256 header must contain EC OID")
        XCTAssertTrue(containsSubsequence(SPKIHeader.ecP384, ecOID), "EC P-384 header must contain EC OID")
    }

    // MARK: - EC P-256 header contains P-256 curve OID

    func testECP256HeaderContainsCurveOID() {
        // P-256 curve OID: 1.2.840.10045.3.1.7 → 0x2a 0x86 0x48 0xce 0x3d 0x03 0x01 0x07
        let p256OID: [UInt8] = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
        XCTAssertTrue(containsSubsequence(SPKIHeader.ecP256, p256OID))
    }

    // MARK: - EC P-384 header contains P-384 curve OID

    func testECP384HeaderContainsCurveOID() {
        // P-384 curve OID: 1.3.132.0.34 → 0x2b 0x81 0x04 0x00 0x22
        let p384OID: [UInt8] = [0x2b, 0x81, 0x04, 0x00, 0x22]
        XCTAssertTrue(containsSubsequence(SPKIHeader.ecP384, p384OID))
    }

    // MARK: - Pin computation with known test vectors

    func testSPKIPinForECP256Key() throws {
        // Generate an EC P-256 key and verify the pin includes the header
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw XCTSkip("Could not generate EC P-256 key pair")
        }

        // Compute pin via our code
        let pin = SPKIHeader.pin(for: publicKey)
        XCTAssertNotNil(pin, "Should produce a pin for EC P-256 key")

        // Verify manually: header + raw key → SHA-256 → base64
        let rawKey = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var spki = Data(SPKIHeader.ecP256)
        spki.append(rawKey)
        var hash = [UInt8](repeating: 0, count: 32)
        spki.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(spki.count), &hash) }
        let expectedPin = Data(hash).base64EncodedString()

        XCTAssertEqual(pin, expectedPin)
    }

    func testSPKIPinForRSA2048Key() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw XCTSkip("Could not generate RSA 2048 key pair")
        }

        let pin = SPKIHeader.pin(for: publicKey)
        XCTAssertNotNil(pin, "Should produce a pin for RSA 2048 key")

        // Verify manually
        let rawKey = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var spki = Data(SPKIHeader.rsa2048)
        spki.append(rawKey)
        var hash = [UInt8](repeating: 0, count: 32)
        spki.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(spki.count), &hash) }
        let expectedPin = Data(hash).base64EncodedString()

        XCTAssertEqual(pin, expectedPin)
    }

    func testSPKIDataIncludesHeaderPrefix() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw XCTSkip("Could not generate key")
        }

        let spki = SPKIHeader.spkiData(for: publicKey)
        XCTAssertNotNil(spki)
        // SPKI data must start with the EC P-256 header bytes
        let headerData = Data(SPKIHeader.ecP256)
        XCTAssertEqual(spki!.prefix(headerData.count), headerData)
    }

    // MARK: - Pin without header differs from pin with header

    func testRawKeyHashDiffersFromSPKIPin() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw XCTSkip("Could not generate key")
        }

        // Hash raw key (the old buggy way)
        let rawKey = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var rawHash = [UInt8](repeating: 0, count: 32)
        rawKey.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(rawKey.count), &rawHash) }
        let rawPin = Data(rawHash).base64EncodedString()

        // Hash with SPKI header (the correct way)
        let correctPin = SPKIHeader.pin(for: publicKey)!

        XCTAssertNotEqual(rawPin, correctPin,
            "Raw key hash must differ from SPKI pin — this was the original bug")
    }

    // MARK: - Default pins array is non-empty

    func testDefaultPinsArePresent() {
        XCTAssertGreaterThanOrEqual(CertificatePinningDelegate.defaultPins.count, 3,
            "Should have at least 3 default pins for rotation support")
    }

    // MARK: - Helpers

    private func containsSubsequence(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<i+needle.count]) == needle { return true }
        }
        return false
    }
}
