//
//  NetworkClient.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation
import Security

protocol NetworkClient {
    func send<R: APIRequest>(_ request: R) async throws -> R.Response
}

// MARK: - SPKI Hashing

/// ASN.1 DER headers to prepend to raw public key bytes to form a full
/// SubjectPublicKeyInfo (SPKI) structure before hashing. The header encodes
/// the algorithm OID and key-length wrapper that `SecKeyCopyExternalRepresentation`
/// strips away.
enum SPKIHeader {
    // RSA 2048
    static let rsa2048: [UInt8] = [
        0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
    ]

    // RSA 4096
    static let rsa4096: [UInt8] = [
        0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
        0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
    ]

    // EC P-256 (prime256v1 / secp256r1)
    static let ecP256: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00
    ]

    // EC P-384 (secp384r1)
    static let ecP384: [UInt8] = [
        0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
        0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
    ]

    /// Returns the appropriate ASN.1 header for a given `SecKey`, or `nil`
    /// if the key type/size is unsupported.
    static func header(for key: SecKey) -> [UInt8]? {
        guard let attrs = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attrs[kSecAttrKeyType] as? String,
              let keySizeAny = attrs[kSecAttrKeySizeInBits] else { return nil }

        let keySize: Int
        if let n = keySizeAny as? Int {
            keySize = n
        } else if let n = keySizeAny as? NSNumber {
            keySize = n.intValue
        } else {
            return nil
        }

        if keyType == (kSecAttrKeyTypeRSA as String) {
            switch keySize {
            case 2048: return rsa2048
            case 4096: return rsa4096
            default: return nil
            }
        } else if keyType == (kSecAttrKeyTypeECSECPrimeRandom as String) {
            switch keySize {
            case 256: return ecP256
            case 384: return ecP384
            default: return nil
            }
        }
        return nil
    }

    /// Build a full SPKI blob from a `SecKey` by prepending the ASN.1 header
    /// to the raw key bytes returned by `SecKeyCopyExternalRepresentation`.
    static func spkiData(for key: SecKey) -> Data? {
        guard let header = header(for: key),
              let rawKeyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        var spki = Data(header)
        spki.append(rawKeyData)
        return spki
    }

    /// SHA-256 hash of the full SPKI, base64-encoded — the standard pin format.
    static func pin(for key: SecKey) -> String? {
        guard let spki = spkiData(for: key) else { return nil }
        var hash = [UInt8](repeating: 0, count: 32)
        spki.withUnsafeBytes { buf in
            _ = CC_SHA256(buf.baseAddress, CC_LONG(spki.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }
}

// MARK: - Certificate Pinning Delegate

/// Pins TLS connections to Google Cloud Functions / Firebase certificates.
/// Uses SPKI (Subject Public Key Info) pinning against Google Trust Services CAs.
/// Accepts an array of pins to support rotation without SDK updates.
// Internal (not private) so the unit tests can verify the default pin set.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate {

    /// SHA-256 SPKI hashes of Google Trust Services certs serving *.cloudfunctions.net.
    /// Pin the intermediates + roots to survive leaf rotation.
    /// Multiple pins allow seamless rotation — as long as one matches, the
    /// connection is accepted.
    let pinnedKeyHashes: Set<String>

    init(pinnedKeyHashes: [String]? = nil) {
        self.pinnedKeyHashes = Set(pinnedKeyHashes ?? Self.defaultPins)
    }

    static let defaultPins: [String] = [
        // WE2 intermediate – EC P-256 (Google Trust Services)
        "vh78KSg1Ry4NaqGDV10w/cTb9VH3BQUZoCWNa93W/EY=",
        // WR2 intermediate – RSA (Google Trust Services)
        "YPtHaftLw6/0vnc2BnNKGF54xiCA28WFcccjkA4ypCM=",
        // GTS Root R1 – RSA 4096
        "hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPgfaAp63Gc=",
        // GTS Root R2 – RSA 4096
        "Vfd95BwDeSQo+NUYxVEEIlvkOlWY2SalKK1lPhzOx78=",
        // GTS Root R3 – EC P-384
        "QXnt2YHvdHR3tJYmQIr0Paosp6t/nggsEGD4QJZ3Q0g=",
        // GTS Root R4 – EC P-384
        "mEflZT5enoR1FuXLgYYGqnVEoZvmf9c2bVBpiOjYQ0c=",
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            Logger.shared.log("Certificate pinning: trust evaluation failed", level: .error)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if any cert in the chain matches our pinned SPKI hashes
        let certCount = SecTrustGetCertificateCount(serverTrust)
        for i in 0..<certCount {
            if #available(iOS 15.0, *) {
                guard let certChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                      i < certChain.count else { continue }
                let cert = certChain[i]
                if let publicKey = SecCertificateCopyKey(cert),
                   let pin = SPKIHeader.pin(for: publicKey),
                   pinnedKeyHashes.contains(pin) {
                    completionHandler(.useCredential, URLCredential(trust: serverTrust))
                    return
                }
            } else {
                // Fallback for iOS < 15: accept if standard trust evaluation passed
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        Logger.shared.log("Certificate pinning: no matching public key found in chain", level: .error)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

// CommonCrypto bridge
import CommonCrypto

// MARK: - Network Client

final class URLSessionNetworkClient: NetworkClient {
    private let baseURL: URL
    private let apiKey: String
    private let tokenProvider: () -> String?
    private let refreshHandler: (() async -> String?)?
    private let session: URLSession

    /// - Parameters:
    ///   - enablePinning: When `true` (the default), enforces SPKI certificate pinning.
    ///   - pinnedKeyHashes: Optional array of base64-encoded SHA-256 SPKI hashes.
    ///     Supports pin rotation: supply current + backup pins so certificates
    ///     can be rotated server-side without an SDK update. When `nil`, uses
    ///     the built-in Google Trust Services pins.
    init(
        baseURL: URL,
        apiKey: String,
        tokenProvider: @escaping () -> String? = { nil },
        refreshHandler: (() async -> String?)? = nil,
        enablePinning: Bool = true,
        pinnedKeyHashes: [String]? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler

        if enablePinning {
            let delegate = CertificatePinningDelegate(pinnedKeyHashes: pinnedKeyHashes)
            self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession.shared
        }
    }

    func send<R>(_ request: R) async throws -> R.Response where R : APIRequest {
        let result = try await execute(request)

        if case .failure(let error) = result,
           isAuthError(error),
           let refreshHandler = refreshHandler,
           request.path != "registerDevice",
           request.path != "refreshToken" {
            if let _ = await refreshHandler() {
                let retryResult = try await execute(request)
                return try retryResult.get()
            }
        }

        return try result.get()
    }

    private func execute<R>(_ request: R) async throws -> Result<R.Response, Error> where R: APIRequest {
        let url = baseURL.appendingPathComponent(request.path)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue(apiKey, forHTTPHeaderField: "X-API-KEY")

        let hasToken: Bool
        if let token = tokenProvider() {
            urlRequest.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            hasToken = true
        } else if request.path != "registerDevice" && request.path != "refreshToken" {
            Logger.shared.log("[\(request.path)] No token available, returning authenticationRequired", level: .debug)
            return .failure(AvafliError.authenticationRequired)
        } else {
            hasToken = false
        }

        urlRequest.timeoutInterval = 15

        Logger.shared.log("[\(request.path)] → \(request.method) \(url.absoluteString) (hasToken=\(hasToken))", level: .debug)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            Logger.shared.log("[\(request.path)] Network error: \(error)", level: .error)
            throw error
        }

        if let httpResponse = response as? HTTPURLResponse {
            Logger.shared.log("[\(request.path)] ← HTTP \(httpResponse.statusCode) (\(data.count) bytes)", level: .debug)

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                Logger.shared.log("[\(request.path)] Auth error body: \(body)", level: .error)
                // A suspended/revoked publisher surfaces as a `permission-denied`
                // callable error whose message mentions "suspended". Map it to a
                // dedicated case so the SDK can silently degrade rather than treat
                // it as a recoverable auth failure (which would trigger a refresh loop).
                if Self.isSuspendedError(message: body) {
                    return .failure(AvafliError.serviceUnavailable)
                }
                // The geo-fence rejection is a `permission-denied` callable
                // error (HTTP 403) — it is NOT an auth failure, so map it
                // before falling through to authenticationRequired (which
                // would pointlessly burn a token refresh).
                if Self.isGeoBlockedError(message: body) {
                    return .failure(AvafliError.geoBlocked)
                }
                return .failure(AvafliError.authenticationRequired)
            }
            if !(200...299).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
                Logger.shared.log("[\(request.path)] Error body: \(body)", level: .error)
                if let errorBody = try? JSONDecoder().decode(CallableErrorResponse.self, from: data) {
                    if Self.isSuspendedError(message: errorBody.error.message) {
                        return .failure(AvafliError.serviceUnavailable)
                    }
                    if Self.isGeoBlockedError(message: errorBody.error.message) {
                        return .failure(AvafliError.geoBlocked)
                    }
                    return .failure(AvafliError.internalError(errorBody.error.message))
                }
                return .failure(AvafliError.network(
                    NSError(domain: "AvafliAPI", code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                ))
            }
        }

        let wrapper = try JSONDecoder().decode(CallableResponse<R.Response>.self, from: data)
        return .success(wrapper.result)
    }

    private func isAuthError(_ error: Error) -> Bool {
        if case AvafliError.authenticationRequired = error { return true }
        return false
    }

    /// Detects the backend "publisher suspended / API key revoked" error from its
    /// message. The backend emits a `permission-denied` callable error with one of:
    ///   - "API key suspended or revoked"
    ///   - "Publisher account suspended"
    static func isSuspendedError(message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("suspended") || lowered.contains("revoked")
    }

    /// Detects the backend geo-fence rejection from its message. gatekeeper.ts
    /// (`enforceGeoFence`) throws a `permission-denied` callable error with one
    /// of two messages:
    ///   - GEO_UNVERIFIED_MESSAGE: "We couldn't verify your location. This
    ///     promotion is only available in the United States."
    ///   - GEO_NON_US_MESSAGE: "This promotion is only available to users
    ///     located in one of the 50 United States or Washington, D.C."
    /// Both contain "promotion is only available"; the "verify your location"
    /// clause is matched too so the unverified variant survives copy drift.
    static func isGeoBlockedError(message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("promotion is only available")
            || lowered.contains("verify your location")
    }
}

// Firebase callable response wrapper
private struct CallableResponse<T: Decodable>: Decodable {
    let result: T
}

private struct CallableErrorResponse: Decodable {
    let error: CallableErrorDetail
}

private struct CallableErrorDetail: Decodable {
    let message: String
    let status: String?
}
