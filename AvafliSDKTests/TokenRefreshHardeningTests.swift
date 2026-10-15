import XCTest
@testable import AvafliSDK

// MARK: - Token-refresh hardening (3.1.4): expiry pre-check + single-flight refresh

/// Stubs every request the test session makes. Each call pops the next
/// scripted (status, body) — a body of `nil` simulates a transport failure.
private final class StubURLProtocol: URLProtocol {
    struct Scripted {
        let status: Int
        let body: Data?
    }

    static let lock = NSLock()
    static var script: [Scripted] = []
    static var seenRequests: [URLRequest] = []

    static func reset(_ script: [Scripted]) {
        lock.lock()
        self.script = script
        seenRequests = []
        lock.unlock()
    }

    static func recorded() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return seenRequests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.seenRequests.append(request)
        let next = Self.script.isEmpty ? Scripted(status: 500, body: Data()) : Self.script.removeFirst()
        Self.lock.unlock()

        guard let body = next.body else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct PingRequest: APIRequest {
    struct Response: Decodable { let ok: Bool }
    var path: String { "getActiveGiveaway" }
    var method: String { "POST" }
    var body: Data? { Data("{}".utf8) }
}

final class TokenRefreshHardeningTests: XCTestCase {

    private static let okBody = Data(#"{"result":{"ok":true}}"#.utf8)
    private static let authFailBody = Data(#"{"error":{"message":"unauthenticated","status":"UNAUTHENTICATED"}}"#.utf8)

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Unsigned JWT with the given `exp` (seconds since epoch) — the decoder
    /// only reads the payload, exactly as `KeychainStorage.saveToken` does.
    private func jwt(exp: TimeInterval) -> String {
        func b64url(_ s: String) -> String {
            Data(s.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return b64url(#"{"alg":"none","typ":"JWT"}"#) + "." + b64url(#"{"exp":\#(Int(exp))}"#) + ".sig"
    }

    private func makeClient(
        token: @escaping () -> String?,
        refresh: (() async -> String?)?
    ) -> URLSessionNetworkClient {
        URLSessionNetworkClient(
            baseURL: URL(string: "https://stub.avafli.test")!,
            apiKey: "avafli_test_stub",
            tokenProvider: token,
            refreshHandler: refresh,
            session: makeSession()
        )
    }

    private func authorizationHeaders() -> [String] {
        StubURLProtocol.recorded().compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    // MARK: 1. Proactive expiry pre-check

    func testIsExpiringSoonHonorsThe60SecondLeeway() {
        let now = Date()
        XCTAssertTrue(URLSessionNetworkClient.isExpiringSoon(jwt(exp: now.timeIntervalSince1970 - 10), now: now), "past exp")
        XCTAssertTrue(URLSessionNetworkClient.isExpiringSoon(jwt(exp: now.timeIntervalSince1970 + 30), now: now), "inside the 60s window")
        XCTAssertFalse(URLSessionNetworkClient.isExpiringSoon(jwt(exp: now.timeIntervalSince1970 + 600), now: now), "10 minutes left")
        XCTAssertFalse(URLSessionNetworkClient.isExpiringSoon("not-a-jwt", now: now), "undecodable → let the 401 path handle it")
    }

    /// A dead cached token is refreshed BEFORE the request: the backend
    /// never sees the expired token and never has to answer a 401.
    func testExpiredTokenIsRefreshedBeforeTheRequest() async throws {
        StubURLProtocol.reset([.init(status: 200, body: Self.okBody)])
        let dead = jwt(exp: Date().timeIntervalSince1970 - 3600)
        let fresh = jwt(exp: Date().timeIntervalSince1970 + 3600)
        var current = dead
        var refreshes = 0
        let client = makeClient(token: { current }, refresh: {
            refreshes += 1
            current = fresh
            return fresh
        })

        let response = try await client.send(PingRequest())

        XCTAssertTrue(response.ok)
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(authorizationHeaders(), ["Bearer \(fresh)"], "only the refreshed token ever hit the wire")
    }

    func testLiveTokenIsNotPreRefreshed() async throws {
        StubURLProtocol.reset([.init(status: 200, body: Self.okBody)])
        let live = jwt(exp: Date().timeIntervalSince1970 + 3600)
        var refreshes = 0
        let client = makeClient(token: { live }, refresh: { refreshes += 1; return live })

        _ = try await client.send(PingRequest())

        XCTAssertEqual(refreshes, 0)
        XCTAssertEqual(authorizationHeaders(), ["Bearer \(live)"])
    }

    /// registerDevice / refreshToken carry no session token and must never
    /// trigger the pre-check (or a refresh loop).
    func testUnauthedPathsSkipThePreCheck() async throws {
        StubURLProtocol.reset([.init(status: 200, body: Data(#"{"result":{"token":"t","refreshToken":"r","expiresIn":1}}"#.utf8))])
        let dead = jwt(exp: Date().timeIntervalSince1970 - 3600)
        var refreshes = 0
        let client = makeClient(token: { dead }, refresh: { refreshes += 1; return nil })

        _ = try await client.send(RefreshTokenRequest(refreshToken: "r"))

        XCTAssertEqual(refreshes, 0)
    }

    // MARK: 2. Single-flight refresh

    /// The primitive: N concurrent callers → exactly one execution, and every
    /// caller receives that one result.
    func testSingleFlightCoalescesConcurrentCallers() async {
        let flight = AvafliSingleFlight<Int>()
        let executions = ManagedAtomic()

        let results = await withTaskGroup(of: Int.self, returning: [Int].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await flight.run {
                        let n = executions.increment()
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        return n
                    }
                }
            }
            var out: [Int] = []
            for await value in group { out.append(value) }
            return out
        }

        XCTAssertEqual(executions.value, 1, "one in-flight operation for eight concurrent callers")
        XCTAssertEqual(Set(results), [1], "every caller got the shared result")
    }

    /// After the flight lands, a later caller runs a NEW operation (the
    /// coalescing is per in-flight window, not forever).
    func testSingleFlightRunsAgainAfterCompletion() async {
        let flight = AvafliSingleFlight<Int>()
        let executions = ManagedAtomic()
        _ = await flight.run { executions.increment() }
        _ = await flight.run { executions.increment() }
        XCTAssertEqual(executions.value, 2)
    }

    /// The cold-open shape: several authed calls in parallel with a dead
    /// token → ONE refresh, then every request retries with the new token.
    func testParallel401sShareOneRefresh() async throws {
        // Three initial requests answer 401, then the three retries answer 200.
        StubURLProtocol.reset([
            .init(status: 401, body: Self.authFailBody),
            .init(status: 401, body: Self.authFailBody),
            .init(status: 401, body: Self.authFailBody),
            .init(status: 200, body: Self.okBody),
            .init(status: 200, body: Self.okBody),
            .init(status: 200, body: Self.okBody),
        ])
        // Undecodable token: the pre-check stays out of the way so this test
        // exercises the 401 path alone.
        var current = "opaque-dead-token"
        let refreshes = ManagedAtomic()
        let client = makeClient(token: { current }, refresh: {
            _ = refreshes.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            current = "opaque-fresh-token"
            return current
        })

        let okCount = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<3 {
                group.addTask { (try? await client.send(PingRequest()))?.ok == true }
            }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }

        XCTAssertEqual(okCount, 3, "every caller recovered")
        XCTAssertEqual(refreshes.value, 1, "three parallel 401s must produce exactly one refreshToken call")
        XCTAssertEqual(StubURLProtocol.recorded().count, 6)
    }

    /// Same shape through the pre-check: three parallel calls with an EXPIRED
    /// decodable token refresh once, up front, and none of them ever 401s.
    func testParallelExpiredTokensRefreshOnceBeforeSending() async throws {
        StubURLProtocol.reset([
            .init(status: 200, body: Self.okBody),
            .init(status: 200, body: Self.okBody),
            .init(status: 200, body: Self.okBody),
        ])
        let dead = jwt(exp: Date().timeIntervalSince1970 - 3600)
        let fresh = jwt(exp: Date().timeIntervalSince1970 + 3600)
        var current = dead
        let refreshes = ManagedAtomic()
        let client = makeClient(token: { current }, refresh: {
            _ = refreshes.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            current = fresh
            return fresh
        })

        let okCount = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<3 {
                group.addTask { (try? await client.send(PingRequest()))?.ok == true }
            }
            var count = 0
            for await ok in group where ok { count += 1 }
            return count
        }

        XCTAssertEqual(okCount, 3)
        XCTAssertEqual(refreshes.value, 1)
        XCTAssertEqual(Set(authorizationHeaders()), ["Bearer \(fresh)"], "the dead token never reached the wire")
    }

    /// The SDK-wide gate exists and coalesces too — every refresh handler the
    /// SDK builds (boot client and the experience's own client) routes
    /// through it.
    func testSDKWideRefreshGateCoalesces() async {
        let executions = ManagedAtomic()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    _ = await Avafli.tokenRefreshGate.run {
                        _ = executions.increment()
                        try? await Task.sleep(nanoseconds: 30_000_000)
                        return "shared"
                    }
                }
            }
        }
        XCTAssertEqual(executions.value, 1)
    }
}

/// Tiny lock-guarded counter for the concurrency tests.
private final class ManagedAtomic {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    @discardableResult
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
