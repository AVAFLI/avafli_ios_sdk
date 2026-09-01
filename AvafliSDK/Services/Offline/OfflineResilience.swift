//
//  OfflineResilience.swift
//  AvafliSDK
//
//  Offline resilience (launch item 15): transient network drops must not cause
//  lost streaks or distorted DAU. Scope is deliberately SAME-DAY only — a
//  pending intent is dropped when its local calendar day ends. Cross-midnight
//  backdated replay is explicitly out of scope: the backend's day windows are
//  server-authoritative (a governed anti-fraud contract; see claimDailyEntries
//  in the backend — dedup + streak math key off `todayDateString(userTz)` /
//  `current_entry_date`), so a client replaying yesterday's claim after
//  midnight would simply be re-windowed into the new day. Whether the NEW
//  day's claim happens is the auto-open engine's decision, not a stale
//  queue's.
//
//  Duplicate-retry safety (verified against the backend claim transaction):
//  claimDailyEntries dedups server-side by the canonical user's local-day
//  entry window and `daily_last_claimed === today`, throwing an
//  `already-exists` callable error ("Already claimed…" / "You've already
//  entered today…"). A duplicate retry therefore can never double-grant;
//  an already-claimed rejection is treated as SUCCESS here.
//

import Foundation
import Network

// MARK: - Network error classification

/// Splits NETWORK-class failures (the request never completed: offline,
/// timeout, connection dropped) from backend rejections (4xx callable errors,
/// auth failures, geo-fence, consent…). Only the former are safe to retry
/// automatically — a rejection would just be rejected again.
enum AvafliNetworkErrorClassifier {

    static func isRetriable(_ error: Error) -> Bool {
        // AvafliError.network wraps either a transport error (retriable) or an
        // HTTP-status NSError minted in NetworkClient (domain "AvafliAPI" —
        // an actual server response, NOT retriable).
        if case AvafliError.network(let inner) = error {
            return isRetriable(inner)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut,
                 .notConnectedToInternet,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .dataNotAllowed,
                 .internationalRoamingOff:
                return true
            default:
                // .cancelled, .badURL, TLS/pinning failures… — not transient
                // connectivity; retrying can't help (and MUST not, for pinning).
                return false
            }
        }
        return false
    }
}

// MARK: - Pending intent

/// A registration or claim the user meant to happen but the network dropped.
struct AvafliPendingIntent: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case registration
        case claim
    }

    let kind: Kind
    /// Local calendar day (yyyy-MM-dd, device timezone) the intent was created.
    /// The same-day guard drops the intent once this day ends.
    let dayKey: String
    let createdAt: Date
}

/// Result of one retry attempt, as reported by the retry handler.
enum AvafliRetryOutcome {
    /// The call succeeded — or the server said "already claimed", which the
    /// idempotent backend dedup makes equivalent to success.
    case success
    /// A backend rejection (4xx-class). Retrying would only repeat it — drop.
    case permanentFailure
    /// Another transport failure — keep the intent for a later trigger.
    case retriableFailure
}

// MARK: - Connectivity monitoring

protocol ConnectivityMonitoring: AnyObject {
    /// Fired on an unsatisfied → satisfied transition.
    var onConnectivityRegained: (() -> Void)? { get set }
    /// Best-effort current state. `true` until the platform reports otherwise
    /// (assume-online default keeps analytics passthrough unbuffered when the
    /// path state isn't known yet).
    var isOnline: Bool { get }
    func start()
    func stop()
}

/// NWPathMonitor-backed connectivity listener.
final class NWPathConnectivityMonitor: ConnectivityMonitoring {
    var onConnectivityRegained: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.avafli.sdk.connectivity")
    private let lock = NSLock()
    private var lastSatisfied: Bool?
    private var started = false

    var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return lastSatisfied ?? true
    }

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            self.lock.lock()
            let previous = self.lastSatisfied
            self.lastSatisfied = satisfied
            self.lock.unlock()
            // Only a genuine offline → online transition triggers retries;
            // the initial path report (previous == nil) does not.
            if satisfied, previous == false {
                self.onConnectivityRegained?()
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

// MARK: - Retry coordinator

/// Persists pending register/claim intents and retries them on connectivity
/// regain, app foreground, and a capped exponential backoff while the app
/// runs. HARD caps everywhere: at most `maxAttemptsPerSession` attempts per
/// intent kind per process lifetime, and the backoff task runs a finite
/// schedule then exits — nothing unbounded, and the task ends early the
/// moment the queue is empty.
final class OfflineRetryCoordinator {

    static let maxAttemptsPerSession = 5
    /// Finite backoff schedule (seconds). 5 slots — the session attempt cap.
    static let defaultBackoffDelays: [TimeInterval] = [2, 4, 8, 16, 32]

    private let storage: Storage
    private let storageKey: String
    private let now: () -> Date
    private let backoffDelays: [TimeInterval]
    private let sleeper: (TimeInterval) async -> Void

    /// Performs the actual retry for a kind. Set once at wiring time.
    var retryHandler: ((AvafliPendingIntent.Kind) async -> AvafliRetryOutcome)?

    private let lock = NSLock()
    private var attemptsThisSession: [AvafliPendingIntent.Kind: Int] = [:]
    private var backoffTask: Task<Void, Never>?
    private var passTask: Task<Void, Never>?

    init(
        storage: Storage,
        bundleId: String,
        now: @escaping () -> Date = Date.init,
        backoffDelays: [TimeInterval] = OfflineRetryCoordinator.defaultBackoffDelays,
        sleeper: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.storage = storage
        // Same `winr.` namespace as the rest of the SDK's persisted state
        // (wire/storage compat is intentionally pre-rebrand).
        self.storageKey = "winr.\(bundleId).offline.pendingIntents"
        self.now = now
        self.backoffDelays = backoffDelays
        self.sleeper = sleeper
    }

    // MARK: Queue

    /// Records a pending intent (one per kind — re-enqueueing refreshes the
    /// day key) and arms the in-session backoff retry task.
    func enqueue(_ kind: AvafliPendingIntent.Kind) {
        lock.lock()
        var intents = loadIntentsLocked()
        intents.removeAll { $0.kind == kind }
        intents.append(AvafliPendingIntent(kind: kind, dayKey: Self.dayKey(for: now()), createdAt: now()))
        saveIntentsLocked(intents)
        lock.unlock()
        Logger.shared.log("Offline retry queued: \(kind.rawValue)", level: .info)
        scheduleBackoffIfNeeded()
    }

    func clear(_ kind: AvafliPendingIntent.Kind) {
        lock.lock()
        var intents = loadIntentsLocked()
        intents.removeAll { $0.kind == kind }
        saveIntentsLocked(intents)
        lock.unlock()
    }

    /// Currently pending kinds, after the same-day guard has pruned stale ones.
    var pendingKinds: [AvafliPendingIntent.Kind] {
        lock.lock(); defer { lock.unlock() }
        return pruneLocked().map { $0.kind }
    }

    // MARK: Triggers

    /// Connectivity regained (platform reachability) — retry immediately.
    func noteConnectivityRegained() {
        attemptNow()
    }

    /// App came to the foreground — retry immediately.
    func noteForeground() {
        attemptNow()
    }

    /// App launch — prune stale intents, then retry whatever survived.
    func noteLaunch() {
        attemptNow()
    }

    // MARK: Internals

    private func attemptNow() {
        lock.lock()
        let hasPending = !pruneLocked().isEmpty
        guard hasPending, passTask == nil else {
            lock.unlock()
            return
        }
        // Assign under the SAME lock hold as the guard: the task's completion
        // block needs this lock to clear `passTask`, so it cannot null it
        // before the assignment lands (that race left a stale non-nil task
        // that blocked every later retry in the session).
        passTask = Task { [weak self] in
            await self?.performPass()
            self?.lock.lock()
            self?.passTask = nil
            self?.lock.unlock()
        }
        lock.unlock()
    }

    /// One retry pass over the pending kinds. Every attempt counts toward the
    /// hard per-session cap regardless of which trigger fired it.
    private func performPass() async {
        guard let handler = retryHandler else { return }

        for kind in pendingKinds {
            lock.lock()
            let attempts = attemptsThisSession[kind] ?? 0
            guard attempts < Self.maxAttemptsPerSession else {
                lock.unlock()
                continue
            }
            attemptsThisSession[kind] = attempts + 1
            lock.unlock()

            let outcome = await handler(kind)
            switch outcome {
            case .success:
                Logger.shared.log("Offline retry succeeded: \(kind.rawValue)", level: .info)
                clear(kind)
            case .permanentFailure:
                Logger.shared.log("Offline retry permanently rejected: \(kind.rawValue) — dropping", level: .info)
                clear(kind)
            case .retriableFailure:
                Logger.shared.log("Offline retry still failing: \(kind.rawValue)", level: .debug)
            }
        }
    }

    /// Arms the capped exponential-backoff retry task. The schedule is finite
    /// (5 slots, ~62s total) and the task exits the moment the queue empties
    /// or the session cap is reached — never an unbounded watcher.
    private func scheduleBackoffIfNeeded() {
        lock.lock()
        guard backoffTask == nil else { lock.unlock(); return }
        let delays = backoffDelays
        // Assign under the SAME lock hold as the guard (same stale-task race
        // as `attemptNow`: with instant sleeps the task could clear
        // `backoffTask` before the assignment landed).
        backoffTask = Task { [weak self] in
            for delay in delays {
                guard let self, !Task.isCancelled else { return }
                await self.sleeper(delay)
                guard !Task.isCancelled else { break }
                if self.pendingKinds.isEmpty { break }
                if self.allKindsCapped() { break }
                await self.performPass()
            }
            self?.lock.lock()
            self?.backoffTask = nil
            self?.lock.unlock()
        }
        lock.unlock()
    }

    private func allKindsCapped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return AvafliPendingIntent.Kind.allCases.allSatisfy {
            (attemptsThisSession[$0] ?? 0) >= Self.maxAttemptsPerSession
        }
    }

    func attemptCount(for kind: AvafliPendingIntent.Kind) -> Int {
        lock.lock(); defer { lock.unlock() }
        return attemptsThisSession[kind] ?? 0
    }

    // MARK: Persistence (call under lock)

    private func loadIntentsLocked() -> [AvafliPendingIntent] {
        (try? storage.load([AvafliPendingIntent].self, for: storageKey)) ?? []
    }

    private func saveIntentsLocked(_ intents: [AvafliPendingIntent]) {
        if intents.isEmpty {
            try? storage.remove(for: storageKey)
        } else {
            try? storage.save(intents, for: storageKey)
        }
    }

    /// SAME-DAY GUARD: drops any intent whose local calendar day has ended.
    /// The server would re-window a stale claim into the new day anyway
    /// (server-authoritative day windows — governed anti-fraud contract), and
    /// initiating a NEW day's claim is the auto-open engine's job, not ours.
    private func pruneLocked() -> [AvafliPendingIntent] {
        let today = Self.dayKey(for: now())
        let intents = loadIntentsLocked()
        let fresh = intents.filter { $0.dayKey == today }
        if fresh.count != intents.count {
            Logger.shared.log("Offline retry: dropped \(intents.count - fresh.count) stale (previous-day) intent(s)", level: .info)
            saveIntentsLocked(fresh)
        }
        return fresh
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

// MARK: - Offline analytics buffering

/// One buffered publisher-facing analytics event, with its ORIGINAL timestamp
/// so a flush after reconnect doesn't shift the publisher's timeline.
struct AvafliBufferedAnalyticsEvent: Codable {
    let event: String
    /// JSON-encoded properties (JSONSerialization); nil when the event had none.
    let propertiesJSON: Data?
    let timestamp: Date
}

/// Wraps the publisher's `AnalyticsAdapter`. While offline, events land in a
/// bounded, persisted ring buffer (capacity 100 — oldest dropped first) and
/// are replayed in order on connectivity regain / next launch, each carrying
/// `original_timestamp` (ISO-8601) and `original_timestamp_ms`.
final class BufferingAnalyticsAdapter: AnalyticsAdapter {

    static let capacity = 100

    private let inner: AnalyticsAdapter
    private let storage: Storage
    private let storageKey: String
    private let isOnline: () -> Bool
    private let now: () -> Date
    private let lock = NSLock()

    init(
        wrapping inner: AnalyticsAdapter,
        storage: Storage,
        bundleId: String,
        isOnline: @escaping () -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.inner = inner
        self.storage = storage
        self.storageKey = "winr.\(bundleId).offline.analyticsBuffer"
        self.isOnline = isOnline
        self.now = now
    }

    func track(event: String, properties: [String: Any]?) {
        if isOnline() {
            // Preserve ordering: anything buffered from an offline stretch
            // flushes BEFORE the live event goes through.
            flush()
            inner.track(event: event, properties: properties)
        } else {
            buffer(event: event, properties: properties)
        }
    }

    /// Replays the buffered events to the wrapped adapter, oldest first.
    /// Called on connectivity regain, on launch, and before any live event.
    func flush() {
        lock.lock()
        let events = loadBufferLocked()
        guard !events.isEmpty else { lock.unlock(); return }
        try? storage.remove(for: storageKey)
        lock.unlock()

        let isoFormatter = ISO8601DateFormatter()
        for buffered in events {
            var properties = decodeProperties(buffered.propertiesJSON) ?? [:]
            properties["original_timestamp"] = isoFormatter.string(from: buffered.timestamp)
            properties["original_timestamp_ms"] = Int(buffered.timestamp.timeIntervalSince1970 * 1000)
            inner.track(event: buffered.event, properties: properties)
        }
        Logger.shared.log("Flushed \(events.count) buffered offline analytics event(s)", level: .debug)
    }

    var bufferedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return loadBufferLocked().count
    }

    private func buffer(event: String, properties: [String: Any]?) {
        lock.lock()
        var events = loadBufferLocked()
        events.append(AvafliBufferedAnalyticsEvent(
            event: event,
            propertiesJSON: encodeProperties(properties),
            timestamp: now()
        ))
        // Bounded ring buffer — drop oldest beyond capacity. HARD cap.
        if events.count > Self.capacity {
            events.removeFirst(events.count - Self.capacity)
        }
        try? storage.save(events, for: storageKey)
        lock.unlock()
    }

    private func loadBufferLocked() -> [AvafliBufferedAnalyticsEvent] {
        (try? storage.load([AvafliBufferedAnalyticsEvent].self, for: storageKey)) ?? []
    }

    private func encodeProperties(_ properties: [String: Any]?) -> Data? {
        guard let properties, !properties.isEmpty else { return nil }
        if JSONSerialization.isValidJSONObject(properties) {
            return try? JSONSerialization.data(withJSONObject: properties)
        }
        // Non-JSON values (Date, custom types…) degrade to their descriptions.
        let stringified = properties.mapValues { "\($0)" }
        return try? JSONSerialization.data(withJSONObject: stringified)
    }

    private func decodeProperties(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - Shared wiring

/// Session-scoped owner of the offline machinery. Built by `Avafli.configure`;
/// everything inside is individually testable without it.
final class AvafliOfflineResilience {

    private(set) static var shared: AvafliOfflineResilience?

    let coordinator: OfflineRetryCoordinator
    let monitor: ConnectivityMonitoring
    private let storage: Storage
    private let bundleId: String
    private var analyticsWrapper: BufferingAnalyticsAdapter?
    private let lock = NSLock()

    /// A background claim retry just succeeded — an open experience should
    /// reconcile via its existing load()/refresh path.
    static let claimRetrySucceededNotification = Notification.Name("AvafliOfflineClaimRetrySucceeded")

    init(
        bundleId: String,
        storage: Storage = UserDefaultsStorage(),
        monitor: ConnectivityMonitoring = NWPathConnectivityMonitor()
    ) {
        self.bundleId = bundleId
        self.storage = storage
        self.monitor = monitor
        self.coordinator = OfflineRetryCoordinator(storage: storage, bundleId: bundleId)

        monitor.onConnectivityRegained = { [weak self] in
            self?.coordinator.noteConnectivityRegained()
            self?.flushAnalyticsBuffer()
        }
        monitor.start()
    }

    /// (Re)build the shared instance on configure. Reused when the bundle id
    /// is unchanged so the session attempt caps aren't reset by re-configures.
    @discardableResult
    static func activate(bundleId: String) -> AvafliOfflineResilience {
        if let existing = shared, existing.bundleId == bundleId {
            return existing
        }
        shared?.monitor.stop()
        let instance = AvafliOfflineResilience(bundleId: bundleId)
        shared = instance
        return instance
    }

    /// Memoized buffering wrapper around the publisher's adapter.
    func analyticsAdapter(wrapping inner: AnalyticsAdapter?) -> AnalyticsAdapter? {
        guard let inner else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let analyticsWrapper { return analyticsWrapper }
        let wrapper = BufferingAnalyticsAdapter(
            wrapping: inner,
            storage: storage,
            bundleId: bundleId,
            isOnline: { [weak self] in self?.monitor.isOnline ?? true }
        )
        analyticsWrapper = wrapper
        return wrapper
    }

    func flushAnalyticsBuffer() {
        lock.lock()
        let wrapper = analyticsWrapper
        lock.unlock()
        guard monitor.isOnline else { return }
        wrapper?.flush()
    }

    static func _resetForTests() {
        shared?.monitor.stop()
        shared = nil
    }
}
