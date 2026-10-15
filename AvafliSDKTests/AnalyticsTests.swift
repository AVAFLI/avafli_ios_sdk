import XCTest
@testable import AvafliSDK

// MARK: - Spy Analytics Adapter

final class SpyAnalyticsAdapter: AnalyticsAdapter {
    var trackedEvents: [(event: String, properties: [String: Any]?)] = []

    func track(event: String, properties: [String: Any]?) {
        trackedEvents.append((event: event, properties: properties))
    }

    var lastEvent: String? { trackedEvents.last?.event }
    var lastProperties: [String: Any]? { trackedEvents.last?.properties }
}

// MARK: - Analytics Tests

final class AnalyticsTests: XCTestCase {

    // MARK: - Event constants

    func testAnalyticsEventConstants() {
        XCTAssertEqual(AvafliAnalyticsEvent.registration, "avafli_registration")
        XCTAssertEqual(AvafliAnalyticsEvent.experienceOpened, "avafli_experience_opened")
        XCTAssertEqual(AvafliAnalyticsEvent.experienceClosed, "avafli_experience_closed")
        XCTAssertEqual(AvafliAnalyticsEvent.dailyEntryClaimed, "avafli_daily_entry_claimed")
        XCTAssertEqual(AvafliAnalyticsEvent.bonusEntryClaimed, "avafli_bonus_entry_claimed")
        XCTAssertEqual(AvafliAnalyticsEvent.streakMilestone, "avafli_streak_milestone")
        XCTAssertEqual(AvafliAnalyticsEvent.prizeWon, "avafli_prize_won")
    }

    func testLegacyAliases() {
        XCTAssertEqual(AvafliAnalyticsEvent.experiencePresented, AvafliAnalyticsEvent.experienceOpened)
        XCTAssertEqual(AvafliAnalyticsEvent.dailyEntriesClaimed, AvafliAnalyticsEvent.dailyEntryClaimed)
    }

    // MARK: - Spy adapter tracks events

    func testSpyAdapterTracksRegistration() {
        let spy = SpyAnalyticsAdapter()
        spy.trackRegistration(userId: "user-123")
        XCTAssertEqual(spy.lastEvent, "avafli_registration")
        XCTAssertEqual(spy.lastProperties?["user_id"] as? String, "user-123")
    }

    func testSpyAdapterTracksExperienceOpened() {
        let spy = SpyAnalyticsAdapter()
        spy.trackExperienceOpened(giveawayId: "camp_1")
        XCTAssertEqual(spy.lastEvent, "avafli_experience_opened")
        XCTAssertEqual(spy.lastProperties?["giveaway_id"] as? String, "camp_1")
    }

    func testSpyAdapterTracksExperienceOpenedNoGiveaway() {
        let spy = SpyAnalyticsAdapter()
        spy.trackExperienceOpened()
        XCTAssertEqual(spy.lastEvent, "avafli_experience_opened")
        XCTAssertTrue(spy.lastProperties?.isEmpty ?? true)
    }

    func testSpyAdapterTracksExperienceClosed() {
        let spy = SpyAnalyticsAdapter()
        spy.trackExperienceClosed(giveawayId: "camp_2")
        XCTAssertEqual(spy.lastEvent, "avafli_experience_closed")
    }

    func testSpyAdapterTracksDailyEntryClaimed() {
        let spy = SpyAnalyticsAdapter()
        spy.trackDailyEntryClaimed(day: 3, entries: 60)
        XCTAssertEqual(spy.lastEvent, "avafli_daily_entry_claimed")
        XCTAssertEqual(spy.lastProperties?["day"] as? Int, 3)
        XCTAssertEqual(spy.lastProperties?["entries"] as? Int, 60)
    }

    func testSpyAdapterTracksBonusEntryClaimed() {
        let spy = SpyAnalyticsAdapter()
        spy.trackBonusEntryClaimed(source: "rewarded_video", entries: 60)
        XCTAssertEqual(spy.lastEvent, "avafli_bonus_entry_claimed")
        XCTAssertEqual(spy.lastProperties?["source"] as? String, "rewarded_video")
    }

    func testSpyAdapterTracksStreakMilestone() {
        let spy = SpyAnalyticsAdapter()
        spy.trackStreakMilestone(day: 6, bonusEntries: 300)
        XCTAssertEqual(spy.lastEvent, "avafli_streak_milestone")
        XCTAssertEqual(spy.lastProperties?["streak_day"] as? Int, 6)
        XCTAssertEqual(spy.lastProperties?["bonus_entries"] as? Int, 300)
    }

    func testSpyAdapterTracksPrizeWon() {
        let spy = SpyAnalyticsAdapter()
        spy.trackPrizeWon(prizeName: "$1000 Cash", prizeValue: "1000")
        XCTAssertEqual(spy.lastEvent, "avafli_prize_won")
        XCTAssertEqual(spy.lastProperties?["prize_name"] as? String, "$1000 Cash")
        XCTAssertEqual(spy.lastProperties?["prize_value"] as? String, "1000")
    }

    func testSpyAdapterTracksPrizeWonWithoutValue() {
        let spy = SpyAnalyticsAdapter()
        spy.trackPrizeWon(prizeName: "Mystery Prize")
        XCTAssertNil(spy.lastProperties?["prize_value"])
    }

    func testMultipleEventsTracked() {
        let spy = SpyAnalyticsAdapter()
        spy.trackRegistration(userId: "u1")
        spy.trackExperienceOpened()
        spy.trackDailyEntryClaimed(day: 1, entries: 10)
        spy.trackExperienceClosed()
        XCTAssertEqual(spy.trackedEvents.count, 4)
    }

    // MARK: - ConsoleAnalyticsAdapter exists and conforms

    func testConsoleAnalyticsAdapterConformsToProtocol() {
        let adapter: AnalyticsAdapter = ConsoleAnalyticsAdapter()
        // Should not crash
        adapter.track(event: "test_event", properties: ["key": "value"])
        adapter.track(event: "test_event_no_props", properties: nil)
        adapter.track(event: "test_event_empty", properties: [:])
    }

    // MARK: - Default options use ConsoleAnalyticsAdapter

    func testDefaultOptionsUseConsoleAdapter() {
        let options = AvafliOptions()
        XCTAssertNotNil(options.analyticsAdapter)
        XCTAssertTrue(options.analyticsAdapter is ConsoleAnalyticsAdapter)
    }
}
