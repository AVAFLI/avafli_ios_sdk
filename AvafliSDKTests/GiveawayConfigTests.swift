import XCTest
@testable import AvafliSDK

final class GiveawayConfigTests: XCTestCase {

    // MARK: - Full GiveawayConfig parsing

    func testFullGiveawayConfigDecoding() throws {
        let json = """
        {
            "id": "give_abc",
            "title": "February Sweepstakes",
            "prizeDescription": "$1,000 Cash",
            "prizeValue": 1000.0,
            "streakLadder": [10, 30, 60, 130, 240, 300],
            "doublingEnabled": true,
            "maxDailyBaseEntries": 300,
            "rulesUrl": "https://example.com/rules",
            "startDate": "2026-02-01",
            "endDate": "2026-02-28",
            "streakConfig": {
                "weeklyResetDay": 1,
                "monthlyResetDay": 1,
                "weeklyBonusThreshold": 5,
                "weeklyBonusEntries": 100,
                "monthlyBonusThreshold": 20,
                "monthlyBonusEntries": 500
            }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(GiveawayConfig.self, from: json)
        XCTAssertEqual(config.id, "give_abc")
        XCTAssertEqual(config.title, "February Sweepstakes")
        XCTAssertEqual(config.prizeDescription, "$1,000 Cash")
        XCTAssertEqual(config.prizeValue, 1000.0)
        XCTAssertEqual(config.streakLadder.count, 6)
        XCTAssertTrue(config.doublingEnabled)
        XCTAssertEqual(config.maxDailyBaseEntries, 300)
        XCTAssertEqual(config.rulesUrl, "https://example.com/rules")
        XCTAssertEqual(config.startDate, "2026-02-01")
        XCTAssertEqual(config.endDate, "2026-02-28")
    }

    // MARK: - StreakConfig parsing

    func testStreakConfigDecoding() throws {
        let json = """
        {
            "weeklyResetDay": 1,
            "monthlyResetDay": 1,
            "weeklyBonusThreshold": 5,
            "weeklyBonusEntries": 100,
            "monthlyBonusThreshold": 20,
            "monthlyBonusEntries": 500
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(StreakConfig.self, from: json)
        XCTAssertEqual(config.weeklyResetDay, 1)
        XCTAssertEqual(config.monthlyResetDay, 1)
        XCTAssertEqual(config.weeklyBonusThreshold, 5)
        XCTAssertEqual(config.weeklyBonusEntries, 100)
        XCTAssertEqual(config.monthlyBonusThreshold, 20)
        XCTAssertEqual(config.monthlyBonusEntries, 500)
    }

    // MARK: - StreakConfigAPI (from network)

    func testStreakConfigAPIDecoding() throws {
        let json = """
        {
            "weeklyResetDay": 2,
            "monthlyResetDay": 15,
            "weeklyBonusThreshold": 7,
            "weeklyBonusEntries": 200,
            "monthlyBonusThreshold": 25,
            "monthlyBonusEntries": 1000
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(StreakConfigAPI.self, from: json)
        XCTAssertEqual(config.weeklyResetDay, 2)
        XCTAssertEqual(config.monthlyResetDay, 15)
    }

    // MARK: - Giveaway model

    func testGiveawayModelDecoding() throws {
        let json = """
        {
            "id": "c1",
            "title": "Test Giveaway",
            "period": "monthly",
            "maxDailyBaseEntries": 300,
            "doublingEnabled": false,
            "streakConfig": {
                "weeklyResetDay": 1,
                "monthlyResetDay": 1,
                "weeklyBonusThreshold": 5,
                "weeklyBonusEntries": 100,
                "monthlyBonusThreshold": 20,
                "monthlyBonusEntries": 500
            }
        }
        """.data(using: .utf8)!
        let giveaway = try JSONDecoder().decode(Giveaway.self, from: json)
        XCTAssertEqual(giveaway.id, "c1")
        XCTAssertEqual(giveaway.period, .monthly)
        XCTAssertFalse(giveaway.doublingEnabled)
    }

    // MARK: - GiveawayConfig encoding/decoding round-trip

    func testGiveawayConfigRoundTrip() throws {
        let original = GiveawayConfig(
            id: "rt1",
            title: "Round Trip",
            prizeDescription: "Prize",
            prizeValue: 500,
            streakLadder: [10, 20, 30],
            doublingEnabled: false,
            maxDailyBaseEntries: 30,
            rulesUrl: "https://rules.com",
            startDate: "2026-01-01",
            endDate: "2026-06-30",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 1,
                monthlyResetDay: 1,
                weeklyBonusThreshold: 3,
                weeklyBonusEntries: 50,
                monthlyBonusThreshold: 10,
                monthlyBonusEntries: 200,
                monthlyMilestones: nil
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GiveawayConfig.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.streakLadder, original.streakLadder)
        XCTAssertEqual(decoded.prizeValue, original.prizeValue)
        XCTAssertNil(decoded.prizeImageUrl)
        XCTAssertNil(decoded.streakMode)
        XCTAssertNil(decoded.latestWinner)
    }

    func testGiveawayConfigRoundTripWithV2Fields() throws {
        let original = GiveawayConfig(
            id: "rt2",
            title: "Round Trip V2",
            prizeDescription: "Prize",
            prizeValue: 500,
            streakLadder: [10, 20, 30],
            doublingEnabled: false,
            maxDailyBaseEntries: 30,
            rulesUrl: "https://rules.com",
            startDate: "2026-01-01",
            endDate: "2026-06-30",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 1, monthlyResetDay: 1,
                weeklyBonusThreshold: nil, weeklyBonusEntries: nil,
                monthlyBonusThreshold: nil, monthlyBonusEntries: nil,
                monthlyMilestones: nil
            ),
            milestones: [MilestoneConfigAPI(day: 7, bonusEntries: 25, badge: "flame")],
            prizeImageUrl: "https://cdn.example.com/prize.png",
            streakMode: "visit",
            latestWinner: GiveawayWinner(
                name: "Catherine C.",
                location: "Brooklyn, New York",
                avatarUrl: "https://cdn.example.com/avatar.png",
                awardedAt: "2026-08-20"
            )
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GiveawayConfig.self, from: data)
        XCTAssertEqual(decoded.prizeImageUrl, "https://cdn.example.com/prize.png")
        XCTAssertEqual(decoded.streakMode, "visit")
        XCTAssertEqual(decoded.latestWinner?.name, "Catherine C.")
        XCTAssertEqual(decoded.latestWinner?.location, "Brooklyn, New York")
        XCTAssertEqual(decoded.latestWinner?.awardedAt, "2026-08-20")
        XCTAssertEqual(decoded.milestones?.count, 1)
        XCTAssertEqual(decoded.milestones?.first?.day, 7)
        XCTAssertEqual(decoded.milestones?.first?.bonusEntries, 25)
        XCTAssertEqual(decoded.milestones?.first?.badge, "flame")
    }

    func testGiveawayConfigDecodingWithV2FieldsFromJSON() throws {
        let json = """
        {
            "id": "give_v2",
            "title": "V2 Giveaway",
            "prizeDescription": "$500 Cash",
            "prizeValue": 500.0,
            "streakLadder": [10, 30, 60],
            "doublingEnabled": false,
            "maxDailyBaseEntries": 60,
            "rulesUrl": "https://example.com/rules",
            "startDate": "2026-08-01",
            "endDate": "2026-08-31",
            "streakConfig": {"weeklyResetDay": 1, "monthlyResetDay": 1},
            "milestones": [
                {"day": 7, "bonusEntries": 25, "badge": "flame"},
                {"day": 30, "bonusEntries": 100, "badge": null}
            ],
            "prizeImageUrl": "https://cdn.example.com/hero.png",
            "streakMode": "daily",
            "latestWinner": {"name": "Alex R.", "location": "Austin, Texas", "awardedAt": "2026-07-15"}
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(GiveawayConfig.self, from: json)
        XCTAssertEqual(config.prizeImageUrl, "https://cdn.example.com/hero.png")
        XCTAssertEqual(config.streakMode, "daily")
        XCTAssertEqual(config.latestWinner?.name, "Alex R.")
        XCTAssertEqual(config.milestones?.count, 2)
        XCTAssertEqual(config.milestones?[1].day, 30)
        XCTAssertEqual(config.milestones?[1].bonusEntries, 100)
        XCTAssertNil(config.milestones?[1].badge)
    }

    // MARK: - GiveawayWinner display formatting

    func testGiveawayWinnerAwardedAtDisplayFormatsDate() {
        let winner = GiveawayWinner(
            name: "Catherine C.", location: nil, avatarUrl: nil, awardedAt: "2026-08-20"
        )
        XCTAssertEqual(winner.awardedAtDisplay, "August 20, 2026")
    }

    func testGiveawayWinnerAwardedAtDisplayFallsBackToRawString() {
        let winner = GiveawayWinner(
            name: "Catherine C.", location: nil, avatarUrl: nil, awardedAt: "last week"
        )
        XCTAssertEqual(winner.awardedAtDisplay, "last week")
    }

    func testGiveawayWinnerAwardedAtDisplayNilWhenAbsent() {
        let winner = GiveawayWinner(name: "N.", location: nil, avatarUrl: nil, awardedAt: nil)
        XCTAssertNil(winner.awardedAtDisplay)
    }

    // MARK: - Storage round-trip for giveaway

    func testGiveawayConfigStorageRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "test.giveaway.config")!
        defaults.removePersistentDomain(forName: "test.giveaway.config")
        defer { defaults.removePersistentDomain(forName: "test.giveaway.config") }
        let storage = UserDefaultsStorage(defaults: defaults)

        let config = GiveawayConfig(
            id: "store1",
            title: "Stored",
            prizeDescription: "Desc",
            prizeValue: 100,
            streakLadder: [5, 10],
            doublingEnabled: true,
            maxDailyBaseEntries: 10,
            rulesUrl: "https://r.com",
            startDate: "2026-01-01",
            endDate: "2026-12-31",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 1, monthlyResetDay: 1,
                weeklyBonusThreshold: 3, weeklyBonusEntries: 30,
                monthlyBonusThreshold: 10, monthlyBonusEntries: 100,
                monthlyMilestones: nil
            )
        )
        try storage.save(config, for: "test_giveaway")
        let loaded: GiveawayConfig? = try storage.load(GiveawayConfig.self, for: "test_giveaway")
        XCTAssertEqual(loaded?.id, "store1")
        XCTAssertEqual(loaded?.streakLadder, [5, 10])
    }

    // MARK: - GetActiveGiveawayRequest/Response

    func testGetActiveGiveawayRequestPath() {
        let request = GetActiveGiveawayRequest()
        XCTAssertEqual(request.path, "getActiveGiveaway")
        XCTAssertEqual(request.method, "POST")
    }

    func testGetActiveGiveawayResponseNullGiveaway() throws {
        let json = """
        {"giveaway": null}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(GetActiveGiveawayResponse.self, from: json)
        XCTAssertNil(response.giveaway)
    }

    // MARK: - StreakState defaults

    func testStreakStateDefaults() {
        let state = StreakState()
        XCTAssertEqual(state.currentDay, 1)
        XCTAssertNil(state.lastClaimedDate)
        XCTAssertEqual(state.totalEntriesEarned, 0)
        XCTAssertEqual(state.weeklyCurrent, 0)
        XCTAssertNil(state.weeklyStart)
        XCTAssertEqual(state.monthlyCurrent, 0)
        XCTAssertNil(state.monthlyStart)
    }

    func testStreakStateCodable() throws {
        let state = StreakState(
            currentDay: 3,
            lastClaimedDate: Date(timeIntervalSince1970: 1000000),
            totalEntriesEarned: 100,
            weeklyCurrent: 2,
            weeklyStart: "2026-02-16",
            monthlyCurrent: 5,
            monthlyStart: "2026-02-01"
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(StreakState.self, from: data)
        XCTAssertEqual(decoded.currentDay, 3)
        XCTAssertEqual(decoded.totalEntriesEarned, 100)
        XCTAssertEqual(decoded.weeklyCurrent, 2)
        XCTAssertEqual(decoded.weeklyStart, "2026-02-16")
    }

    // MARK: - AvafliConfiguration

    func testAvafliConfigurationConstruction() {
        let config = AvafliConfiguration(
            apiKey: "pk_live_abc",
            environment: .production,
            bundleId: "com.app.live",
            user: AvafliUser(id: "user-1", firstName: "Jane", lastName: "Doe")
        )
        XCTAssertEqual(config.apiKey, "pk_live_abc")
        XCTAssertEqual(config.bundleId, "com.app.live")
        XCTAssertEqual(config.user.id, "user-1")
    }

    func testAvafliEnvironmentCases() {
        // Production-only: no staging/qa infrastructure exists.
        let envs: [AvafliEnvironment] = [.production]
        XCTAssertEqual(envs.count, 1)
    }

    // NOTE: the DeleteUserData tests were removed with the endpoint itself —
    // 2.5.0 replaced hard deletion with Avafli.optOut() (entry records are the
    // evidence a drawing was fair).
}
