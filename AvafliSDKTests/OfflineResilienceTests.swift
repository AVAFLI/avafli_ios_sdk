import XCTest
@testable import AvafliSDK

// MARK: - Fakes

/// In-memory Storage fake — no UserDefaults bleed between tests.
private final class MemoryStorage: Storage {
    private var store: [String: Data] = [:]
    private let lock = NSLock()

    func save<T>(_ value: T, for key: String) throws where T: Decodable, T: Encodable {
        let data = try JSONEncoder().encode(value)
        lock.lock(); store[key] = data; lock.unlock()
    }

    func load<T>(_ type: T.Type, for key: String) throws -> T? where T: Decodable, T: Encodable {
        lock.lock(); let data = store[key]; lock.unlock()
        guard let data else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func remove(for key: String) throws {
        lock.lock(); store[key] = nil; lock.unlock()
    }

    var keys: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(store.keys)
    }
}

// MARK: - Classifier

final class NetworkErrorClassifierTests: XCTestCase {

    func testTransportErrorsAreRetriable() {
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(URLError(.timedOut)))
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(URLError(.notConnectedToInternet)))
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(URLError(.networkConnectionLost)))
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(URLError(.cannotConnectToHost)))
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(URLError(.dnsLookupFailed)))
    }

    func testNonTransportURLErrorsAreNotRetriable() {
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(URLError(.cancelled)))
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(URLError(.badURL)))
        // TLS/pinning failures must NEVER auto-retry.
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(URLError(.serverCertificateUntrusted)))
    }

    func testBackendRejectionsAreNotRetriable() {
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(AvafliError.internalError("Already claimed today")))
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(AvafliError.authenticationRequired))
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(AvafliError.geoBlocked))
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(AvafliError.serviceUnavailable))
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(AvafliError.optedOut))
    }

    func testHTTPStatusErrorIsNotRetriableButWrappedTransportIs() {
        // AvafliError.network wrapping an HTTP-status NSError (a real server
        // response, e.g. 404) — a rejection, not a drop.
        let httpError = AvafliError.network(
            NSError(domain: "AvafliAPI", code: 404, userInfo: nil)
        )
        XCTAssertFalse(AvafliNetworkErrorClassifier.isRetriable(httpError))

        // AvafliError.network wrapping a genuine transport failure — retriable.
        let transportError = AvafliError.network(URLError(.timedOut))
        XCTAssertTrue(AvafliNetworkErrorClassifier.isRetriable(transportError))
    }

    func testAlreadyClaimedRejectionDetection() {
        XCTAssertTrue(Avafli.isAlreadyClaimedRejection(AvafliError.internalError("Already claimed daily entries today")))
        XCTAssertTrue(Avafli.isAlreadyClaimedRejection(AvafliError.internalError("Already claimed today")))
        XCTAssertTrue(Avafli.isAlreadyClaimedRejection(
            AvafliError.internalError("You've already entered today on another device. Come back tomorrow to keep your streak going!")
        ))
        XCTAssertFalse(Avafli.isAlreadyClaimedRejection(URLError(.timedOut)))
        XCTAssertFalse(Avafli.isAlreadyClaimedRejection(AvafliError.geoBlocked))
    }
}

// MARK: - Retry coordinator

final class OfflineRetryCoordinatorTests: XCTestCase {

    private var storage: MemoryStorage!

    override func setUp() {
        super.setUp()
        storage = MemoryStorage()
    }

    private func makeCoordinator(
        now: @escaping () -> Date = Date.init,
        backoffDelays: [TimeInterval] = []
    ) -> OfflineRetryCoordinator {
        OfflineRetryCoordinator(
            storage: storage,
            bundleId: "com.test.app",
            now: now,
            backoffDelays: backoffDelays,
            sleeper: { _ in }  // no real sleeping in tests
        )
    }

    // MARK: Persistence

    func testEnqueuePersistsIntentAcrossCoordinatorInstances() {
        let first = makeCoordinator()
        first.enqueue(.claim)
        XCTAssertEqual(first.pendingKinds, [.claim])

        // A brand-new coordinator over the same storage (≈ app relaunch)
        // still sees the pending intent.
        let second = makeCoordinator()
        XCTAssertEqual(second.pendingKinds, [.claim])
    }

    func testStorageKeyUsesWinrNamespace() {
        let coordinator = makeCoordinator()
        coordinator.enqueue(.claim)
        XCTAssertEqual(storage.keys, ["winr.com.test.app.offline.pendingIntents"])
    }

    func testClearRemovesIntent() {
        let coordinator = makeCoordinator()
        coordinator.enqueue(.claim)
        coordinator.enqueue(.registration)
        coordinator.clear(.claim)
        XCTAssertEqual(coordinator.pendingKinds, [.registration])
    }

    func testEnqueueSameKindTwiceKeepsOneIntent() {
        let coordinator = makeCoordinator()
        coordinator.enqueue(.claim)
        coordinator.enqueue(.claim)
        XCTAssertEqual(coordinator.pendingKinds, [.claim])
    }

    // MARK: Same-day guard

    func testIntentFromPreviousLocalDayIsDropped() {
        var currentDate = Date(timeIntervalSince1970: 1_756_600_000) // fixed instant
        let coordinator = makeCoordinator(now: { currentDate })
        coordinator.enqueue(.claim)
        XCTAssertEqual(coordinator.pendingKinds, [.claim])

        // Cross local midnight (+1 day) — the intent must be dropped, not
        // replayed: server-authoritative day windows make a stale-day claim a
        // NEW-day claim, which is the auto-open engine's decision.
        currentDate = currentDate.addingTimeInterval(24 * 60 * 60)
        XCTAssertEqual(coordinator.pendingKinds, [])
        // And the drop is persisted.
        XCTAssertEqual(storage.keys, [])
    }

    func testSameDayIntentSurvives() {
        var currentDate = Date(timeIntervalSince1970: 1_756_600_000)
        let coordinator = makeCoordinator(now: { currentDate })
        coordinator.enqueue(.claim)
        currentDate = currentDate.addingTimeInterval(60) // one minute later
        XCTAssertEqual(coordinator.pendingKinds, [.claim])
    }

    // MARK: Retry outcomes

    func testSuccessClearsIntent() async {
        let coordinator = makeCoordinator()
        coordinator.retryHandler = { _ in .success }
        coordinator.enqueue(.claim)
        coordinator.noteConnectivityRegained()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.pendingKinds, [])
        XCTAssertEqual(coordinator.attemptCount(for: .claim), 1)
    }

    func testPermanentFailureClearsIntent() async {
        let coordinator = makeCoordinator()
        coordinator.retryHandler = { _ in .permanentFailure }
        coordinator.enqueue(.claim)
        coordinator.noteForeground()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.pendingKinds, [])
    }

    func testRetriableFailureKeepsIntent() async {
        let coordinator = makeCoordinator()
        coordinator.retryHandler = { _ in .retriableFailure }
        coordinator.enqueue(.claim)
        coordinator.noteForeground()
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.pendingKinds, [.claim])
    }

    // MARK: Hard caps

    func testAttemptsAreHardCappedPerSession() async {
        let coordinator = makeCoordinator()
        let attemptCounter = AtomicCounter()
        coordinator.retryHandler = { _ in
            attemptCounter.increment()
            return .retriableFailure
        }
        coordinator.enqueue(.claim)

        // Hammer the triggers well past the cap.
        for _ in 0..<20 {
            coordinator.noteConnectivityRegained()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertEqual(attemptCounter.value, OfflineRetryCoordinator.maxAttemptsPerSession)
        XCTAssertEqual(coordinator.attemptCount(for: .claim), OfflineRetryCoordinator.maxAttemptsPerSession)
        // The intent stays persisted for the NEXT session (fresh cap).
        XCTAssertEqual(coordinator.pendingKinds, [.claim])
    }

    func testBackoffScheduleIsFinite() async {
        // With instant sleeps and an always-failing handler, the backoff task
        // must attempt at most once per delay slot and then stop on its own.
        let attemptCounter = AtomicCounter()
        let coordinator = OfflineRetryCoordinator(
            storage: storage,
            bundleId: "com.test.app",
            backoffDelays: [0, 0, 0],
            sleeper: { _ in }
        )
        coordinator.retryHandler = { _ in
            attemptCounter.increment()
            return .retriableFailure
        }
        coordinator.enqueue(.claim)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertLessThanOrEqual(attemptCounter.value, 3)
        XCTAssertEqual(coordinator.pendingKinds, [.claim])
    }

    func testBackoffStopsWhenIntentCleared() async {
        let attemptCounter = AtomicCounter()
        let coordinator = OfflineRetryCoordinator(
            storage: storage,
            bundleId: "com.test.app",
            backoffDelays: [0, 0, 0, 0, 0],
            sleeper: { _ in }
        )
        coordinator.retryHandler = { _ in
            attemptCounter.increment()
            return .success
        }
        coordinator.enqueue(.claim)
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Success on the first slot — the finite schedule bails out early.
        XCTAssertEqual(attemptCounter.value, 1)
        XCTAssertEqual(coordinator.pendingKinds, [])
    }

    func testDayKeyFormat() {
        let key = OfflineRetryCoordinator.dayKey(for: Date(timeIntervalSince1970: 0))
        // Local-timezone yyyy-MM-dd.
        XCTAssertEqual(key.count, 10)
        XCTAssertEqual(key.filter { $0 == "-" }.count, 2)
    }
}

/// Tiny thread-safe counter for concurrency-crossing assertions.
private final class AtomicCounter {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

// MARK: - Buffering analytics adapter

final class BufferingAnalyticsAdapterTests: XCTestCase {

    private var storage: MemoryStorage!
    private var spy: SpyAnalyticsAdapter!
    private var online: Bool = true

    override func setUp() {
        super.setUp()
        storage = MemoryStorage()
        spy = SpyAnalyticsAdapter()
        online = true
    }

    private func makeAdapter(now: @escaping () -> Date = Date.init) -> BufferingAnalyticsAdapter {
        BufferingAnalyticsAdapter(
            wrapping: spy,
            storage: storage,
            bundleId: "com.test.app",
            isOnline: { [weak self] in self?.online ?? true },
            now: now
        )
    }

    func testOnlinePassthrough() {
        let adapter = makeAdapter()
        adapter.track(event: "avafli_experience_opened", properties: ["giveaway_id": "g1"])
        XCTAssertEqual(spy.trackedEvents.count, 1)
        XCTAssertEqual(spy.lastEvent, "avafli_experience_opened")
        XCTAssertEqual(adapter.bufferedCount, 0)
    }

    func testOfflineEventsAreBufferedNotForwarded() {
        online = false
        let adapter = makeAdapter()
        adapter.track(event: "e1", properties: ["a": 1])
        adapter.track(event: "e2", properties: nil)
        XCTAssertEqual(spy.trackedEvents.count, 0)
        XCTAssertEqual(adapter.bufferedCount, 2)
    }

    func testBufferPersistsAcrossAdapterInstances() {
        online = false
        makeAdapter().track(event: "e1", properties: nil)
        // New adapter instance over the same storage (≈ next launch).
        let secondLaunch = makeAdapter()
        XCTAssertEqual(secondLaunch.bufferedCount, 1)
        online = true
        secondLaunch.flush()
        XCTAssertEqual(spy.trackedEvents.count, 1)
        XCTAssertEqual(spy.lastEvent, "e1")
        XCTAssertEqual(secondLaunch.bufferedCount, 0)
    }

    func testFlushPreservesOrderAndOriginalTimestamps() {
        online = false
        let t0 = Date(timeIntervalSince1970: 1_756_600_000)
        var currentDate = t0
        let adapter = makeAdapter(now: { currentDate })

        adapter.track(event: "first", properties: ["n": 1])
        currentDate = t0.addingTimeInterval(60)
        adapter.track(event: "second", properties: ["n": 2])

        online = true
        adapter.flush()

        XCTAssertEqual(spy.trackedEvents.map { $0.event }, ["first", "second"])
        let firstProps = spy.trackedEvents[0].properties
        XCTAssertEqual(firstProps?["n"] as? Int, 1)
        XCTAssertEqual(firstProps?["original_timestamp_ms"] as? Int, Int(t0.timeIntervalSince1970 * 1000))
        XCTAssertNotNil(firstProps?["original_timestamp"] as? String)
        let secondProps = spy.trackedEvents[1].properties
        XCTAssertEqual(secondProps?["original_timestamp_ms"] as? Int, Int(t0.addingTimeInterval(60).timeIntervalSince1970 * 1000))
    }

    func testRingBufferDropsOldestBeyondCapacity() {
        online = false
        let adapter = makeAdapter()
        for i in 0..<(BufferingAnalyticsAdapter.capacity + 25) {
            adapter.track(event: "e\(i)", properties: nil)
        }
        XCTAssertEqual(adapter.bufferedCount, BufferingAnalyticsAdapter.capacity)

        online = true
        adapter.flush()
        XCTAssertEqual(spy.trackedEvents.count, BufferingAnalyticsAdapter.capacity)
        // Oldest 25 dropped; the first surviving event is e25, the last e124.
        XCTAssertEqual(spy.trackedEvents.first?.event, "e25")
        XCTAssertEqual(spy.trackedEvents.last?.event, "e\(BufferingAnalyticsAdapter.capacity + 24)")
    }

    func testLiveEventAfterReconnectFlushesBufferFirst() {
        online = false
        let adapter = makeAdapter()
        adapter.track(event: "buffered", properties: nil)

        online = true
        adapter.track(event: "live", properties: nil)

        // Order preserved: the offline backlog lands before the live event.
        XCTAssertEqual(spy.trackedEvents.map { $0.event }, ["buffered", "live"])
        XCTAssertEqual(adapter.bufferedCount, 0)
    }

    func testNonJSONPropertiesDegradeGracefully() {
        online = false
        let adapter = makeAdapter()
        adapter.track(event: "e", properties: ["when": Date(timeIntervalSince1970: 0)])
        online = true
        adapter.flush()
        XCTAssertEqual(spy.trackedEvents.count, 1)
        // Date isn't JSON-serializable — it degrades to its description.
        XCTAssertNotNil(spy.lastProperties?["when"] as? String)
    }

    func testFlushWithEmptyBufferIsANoOp() {
        let adapter = makeAdapter()
        adapter.flush()
        XCTAssertEqual(spy.trackedEvents.count, 0)
    }
}
