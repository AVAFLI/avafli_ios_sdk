import XCTest
@testable import AvafliSDK

// MARK: - Infrastructure-refusal retry (3.2.1, RESILIENCE_SPEC Oct 15 2026)
//
// Cloud Run refuses overflow traffic with HTTP 429/500 and a PLAIN-TEXT body
// while new instances warm up. The network client retries such refusals on a
// jittered schedule (1/2/4/8 s base, full jitter, 250 ms floor, Retry-After
// honoured up to 10 s) and only then surfaces `.internalError("HTTP n")`.
// Callable JSON errors are answers and are never retried here.

/// Stubs every request the test session makes. Each call pops the next
/// scripted (status, body, headers) — a body of `nil` simulates a transport
/// failure. Once the script is exhausted every further call answers 200.
private final class InfraStubURLProtocol: URLProtocol {
    struct Scripted {
        let status: Int
        let body: Data?
        var headers: [String: String] = [:]
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
        let next = Self.script.isEmpty
            ? Scripted(status: 200, body: InfraRefusalRetryTests.okBody)
            : Self.script.removeFirst()
        Self.lock.unlock()

        guard let body = next.body else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: nil, headerFields: next.headers
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

/// Lock-protected recorder shared between the test and the client's
/// injected sleeper / the logger sink (both fire off the test's thread).
private final class Recorder<Value> {
    private let lock = NSLock()
    private var items: [Value] = []
    func append(_ value: Value) { lock.lock(); items.append(value); lock.unlock() }
    var values: [Value] { lock.lock(); defer { lock.unlock() }; return items }
}

final class InfraRefusalRetryTests: XCTestCase {

    static let okBody = Data(#"{"result":{"ok":true}}"#.utf8)
    private static let noInstanceBody = Data("The request was aborted because there was no available instance.".utf8)
    private static let htmlBody = Data("<html><head><title>503 Service Unavailable</title></head><body>upstream unavailable</body></html>".utf8)
    private static let rateLimitBody = Data(#"{"error":{"message":"Too many requests. Please try again later.","status":"RESOURCE_EXHAUSTED"}}"#.utf8)
    private static let badRequestBody = Data(#"{"error":{"message":"Missing giveawayId","status":"INVALID_ARGUMENT"}}"#.utf8)

    private var sleeps: Recorder<TimeInterval>!
    private var retryLogs: Recorder<String>!
    private var savedLevel: AvafliOptions.LoggingLevel = .error

    override func setUp() {
        super.setUp()
        sleeps = Recorder()
        retryLogs = Recorder()
        savedLevel = Logger.shared.level
        Logger.shared.level = .debug
        let logs = retryLogs!
        Logger.shared.sink = { message, level in
            guard level == .debug, message.contains("Infrastructure refusal"), message.contains("retry") else { return }
            logs.append(message)
        }
    }

    override func tearDown() {
        Logger.shared.sink = nil
        Logger.shared.level = savedLevel
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InfraStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// A client with a live opaque token (keeps the expiry pre-check and the
    /// 401 path out of the way) and a sleeper that records instead of waiting.
    private func makeClient() -> URLSessionNetworkClient {
        let sleeps = self.sleeps!
        return URLSessionNetworkClient(
            baseURL: URL(string: "https://stub.avafli.test")!,
            apiKey: "avafli_test_stub",
            tokenProvider: { "opaque-live-token" },
            refreshHandler: nil,
            session: makeSession(),
            sleeper: { seconds in sleeps.append(seconds) }
        )
    }

    /// Every jittered delay is `random(0, base) + 0.25` for its slot.
    private func assertWithinSchedule(_ delays: [TimeInterval], file: StaticString = #filePath, line: UInt = #line) {
        let floor = URLSessionNetworkClient.infraRetryJitterFloor
        let bases = URLSessionNetworkClient.infraRetryBaseDelays
        XCTAssertLessThanOrEqual(delays.count, bases.count, "never more retries than the schedule has slots", file: file, line: line)
        for (index, delay) in delays.enumerated() {
            XCTAssertGreaterThanOrEqual(delay, floor, "retry \(index + 1) honours the 250 ms floor", file: file, line: line)
            XCTAssertLessThanOrEqual(delay, bases[index] + floor, "retry \(index + 1) stays within its base (\(bases[index]) s) + floor", file: file, line: line)
        }
        let worstCase = bases.prefix(delays.count).reduce(0, +) + floor * Double(delays.count)
        XCTAssertLessThanOrEqual(delays.reduce(0, +), worstCase, "total elapsed within the schedule", file: file, line: line)
    }

    // MARK: 1. 429 + plain-text body → retried, succeeds, caller sees success

    func testPlainText429IsRetriedUntilItSucceeds() async throws {
        InfraStubURLProtocol.reset([
            .init(status: 429, body: Self.noInstanceBody),
            .init(status: 429, body: Self.noInstanceBody),
            .init(status: 429, body: Self.noInstanceBody),
            .init(status: 200, body: Self.okBody),
        ])

        let response = try await makeClient().send(PingRequest())

        XCTAssertTrue(response.ok, "the caller sees the eventual success, never the refusals")
        XCTAssertEqual(InfraStubURLProtocol.recorded().count, 4, "three refusals, then the success")
        XCTAssertEqual(sleeps.values.count, 3)
        assertWithinSchedule(sleeps.values)
        let logs = retryLogs.values
        XCTAssertEqual(logs.count, 3, "one debug line per retry")
        XCTAssertTrue(logs.allSatisfy { $0.contains("HTTP 429") }, "each line names the status: \(logs)")
        XCTAssertTrue(logs[0].contains("retry 1/4") && logs[1].contains("retry 2/4") && logs[2].contains("retry 3/4"), "each line names the attempt: \(logs)")
        XCTAssertTrue(logs.allSatisfy { $0.contains(" in ") && $0.hasSuffix("s") }, "each line names the delay: \(logs)")
    }

    // MARK: 2. 503 + HTML body → same

    func testHTML503IsRetriedUntilItSucceeds() async throws {
        InfraStubURLProtocol.reset([
            .init(status: 503, body: Self.htmlBody),
            .init(status: 503, body: Self.htmlBody),
            .init(status: 503, body: Self.htmlBody),
            .init(status: 200, body: Self.okBody),
        ])

        let response = try await makeClient().send(PingRequest())

        XCTAssertTrue(response.ok)
        XCTAssertEqual(InfraStubURLProtocol.recorded().count, 4)
        XCTAssertEqual(sleeps.values.count, 3)
        assertWithinSchedule(sleeps.values)
        let logs = retryLogs.values
        XCTAssertEqual(logs.count, 3)
        XCTAssertTrue(logs.allSatisfy { $0.contains("HTTP 503") }, "\(logs)")
    }

    // MARK: 3. 429 with a callable body (our own rate limiter) → NOT retried

    func testCallable429IsSurfacedAtOnce() async {
        InfraStubURLProtocol.reset([
            .init(status: 429, body: Self.rateLimitBody),
            .init(status: 200, body: Self.okBody),
        ])

        do {
            _ = try await makeClient().send(PingRequest())
            XCTFail("a callable rate limit is an answer — it must surface")
        } catch AvafliError.internalError(let message) {
            XCTAssertEqual(message, "Too many requests. Please try again later.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(InfraStubURLProtocol.recorded().count, 1, "exactly one request — no retry")
        XCTAssertTrue(sleeps.values.isEmpty, "no pause was taken")
        XCTAssertTrue(retryLogs.values.isEmpty, "nothing was logged as a retry")
    }

    // MARK: 4. 400 callable error → NOT retried

    func testCallable400IsSurfacedAtOnce() async {
        InfraStubURLProtocol.reset([
            .init(status: 400, body: Self.badRequestBody),
            .init(status: 200, body: Self.okBody),
        ])

        do {
            _ = try await makeClient().send(PingRequest())
            XCTFail("a 400 is a rejection — it must surface")
        } catch AvafliError.internalError(let message) {
            XCTAssertEqual(message, "Missing giveawayId")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertEqual(InfraStubURLProtocol.recorded().count, 1)
        XCTAssertTrue(sleeps.values.isEmpty)
        XCTAssertTrue(retryLogs.values.isEmpty)
    }

    // MARK: 5. Exhausted after 4 retries → server-error type, NOT queued offline

    func testExhaustedRefusalSurfacesServerErrorAndIsNotQueuedOffline() async {
        // Five refusals: the first request plus all four retries.
        InfraStubURLProtocol.reset(Array(repeating: .init(status: 503, body: Self.htmlBody), count: 5))

        var surfaced: Error?
        do {
            _ = try await makeClient().send(PingRequest())
            XCTFail("the schedule is bounded — the error must surface")
        } catch {
            surfaced = error
        }

        guard let surfaced else { return }
        guard case AvafliError.internalError(let message) = surfaced else {
            return XCTFail("expected the SDK's server-error type, got \(surfaced)")
        }
        XCTAssertEqual(message, "HTTP 503", "the final error is the existing server-error form")
        XCTAssertEqual(InfraStubURLProtocol.recorded().count, 5, "1 request + 4 retries")
        XCTAssertEqual(sleeps.values.count, 4)
        assertWithinSchedule(sleeps.values)
        XCTAssertEqual(retryLogs.values.count, 4)

        // The offline queue's transport-only classifier refuses it: the server
        // answered (it was just busy), so this is NOT a dropped request.
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(surfaced))

        // And through the real wiring: the SDK's claim-retry hook does not
        // enqueue it, while a genuine transport drop (the positive control) does.
        let resilience = AvafliOfflineResilience.activate(bundleId: "com.avafli.test.infraRefusal")
        defer { AvafliOfflineResilience._resetForTests() }
        resilience.coordinator.clear(.claim)
        resilience.coordinator.clear(.registration)

        Avafli.enqueueOfflineClaimRetry(for: surfaced)
        XCTAssertTrue(resilience.coordinator.pendingKinds.isEmpty, "an exhausted infra refusal is not queued")

        Avafli.enqueueOfflineClaimRetry(for: URLError(.timedOut))
        XCTAssertEqual(resilience.coordinator.pendingKinds, [.claim], "positive control: a transport drop IS queued")
        resilience.coordinator.clear(.claim)
    }

    // MARK: 6. Retry-After: 3 → the first delay is ≈3 s

    func testRetryAfterHeaderDrivesTheFirstDelay() async throws {
        InfraStubURLProtocol.reset([
            .init(status: 429, body: Self.noInstanceBody, headers: ["Retry-After": "3"]),
            .init(status: 200, body: Self.okBody),
        ])

        let response = try await makeClient().send(PingRequest())

        XCTAssertTrue(response.ok)
        XCTAssertEqual(sleeps.values.count, 1)
        XCTAssertEqual(try XCTUnwrap(sleeps.values.first), 3, accuracy: 0.001, "Retry-After replaces the jittered base")
        XCTAssertTrue(retryLogs.values.first?.contains("in 3.00s") == true, "\(retryLogs.values)")

        // Bounds: the header is capped at 10 s and floored at 250 ms; absent
        // (or unusable) it falls back to the jittered schedule.
        XCTAssertEqual(URLSessionNetworkClient.infraRetryDelay(attempt: 0, retryAfter: 60), 10)
        XCTAssertEqual(URLSessionNetworkClient.infraRetryDelay(attempt: 0, retryAfter: 0.01), 0.25)
        XCTAssertEqual(URLSessionNetworkClient.infraRetryDelay(attempt: 0, retryAfter: nil, random: { _ in 0 }), 0.25)
        XCTAssertEqual(URLSessionNetworkClient.infraRetryDelay(attempt: 3, retryAfter: nil, random: { $0 }), 8.25)
        XCTAssertEqual(URLSessionNetworkClient.infraRetryDelay(attempt: 0, retryAfter: 0, random: { _ in 0.5 }), 0.75, "Retry-After: 0 is not a delay — jitter applies")
    }
}
