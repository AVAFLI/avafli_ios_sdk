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

/// Coalesces concurrent callers onto ONE in-flight async operation: the first
/// caller runs it, every caller arriving before it finishes awaits that same
/// result. Used for token refresh — a cold open fires 2–3 parallel authed
/// calls with a dead token → parallel 401s → without this, parallel
/// `refreshToken` calls with the same refresh token.
final class AvafliSingleFlight<Value> {
    private let lock = NSLock()
    private var inFlight: Task<Value, Never>?

    func run(_ operation: @escaping () async -> Value) async -> Value {
        await claim(operation).value
    }

    /// Joins the in-flight task, or starts one. Assigned under the SAME lock
    /// hold as the guard: the task clears the slot under this lock when it
    /// finishes, so it can't null it before the assignment lands.
    private func claim(_ operation: @escaping () async -> Value) -> Task<Value, Never> {
        lock.lock(); defer { lock.unlock() }
        if let inFlight { return inFlight }
        let task = Task<Value, Never> {
            let value = await operation()
            self.land()
            return value
        }
        inFlight = task
        return task
    }

    private func land() {
        lock.lock()
        inFlight = nil
        lock.unlock()
    }
}

final class URLSessionNetworkClient: NetworkClient {
    private let baseURL: URL
    private let apiKey: String
    private let tokenProvider: () -> String?
    private let refreshHandler: (() async -> String?)?
    private let session: URLSession
    /// Per-client single-flight over `refreshHandler` (the SDK-wide one is
    /// `Avafli.tokenRefreshGate`, which every handler routes through).
    private let refreshGate = AvafliSingleFlight<String?>()

    /// A cached token whose JWT `exp` is within this many seconds is treated
    /// as dead and refreshed BEFORE the request instead of eating a
    /// guaranteed 401 (same 60s leeway `KeychainStorage` applies).
    static let expiryLeeway: TimeInterval = 60

    // MARK: Infrastructure-refusal retry (RESILIENCE_SPEC, Oct 15 2026)

    /// When a traffic step outruns warm Cloud Run instances the platform
    /// refuses the overflow with HTTP 429 or 500 and a PLAIN-TEXT body
    /// ("The request was aborted because there was no available instance.");
    /// instances arrive within ~10–30 s. Such a refusal — one of these
    /// statuses AND a body that is not a callable error — is retried with
    /// exponential backoff + full jitter before the host app sees anything.
    /// Callable errors (our own rate limiters, resend cooldowns, geo,
    /// consent, already-claimed) are answers, never retried here.
    static let infraRefusalStatuses: Set<Int> = [429, 500, 502, 503, 504]
    /// Base delays (seconds) — 4 retries, ≈15 s worst case.
    static let infraRetryBaseDelays: [TimeInterval] = [1, 2, 4, 8]
    /// Added to every jittered delay so a retry never fires immediately.
    static let infraRetryJitterFloor: TimeInterval = 0.25
    /// A `Retry-After` header is honoured up to this many seconds.
    static let infraRetryAfterCap: TimeInterval = 10

    /// The pause between infra-refusal retries (injectable for tests).
    private let sleeper: (TimeInterval) async -> Void

    /// `Task.sleep` wrapper. Safe to await from any actor, including the main
    /// actor — it suspends the task, it never blocks a thread.
    static func defaultSleep(_ seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Delay before retry number `attempt` (0-based). A `Retry-After` wins
    /// when present (bounded by the jitter floor and the 10 s cap);
    /// otherwise full jitter over the base: `random(0, base) + floor`.
    static func infraRetryDelay(
        attempt: Int,
        retryAfter: TimeInterval?,
        random: (TimeInterval) -> TimeInterval = { Double.random(in: 0...$0) }
    ) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return max(infraRetryJitterFloor, min(retryAfter, infraRetryAfterCap))
        }
        let base = infraRetryBaseDelays[min(max(attempt, 0), infraRetryBaseDelays.count - 1)]
        return random(base) + infraRetryJitterFloor
    }

    /// `Retry-After` in seconds, when the header is present and numeric.
    /// (The HTTP-date form is ignored — the jittered schedule applies.)
    static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let seconds = TimeInterval(raw), seconds.isFinite else { return nil }
        return seconds
    }

    /// One `execute`'s view of an infrastructure refusal. Never leaves
    /// `executeWithInfraRetry`, which surfaces `.internalError("HTTP n")`
    /// once the schedule is exhausted.
    private struct InfraRefusal: Error {
        let status: Int
        let retryAfter: TimeInterval?
    }

    /// - Parameters:
    ///   - enablePinning: When `true` (the default), enforces SPKI certificate pinning.
    ///   - pinnedKeyHashes: Optional array of base64-encoded SHA-256 SPKI hashes.
    ///     Supports pin rotation: supply current + backup pins so certificates
    ///     can be rotated server-side without an SDK update. When `nil`, uses
    ///     the built-in Google Trust Services pins.
    ///   - session: Test seam — a stubbed `URLSession`. When set, pinning is
    ///     not applied (the session is used as given).
    ///   - sleeper: Test seam — the pause between infrastructure-refusal
    ///     retries. Defaults to a `Task.sleep` wrapper.
    init(
        baseURL: URL,
        apiKey: String,
        tokenProvider: @escaping () -> String? = { nil },
        refreshHandler: (() async -> String?)? = nil,
        enablePinning: Bool = true,
        pinnedKeyHashes: [String]? = nil,
        session: URLSession? = nil,
        sleeper: @escaping (TimeInterval) async -> Void = URLSessionNetworkClient.defaultSleep
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tokenProvider = tokenProvider
        self.refreshHandler = refreshHandler
        self.sleeper = sleeper

        if let session {
            self.session = session
        } else if enablePinning {
            let delegate = CertificatePinningDelegate(pinnedKeyHashes: pinnedKeyHashes)
            self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        } else {
            self.session = URLSession.shared
        }
    }

    func send<R>(_ request: R) async throws -> R.Response where R : APIRequest {
        let authed = request.path != "registerDevice" && request.path != "refreshToken"

        // Proactive expiry pre-check: a token that is already past (or within
        // `expiryLeeway` of) its `exp` is refreshed first — never sent.
        if authed, let refreshHandler, let token = tokenProvider(), Self.isExpiringSoon(token) {
            Logger.shared.log("[\(request.path)] Cached token expired/expiring — refreshing before the request", level: .debug)
            _ = await refreshGate.run(refreshHandler)
        }

        let result = try await executeWithInfraRetry(request)

        if case .failure(let error) = result,
           isAuthError(error),
           let refreshHandler = refreshHandler,
           authed {
            if let _ = await refreshGate.run(refreshHandler) {
                let retryResult = try await executeWithInfraRetry(request)
                return try retryResult.get()
            }
        }

        return try result.get()
    }

    /// `execute` inside the bounded infrastructure-refusal retry: up to
    /// `infraRetryBaseDelays.count` retries on a 429/5xx whose body is not a
    /// callable error, each after a jittered pause (or the server's
    /// `Retry-After`). Everything else — success, callable errors, the 401
    /// path, transport failures (thrown) — passes straight through.
    private func executeWithInfraRetry<R>(_ request: R) async throws -> Result<R.Response, Error> where R: APIRequest {
        let maxRetries = Self.infraRetryBaseDelays.count
        var retries = 0
        while true {
            let result = try await execute(request)
            guard case .failure(let error) = result, let refusal = error as? InfraRefusal else {
                return result
            }
            if retries >= maxRetries {
                Logger.shared.log(
                    "[\(request.path)] Infrastructure refusal HTTP \(refusal.status) — giving up after \(retries) retries",
                    level: .error
                )
                return .failure(AvafliError.internalError("HTTP \(refusal.status)"))
            }
            let delay = Self.infraRetryDelay(attempt: retries, retryAfter: refusal.retryAfter)
            retries += 1
            Logger.shared.log(
                "[\(request.path)] Infrastructure refusal HTTP \(refusal.status) — retry \(retries)/\(maxRetries) in \(String(format: "%.2f", delay))s",
                level: .debug
            )
            await sleeper(delay)
            // A cancelled caller must not keep hammering a busy backend.
            try Task.checkCancellation()
        }
    }

    /// True when the JWT's `exp` is past or within `expiryLeeway`. A token
    /// that can't be decoded is NOT pre-refreshed (the 401 path handles it).
    static func isExpiringSoon(_ token: String, now: Date = Date()) -> Bool {
        guard let expiry = JWTDecoder.expiry(from: token) else { return false }
        return expiry.timeIntervalSince(now) <= expiryLeeway
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
                // A reason-tagged rejection (the claim code's `code_mismatch`
                // is a `permission-denied`) is an ANSWER, not an auth failure.
                // Surfacing it also keeps it off the refresh-and-retry path,
                // which would spend a second try on the same wrong code.
                if request.surfacesCallableErrorDetails,
                   let failure = AvafliCallableFailure(responseBody: data),
                   failure.reason != nil {
                    return .failure(failure)
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
                    if request.surfacesCallableErrorDetails,
                       let failure = AvafliCallableFailure(responseBody: data) {
                        return .failure(failure)
                    }
                    return .failure(AvafliError.internalError(errorBody.error.message))
                }
                // An undecodable non-2xx body (a load balancer's HTML 502, a
                // proxy error page, Cloud Run's plain-text "no available
                // instance" 429/500) is a SERVER outage, not a device
                // connectivity problem — .network here produced "check your
                // connection" for infrastructure failures. 429/5xx is an
                // infrastructure refusal: `executeWithInfraRetry` retries it on
                // the jittered schedule and surfaces internalError("HTTP n")
                // only once exhausted. The offline queue correctly refuses
                // both (transport-only classifier) — the server answered, it
                // was just busy.
                if Self.infraRefusalStatuses.contains(httpResponse.statusCode) {
                    return .failure(InfraRefusal(
                        status: httpResponse.statusCode,
                        retryAfter: Self.retryAfterSeconds(from: httpResponse)
                    ))
                }
                return .failure(AvafliError.internalError("HTTP \(httpResponse.statusCode)"))
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
    /// Machine-readable extras (`HttpsError.details`). Decoded leniently: a
    /// shape this SDK doesn't know must never cost the caller the message.
    let details: CallableErrorDetails?

    private enum CodingKeys: String, CodingKey { case message, status, details }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        details = try? c.decodeIfPresent(CallableErrorDetails.self, forKey: .details)
    }
}

private struct CallableErrorDetails: Decodable {
    let reason: String?
    let retryAfterSeconds: Int?
    let attemptsRemaining: Int?
    let verification: ClaimVerificationBlock?

    private enum CodingKeys: String, CodingKey {
        case reason, retryAfterSeconds, attemptsRemaining, verification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        retryAfterSeconds = Self.wholeNumber(in: c, for: .retryAfterSeconds)
        attemptsRemaining = Self.wholeNumber(in: c, for: .attemptsRemaining)
        verification = try? c.decodeIfPresent(ClaimVerificationBlock.self, forKey: .verification)
    }

    /// JSON numbers arrive as 45 or 45.0 depending on the encoder.
    private static func wholeNumber(in c: KeyedDecodingContainer<CodingKeys>, for key: CodingKeys) -> Int? {
        if let n = try? c.decodeIfPresent(Int.self, forKey: key) { return n }
        if let n = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(n.rounded(.up)) }
        return nil
    }
}

/// A callable rejection with its machine-readable details, for the requests
/// that opt in (`APIRequest.surfacesCallableErrorDetails`). Wire format:
/// `{"error":{"status":"FAILED_PRECONDITION","message":"…","details":{…}}}`.
struct AvafliCallableFailure: Error, CustomStringConvertible {
    /// The callable status, e.g. "FAILED_PRECONDITION", "RESOURCE_EXHAUSTED".
    let status: String?
    let message: String
    /// `details.reason`, e.g. "code_mismatch", "fresh_code_sent".
    let reason: String?
    let retryAfterSeconds: Int?
    let attemptsRemaining: Int?
    let verification: ClaimVerificationBlock?

    init(
        status: String?,
        message: String,
        reason: String? = nil,
        retryAfterSeconds: Int? = nil,
        attemptsRemaining: Int? = nil,
        verification: ClaimVerificationBlock? = nil
    ) {
        self.status = status
        self.message = message
        self.reason = reason
        self.retryAfterSeconds = retryAfterSeconds
        self.attemptsRemaining = attemptsRemaining
        self.verification = verification
    }

    /// nil when the body is not a callable error envelope.
    init?(responseBody data: Data) {
        guard let body = try? JSONDecoder().decode(CallableErrorResponse.self, from: data) else { return nil }
        self.init(
            status: body.error.status,
            message: body.error.message,
            reason: body.error.details?.reason,
            retryAfterSeconds: body.error.details?.retryAfterSeconds,
            attemptsRemaining: body.error.details?.attemptsRemaining,
            verification: body.error.details?.verification
        )
    }

    /// Carries the message, so callers that match on the error's text (the
    /// claim submit's "Already submitted") keep working.
    var description: String { "callableFailure(\(status ?? "UNKNOWN"): \(message))" }
}
