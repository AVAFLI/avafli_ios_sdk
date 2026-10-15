import XCTest
@testable import AvafliSDK

final class StorageTests: XCTestCase {

    private var storage: UserDefaultsStorage!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "com.winr.sdk.test.storage")!
        defaults.removePersistentDomain(forName: "com.winr.sdk.test.storage")
        storage = UserDefaultsStorage(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "com.winr.sdk.test.storage")
        super.tearDown()
    }

    // MARK: - Basic CRUD

    func testSaveAndLoadString() throws {
        try storage.save("hello", for: "key1")
        let loaded: String? = try storage.load(String.self, for: "key1")
        XCTAssertEqual(loaded, "hello")
    }

    func testSaveAndLoadInt() throws {
        try storage.save(42, for: "num")
        let loaded: Int? = try storage.load(Int.self, for: "num")
        XCTAssertEqual(loaded, 42)
    }

    func testLoadNonexistentReturnsNil() throws {
        let result: String? = try storage.load(String.self, for: "missing")
        XCTAssertNil(result)
    }

    func testRemove() throws {
        try storage.save("temp", for: "key")
        try storage.remove(for: "key")
        let result: String? = try storage.load(String.self, for: "key")
        XCTAssertNil(result)
    }

    func testOverwrite() throws {
        try storage.save("v1", for: "key")
        try storage.save("v2", for: "key")
        let loaded: String? = try storage.load(String.self, for: "key")
        XCTAssertEqual(loaded, "v2")
    }

    // MARK: - Complex types

    func testSaveAndLoadStreakState() throws {
        let state = StreakState(
            currentDay: 4,
            lastClaimedDate: Date(timeIntervalSince1970: 1708300800),
            totalEntriesEarned: 230,
            weeklyCurrent: 3,
            weeklyStart: "2026-02-15",
            monthlyCurrent: 12,
            monthlyStart: "2026-02-01"
        )
        try storage.save(state, for: "streak")
        let loaded: StreakState? = try storage.load(StreakState.self, for: "streak")
        XCTAssertEqual(loaded?.currentDay, 4)
        XCTAssertEqual(loaded?.totalEntriesEarned, 230)
        XCTAssertEqual(loaded?.weeklyCurrent, 3)
        XCTAssertEqual(loaded?.weeklyStart, "2026-02-15")
        XCTAssertEqual(loaded?.monthlyCurrent, 12)
    }

    func testSaveAndLoadGiveawayConfig() throws {
        let config = GiveawayConfig(
            id: "c1", title: "Test", prizeDescription: "Prize",
            prizeValue: 500, streakLadder: [10, 20, 30],
            doublingEnabled: true, maxDailyBaseEntries: 30,
            rulesUrl: "https://rules.com",
            startDate: "2026-01-01", endDate: "2026-12-31",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 0, monthlyResetDay: 1,
                weeklyBonusThreshold: 5, weeklyBonusEntries: 100,
                monthlyBonusThreshold: 20, monthlyBonusEntries: 500,
                monthlyMilestones: nil
            )
        )
        try storage.save(config, for: "giveaway")
        let loaded: GiveawayConfig? = try storage.load(GiveawayConfig.self, for: "giveaway")
        XCTAssertEqual(loaded?.id, "c1")
        XCTAssertEqual(loaded?.prizeValue, 500)
    }

    // MARK: - DailyEntryGrant

    func testDailyEntryGrantProperties() {
        let grant = DailyEntryGrant(baseEntries: 60, bonusEntries: 60)
        XCTAssertEqual(grant.baseEntries, 60)
        XCTAssertEqual(grant.bonusEntries, 60)
        XCTAssertEqual(grant.total, 120)
    }

    func testDailyEntryGrantDefaultBonus() {
        let grant = DailyEntryGrant(baseEntries: 10)
        XCTAssertEqual(grant.bonusEntries, 0)
        XCTAssertEqual(grant.total, 10)
    }
}
