import XCTest
@testable import AvafliSDK

final class PrizeCappingTests: XCTestCase {

    // MARK: - GiveawayConfig constraints

    func testGiveawayConfigMaxDailyBaseEntries() throws {
        let json = """
        {
            "id": "camp_1",
            "title": "Test",
            "prizeDescription": "Cash",
            "prizeValue": 1000.0,
            "streakLadder": [10, 30, 60, 130, 240, 300],
            "doublingEnabled": true,
            "maxDailyBaseEntries": 300,
            "rulesUrl": "https://example.com",
            "startDate": "2026-01-01",
            "endDate": "2026-12-31",
            "streakConfig": {
                "weeklyResetDay": 0,
                "monthlyResetDay": 1,
                "weeklyBonusThreshold": 5,
                "weeklyBonusEntries": 100,
                "monthlyBonusThreshold": 20,
                "monthlyBonusEntries": 500
            }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(GiveawayConfig.self, from: json)
        XCTAssertEqual(config.maxDailyBaseEntries, 300)
        XCTAssertEqual(config.prizeValue, 1000.0)
    }

    // MARK: - Streak ladder enforces max per day

    func testStreakLadderNeverExceedsMaxDaily() {
        let engine = StreakEngine()
        let maxDaily = 300
        for day in 1...6 {
            XCTAssertLessThanOrEqual(
                engine.baseEntries(forDay: day), maxDaily,
                "Day \(day) exceeds max daily entries"
            )
        }
    }

    func testStreakLadderDay6EqualsMax() {
        let engine = StreakEngine()
        XCTAssertEqual(engine.baseEntries(forDay: 6), 300)
    }

    // MARK: - DailyEntryGrant total

    func testDailyEntryGrantTotal() {
        let grant = DailyEntryGrant(baseEntries: 60, bonusEntries: 60)
        XCTAssertEqual(grant.total, 120)
    }

    func testDailyEntryGrantTotalWithoutBonus() {
        let grant = DailyEntryGrant(baseEntries: 130)
        XCTAssertEqual(grant.total, 130)
        XCTAssertEqual(grant.bonusEntries, 0)
    }

    // MARK: - ClaimDailyEntriesResponse parsing

    func testClaimDailyEntriesResponseDecoding() throws {
        let json = """
        {
            "entries": 60,
            "streakDay": 3,
            "totalEntries": 160,
            "weeklyBonusEntries": null,
            "monthlyBonusEntries": null
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaimDailyEntriesResponse.self, from: json)
        XCTAssertEqual(response.entries, 60)
        XCTAssertEqual(response.streakDay, 3)
        XCTAssertEqual(response.totalEntries, 160)
        XCTAssertNil(response.weeklyBonusEntries)
    }

    func testClaimDailyEntriesResponseWithBonuses() throws {
        let json = """
        {
            "entries": 240,
            "streakDay": 5,
            "totalEntries": 870,
            "weeklyBonusEntries": 100,
            "monthlyBonusEntries": 500
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ClaimDailyEntriesResponse.self, from: json)
        XCTAssertEqual(response.weeklyBonusEntries, 100)
        XCTAssertEqual(response.monthlyBonusEntries, 500)
    }

    // NOTE: ClaimBonusEntriesResponse tests were removed with the endpoint
    // (the rewarded-video bonus stack is gone from the SDK).

    // MARK: - Prize value from config

    func testPrizeValueFromGiveawayConfig() throws {
        let json = """
        {
            "id": "camp_2",
            "title": "Small Prize",
            "prizeDescription": "Gift card",
            "prizeValue": 50.0,
            "streakLadder": [5, 15, 30],
            "doublingEnabled": false,
            "maxDailyBaseEntries": 30,
            "rulesUrl": "https://example.com",
            "startDate": "2026-01-01",
            "endDate": "2026-03-31",
            "streakConfig": {
                "weeklyResetDay": 0,
                "monthlyResetDay": 1,
                "weeklyBonusThreshold": 5,
                "weeklyBonusEntries": 50,
                "monthlyBonusThreshold": 15,
                "monthlyBonusEntries": 200
            }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(GiveawayConfig.self, from: json)
        XCTAssertEqual(config.prizeValue, 50.0)
        XCTAssertEqual(config.streakLadder.count, 3)
        XCTAssertFalse(config.doublingEnabled)
    }
}
