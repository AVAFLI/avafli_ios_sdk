//
//  KeychainStorage.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation
import Security

final class KeychainStorage {
    private let service: String

    init(service: String = "com.winr.sdk") {
        self.service = service
    }

    // MARK: - JWT Token

    func saveToken(_ token: String) {
        save(data: Data(token.utf8), forKey: "winr_auth_token")
        // Derive expiry from the JWT `exp` claim (seconds since epoch). Refresh
        // ~60s early to avoid races at the boundary. Fall back to a conservative
        // 55-minute window only if the token can't be decoded.
        let expiry: Date
        if let exp = JWTDecoder.expiry(from: token) {
            expiry = exp.addingTimeInterval(-60)
        } else {
            Logger.shared.log("Could not decode JWT exp claim; using fallback expiry", level: .error)
            expiry = Date().addingTimeInterval(55 * 60)
        }
        save(data: Data("\(expiry.timeIntervalSince1970)".utf8), forKey: "winr_token_expiry")
    }

    func loadToken() -> String? {
        guard let data = load(forKey: "winr_auth_token") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func isTokenExpired() -> Bool {
        guard let data = load(forKey: "winr_token_expiry"),
              let str = String(data: data, encoding: .utf8),
              let expiry = Double(str) else {
            return true // No expiry stored, treat as expired
        }
        return Date().timeIntervalSince1970 >= expiry
    }

    func saveRefreshToken(_ token: String) {
        save(data: Data(token.utf8), forKey: "winr_refresh_token")
    }

    func loadRefreshToken() -> String? {
        guard let data = load(forKey: "winr_refresh_token") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveUUID(_ uuid: String) {
        save(data: Data(uuid.utf8), forKey: "winr_user_uuid")
    }

    func loadUUID() -> String? {
        guard let data = load(forKey: "winr_user_uuid") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stable per-install guest identity, minted on first use. Survives app
    /// relaunches (Keychain) so a guest's attribution doesn't churn per session;
    /// deliberately NOT synced to iCloud (same protection class as the UUID).
    ///
    /// 3.0.0: NEW mints use the `avafli_guest_` prefix; an id already persisted
    /// by 2.9.x (`winr_guest_…`) is returned untouched — rewriting it would
    /// churn the install's attribution. The storage key itself stays
    /// `winr_guest_id` (persistence keys are frozen for upgrade continuity).
    func loadOrCreateGuestId() -> String {
        if let data = load(forKey: "winr_guest_id"),
           let existing = String(data: data, encoding: .utf8) {
            return existing
        }
        let fresh = "avafli_guest_" + UUID().uuidString.lowercased()
        save(data: Data(fresh.utf8), forKey: "winr_guest_id")
        return fresh
    }

    func deleteToken() {
        delete(forKey: "winr_auth_token")
        delete(forKey: "winr_refresh_token")
        delete(forKey: "winr_token_expiry")
    }

    func deleteAll() {
        delete(forKey: "winr_auth_token")
        delete(forKey: "winr_refresh_token")
        delete(forKey: "winr_token_expiry")
        delete(forKey: "winr_user_uuid")
    }

    // MARK: - Generic Keychain Operations

    private func save(data: Data, forKey key: String) {
        delete(forKey: key) // Remove existing before saving

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.shared.log("Keychain save failed for \(key): \(status)", level: .error)
        }
    }

    private func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - JWT Decoding

/// Minimal JWT decoder. Reads the `exp` claim from the payload so token expiry
/// is driven by the server-issued token rather than a hardcoded local window.
/// This does NOT verify the signature — that is the backend's responsibility on
/// every request; here we only read the (untrusted) expiry to schedule refresh.
enum JWTDecoder {

    /// Returns the `exp` claim as a `Date`, or `nil` if the token is malformed
    /// (not a 3-part `header.payload.signature` JWT) or has no numeric `exp`.
    static func expiry(from token: String) -> Date? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }

        guard let payloadData = base64URLDecode(segments[1]),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        // `exp` is seconds since epoch; tolerate Int or Double encodings.
        let expSeconds: Double
        if let n = json["exp"] as? Double {
            expSeconds = n
        } else if let n = json["exp"] as? Int {
            expSeconds = Double(n)
        } else if let n = json["exp"] as? NSNumber {
            expSeconds = n.doubleValue
        } else {
            return nil
        }

        return Date(timeIntervalSince1970: expSeconds)
    }

    /// Decodes a base64url segment (RFC 7515): `-`→`+`, `_`→`/`, and pad to a
    /// multiple of 4 with `=`.
    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
