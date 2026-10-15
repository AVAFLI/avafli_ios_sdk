//
//  OptOutRejoinTests.swift
//  AvafliSDKTests
//
//  3.2.0 — rejoin 24 hours after "Delete my data" (Rules §9, Terms §5.2,
//  Privacy §6). The opt-out is cached with the moment it lifts; when that
//  moment has passed, `configure()` (and the next foreground) clears the
//  opt-out and every piece of the old session, then registers normally.
//

import XCTest
@testable import AvafliSDK

final class OptOutRejoinTests: XCTestCase {

    private let bundleId = "com.avafli.tests.rejoin"
    private let userId = "u-rejoin"
    private let defaults = UserDefaults.standard
    private let keychain = KeychainStorage()
    /// The device clock the SDK runs on.
    private let clock = Clock(Date(timeIntervalSince1970: 1_790_000_000))

    private final class Clock {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func advance(by seconds: TimeInterval) {
            lock.lock(); value = value.addingTimeInterval(seconds); lock.unlock()
        }
    }

    private final class Counter {
        private let lock = NSLock()
        private var count = 0
        var value: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock(); count += 1; lock.unlock()
        }
    }

    // MARK: Keys

    private var optedOutKey: String { "winr_opted_out_\(bundleId)" }
    private var optedOutUntilKey: String { "winr_opted_out_until_\(bundleId)" }

    /// Every piece of the old session the SDK keeps in UserDefaults.
    private var sessionKeys: [String] {
        [
            "winr_last_auto_present_\(bundleId)",
            "winr_unregistered_impressions_\(bundleId)",
            "winr_marketing_consent",
            "winr.\(bundleId).giveaway",
            "winr.\(bundleId).user.\(userId).emailSubmitted",
            "winr.\(bundleId).user.\(userId).streak",
            "winr.\(bundleId).user.\(userId).adoptionCodeSentAt",
            // A second host identity on the same install.
            "winr.\(bundleId).user.someone-else.emailSubmitted",
        ]
    }

    private var pendingIntentsKey: String { "winr.\(bundleId).offline.pendingIntents" }

    override func setUp() {
        super.setUp()
        wipe()
        Avafli._resetPresentationStateForTests()
        let clock = self.clock
        Avafli._setNowForTests { clock.now }
    }

    override func tearDown() {
        Avafli._setRegistrationOverrideForTests(nil)
        Avafli._resetPresentationStateForTests()
        wipe()
        super.tearDown()
    }

    private func wipe() {
        for key in sessionKeys + [optedOutKey, optedOutUntilKey, pendingIntentsKey] {
            defaults.removeObject(forKey: key)
        }
        keychain.deleteAll()
    }

    // MARK: Harness

    private func makeConfig() -> AvafliConfiguration {
        AvafliConfiguration(
            apiKey: "avafli_test_rejoin",
            bundleId: bundleId,
            user: AvafliUser(id: userId),
            options: AvafliOptions(logging: .none, analyticsAdapter: nil, enablePushReminders: false)
        )
    }

    /// An opted-out install with a session left over from before the delete.
    /// `until` nil = a flag cached by a build that stored no time.
    private func seedOptedOutInstall(until: Date?, withAuthToken: Bool) {
        defaults.set(true, forKey: optedOutKey)
        if let until {
            defaults.set(until.timeIntervalSince1970, forKey: optedOutUntilKey)
        }
        for key in sessionKeys {
            defaults.set(Data("seed".utf8), forKey: key)
        }
        if withAuthToken { keychain.saveToken("old-session-token") }
        keychain.saveRefreshToken("old-refresh-token")
        keychain.saveUUID("old-user-id")
    }

    private func storedUntil() -> Date? {
        (defaults.object(forKey: optedOutUntilKey) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    @discardableResult
    private func configureAndSettle(registrations: Counter, onRegister: (() -> Void)? = nil) async -> Counter {
        Avafli._setRegistrationOverrideForTests { _ in
            registrations.increment()
            onRegister?()
        }
        Avafli.configure(makeConfig())
        await Avafli._awaitRegistrationForTests()
        return registrations
    }

    @MainActor
    private func presentResult() -> (accepted: Bool, result: Result<DailyEntryGrant, AvafliError>?) {
        var result: Result<DailyEntryGrant, AvafliError>?
        let accepted = Avafli.present { result = $0 }
        return (accepted, result)
    }

    // MARK: Before the moment: nothing changes

    func testOptedOutWithTimeInTheFutureChangesNothing() async {
        let until = clock.now.addingTimeInterval(3 * 60 * 60)
        // No auth token: configure()'s profile submit then stays off the network.
        seedOptedOutInstall(until: until, withAuthToken: false)
        let registrations = Counter()

        await configureAndSettle(registrations: registrations)

        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertTrue(defaults.bool(forKey: optedOutKey))
        XCTAssertEqual(storedUntil(), until)
        for key in sessionKeys {
            XCTAssertNotNil(defaults.object(forKey: key), "\(key) must be left alone")
        }
        XCTAssertEqual(keychain.loadRefreshToken(), "old-refresh-token")
        XCTAssertEqual(keychain.loadUUID(), "old-user-id")
        // configure() registers exactly as it always has — once.
        XCTAssertEqual(registrations.value, 1)

        // No presentation: present() is a no-op.
        let outcome = await presentResult()
        XCTAssertFalse(outcome.accepted)
        guard case .failure(.optedOut)? = outcome.result else {
            return XCTFail("Expected .optedOut, got \(String(describing: outcome.result))")
        }

        // A foreground before the moment does not register again.
        await Avafli._foregroundRejoinCheckForTests()
        XCTAssertEqual(registrations.value, 1)
        XCTAssertTrue(Avafli._isOptedOutForTests())
    }

    // MARK: After the moment: a brand-new participant

    func testOptedOutWithTimePassedClearsTheOldSessionAndRegisters() async {
        seedOptedOutInstall(until: clock.now.addingTimeInterval(-1), withAuthToken: true)
        defaults.set(Data("seed".utf8), forKey: pendingIntentsKey)
        let registrations = Counter()
        var keychainAtRegistration: [String?] = ["unset"]
        let keychain = self.keychain

        await configureAndSettle(registrations: registrations) {
            keychainAtRegistration = [keychain.loadToken(), keychain.loadRefreshToken(), keychain.loadUUID()]
        }

        // The opt-out is gone…
        XCTAssertFalse(Avafli._isOptedOutForTests())
        XCTAssertNil(defaults.object(forKey: optedOutKey))
        XCTAssertNil(defaults.object(forKey: optedOutUntilKey))
        // …and so is each piece of the old session.
        XCTAssertNil(defaults.object(forKey: "winr_last_auto_present_\(bundleId)"), "once-per-day auto-open mark")
        XCTAssertNil(defaults.object(forKey: "winr_unregistered_impressions_\(bundleId)"), "impression counter")
        XCTAssertNil(defaults.object(forKey: "winr_marketing_consent"), "marketing consent")
        XCTAssertNil(defaults.object(forKey: "winr.\(bundleId).giveaway"), "cached giveaway")
        XCTAssertNil(defaults.object(forKey: "winr.\(bundleId).user.\(userId).emailSubmitted"), "email-submitted flag")
        XCTAssertNil(defaults.object(forKey: "winr.\(bundleId).user.\(userId).streak"), "cached streak")
        XCTAssertNil(defaults.object(forKey: "winr.\(bundleId).user.\(userId).adoptionCodeSentAt"), "adoption stamp")
        XCTAssertNil(defaults.object(forKey: "winr.\(bundleId).user.someone-else.emailSubmitted"), "other identity's flag")
        XCTAssertNil(defaults.object(forKey: pendingIntentsKey), "queued claim retry")
        XCTAssertNil(keychain.loadToken(), "auth token")
        XCTAssertNil(keychain.loadRefreshToken(), "refresh token")
        XCTAssertNil(keychain.loadUUID(), "user id")
        XCTAssertNil(Avafli._cachedGiveawayForTests())
        XCTAssertNil(Avafli._cachedEmailConsentForTests())

        // Registration ran, and it ran for a device with no session (so the
        // backend is asked to register, not to refresh the old account).
        XCTAssertEqual(registrations.value, 1)
        XCTAssertEqual(keychainAtRegistration, [nil, nil, nil])

        // The normal flow follows: the opt-out gate no longer answers.
        let outcome = await presentResult()
        guard case .failure(.giveawayNotActive)? = outcome.result else {
            return XCTFail("Expected the normal no-giveaway answer, got \(String(describing: outcome.result))")
        }
    }

    func testLapseWhileTheAppStayedInMemoryLiftsOnForeground() async {
        seedOptedOutInstall(until: clock.now.addingTimeInterval(60), withAuthToken: false)
        let registrations = Counter()
        await configureAndSettle(registrations: registrations)
        XCTAssertTrue(Avafli._isOptedOutForTests())

        clock.advance(by: 61)
        await Avafli._foregroundRejoinCheckForTests()

        XCTAssertFalse(Avafli._isOptedOutForTests())
        XCTAssertNil(defaults.object(forKey: optedOutKey))
        XCTAssertNil(keychain.loadUUID())
        XCTAssertEqual(registrations.value, 2)

        // Nothing left to lift: later foregrounds register nothing.
        await Avafli._foregroundRejoinCheckForTests()
        XCTAssertEqual(registrations.value, 2)
    }

    // MARK: A flag cached without a time

    func testLegacyOptOutGetsATimeAndLiftsADayLater() async {
        seedOptedOutInstall(until: nil, withAuthToken: false)
        let firstSeen = clock.now
        let registrations = Counter()

        await configureAndSettle(registrations: registrations)

        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertEqual(storedUntil(), firstSeen.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(keychain.loadUUID(), "old-user-id")

        // One second short of the day: still out.
        clock.advance(by: 24 * 60 * 60 - 1)
        await Avafli._foregroundRejoinCheckForTests()
        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertEqual(registrations.value, 1)

        clock.advance(by: 1)
        await configureAndSettle(registrations: registrations)
        XCTAssertFalse(Avafli._isOptedOutForTests())
        XCTAssertNil(defaults.object(forKey: optedOutKey))
        XCTAssertNil(keychain.loadUUID())
        XCTAssertEqual(registrations.value, 2)
    }

    // MARK: The server still says no

    func testServerStillOptedOutAdoptsItsTimeAndDoesNotLoop() async {
        seedOptedOutInstall(until: clock.now.addingTimeInterval(-1), withAuthToken: false)
        let serverUntil = clock.now.addingTimeInterval(2 * 60 * 60)
        let registrations = Counter()
        var serverOptedOut = true
        let serverIso = iso(serverUntil)

        await configureAndSettle(registrations: registrations) {
            if serverOptedOut {
                Avafli._noteServerOptOutForTests(optedOut: true, until: serverIso)
            }
        }

        XCTAssertEqual(registrations.value, 1)
        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertTrue(defaults.bool(forKey: optedOutKey))
        XCTAssertEqual(storedUntil()?.timeIntervalSince1970 ?? 0, serverUntil.timeIntervalSince1970, accuracy: 0.01)

        // No loop: until the server's time, nothing registers again.
        await Avafli._foregroundRejoinCheckForTests()
        clock.advance(by: 60 * 60)
        await Avafli._foregroundRejoinCheckForTests()
        XCTAssertEqual(registrations.value, 1)

        // After it: one more try, and this time the server lets them in.
        clock.advance(by: 60 * 60)
        serverOptedOut = false
        await Avafli._foregroundRejoinCheckForTests()
        XCTAssertEqual(registrations.value, 2)
        XCTAssertFalse(Avafli._isOptedOutForTests())
        XCTAssertNil(defaults.object(forKey: optedOutKey))
    }

    /// The server's time can already be behind this device's clock (skew).
    /// Adopting it as-is would re-try on every foreground.
    func testServerTimeBehindTheDeviceClockBacksOffInsteadOfLooping() async {
        seedOptedOutInstall(until: clock.now.addingTimeInterval(-1), withAuthToken: false)
        let registrations = Counter()
        let staleIso = iso(clock.now.addingTimeInterval(-10 * 60))
        let refusedAt = clock.now

        await configureAndSettle(registrations: registrations) {
            Avafli._noteServerOptOutForTests(optedOut: true, until: staleIso)
        }

        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertEqual(storedUntil(), refusedAt.addingTimeInterval(Avafli.optOutRecheckInterval))
        for _ in 0..<5 {
            await Avafli._foregroundRejoinCheckForTests()
        }
        XCTAssertEqual(registrations.value, 1)
    }

    // MARK: Where the time comes from

    func testServerReportedOptOutStoresTheServersTime() async {
        let registrations = Counter()
        let serverUntil = clock.now.addingTimeInterval(5 * 60 * 60)
        let serverIso = iso(serverUntil)

        await configureAndSettle(registrations: registrations) {
            Avafli._noteServerOptOutForTests(optedOut: true, until: serverIso)
        }

        XCTAssertTrue(Avafli._isOptedOutForTests())
        XCTAssertTrue(defaults.bool(forKey: optedOutKey))
        XCTAssertEqual(storedUntil()?.timeIntervalSince1970 ?? 0, serverUntil.timeIntervalSince1970, accuracy: 0.01)
    }

    /// An older backend reports the opt-out without a time.
    func testServerReportedOptOutWithoutATimeGetsTwentyFourHours() async {
        let registrations = Counter()
        let seenAt = clock.now

        await configureAndSettle(registrations: registrations) {
            Avafli._noteServerOptOutForTests(optedOut: true, until: nil)
        }

        XCTAssertEqual(storedUntil(), seenAt.addingTimeInterval(24 * 60 * 60))
    }

    func testResponsesDecodeOptedOutUntil() throws {
        let register = try JSONDecoder().decode(RegisterDeviceResponse.self, from: Data("""
        { "token": "t", "refreshToken": "r", "uuid": "u", "optedOut": true, "optedOutUntil": "2026-09-30T12:00:00.000Z" }
        """.utf8))
        XCTAssertEqual(register.optedOutUntil, "2026-09-30T12:00:00.000Z")

        let giveaway = try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: Data("""
        { "optedOut": true, "optedOutUntil": "2026-09-30T12:00:00.000Z" }
        """.utf8))
        XCTAssertEqual(giveaway.optedOutUntil, "2026-09-30T12:00:00.000Z")

        let optOut = try JSONDecoder().decode(OptOutResponse.self, from: Data("""
        { "success": true, "optedOut": true, "optedOutUntil": "2026-09-30T12:00:00.000Z" }
        """.utf8))
        XCTAssertEqual(optOut.optedOutUntil, "2026-09-30T12:00:00.000Z")

        // Older backends send none of it.
        let legacy = try JSONDecoder().decode(OptOutResponse.self, from: Data("""
        { "success": true, "optedOut": true }
        """.utf8))
        XCTAssertNil(legacy.optedOutUntil)
        XCTAssertNil(try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: Data("{}".utf8)).optedOutUntil)
    }

    // MARK: Copy

    func testDeleteConfirmationSaysTwentyFourHours() {
        XCTAssertEqual(
            AvafliV2Strings.optOutBody,
            "This permanently erases your information and ends your participation. Entries and streaks are forfeited and cannot be restored. You can join again as a new participant after 24 hours."
        )
    }
}
