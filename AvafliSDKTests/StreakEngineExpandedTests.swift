import XCTest
@testable import AvafliSDK

final class StreakEngineExpandedTests: XCTestCase {

    let engine = StreakEngine()

    // MARK: - Helper

    private func date(_ string: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: string)!
    }

    // MARK: - Weekly streak tracking (weeks are Monday-based, UTC)

    func testWeeklyStreakIncrementsWithinSameWeek() {
        // Tue Feb 17 2026 → Wed Feb 18 2026 (same Monday-based week of Feb 16)
        let tuesday = date("2026-02-17 10:00")
        let wednesday = date("2026-02-18 10:00")
        let mondayStr = "2026-02-16"

        let state = StreakState(
            currentDay: 2,
            lastClaimedDate: tuesday,
            totalEntriesEarned: 40,
            weeklyCurrent: 2,
            weeklyStart: mondayStr,
            monthlyCurrent: 2,
            monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: wednesday)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.weeklyCurrent, 3)
            XCTAssertEqual(newState.weeklyStart, mondayStr)
        } else {
            XCTFail("Expected success")
        }
    }

    func testWeeklyStreakResetsOnNewWeek() {
        // Sun Feb 22 2026 (last day of the Feb 16 week) → Mon Feb 23 2026 (new week)
        let sunday = date("2026-02-22 10:00")
        let monday = date("2026-02-23 10:00")

        let state = StreakState(
            currentDay: 5,
            lastClaimedDate: sunday,
            totalEntriesEarned: 100,
            weeklyCurrent: 7,
            weeklyStart: "2026-02-16",
            monthlyCurrent: 10,
            monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: monday)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.weeklyCurrent, 1)
            XCTAssertEqual(newState.weeklyStart, "2026-02-23")
        } else {
            XCTFail("Expected success")
        }
    }

    func testSaturdayAndSundayAreSameWeek() {
        // Sat Feb 21 and Sun Feb 22 both belong to the Monday Feb 16 week.
        let saturday = date("2026-02-21 10:00")
        let sunday = date("2026-02-22 10:00")

        let state = StreakState(
            currentDay: 3, lastClaimedDate: saturday, totalEntriesEarned: 10,
            weeklyCurrent: 6, weeklyStart: "2026-02-16",
            monthlyCurrent: 15, monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: sunday)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.weeklyCurrent, 7, "Sunday continues the Monday-based week")
            XCTAssertEqual(newState.weeklyStart, "2026-02-16")
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - Monthly streak tracking

    func testMonthlyStreakIncrementsWithinSameMonth() {
        let day1 = date("2026-02-10 10:00")
        let day2 = date("2026-02-11 10:00")

        let state = StreakState(
            currentDay: 1,
            lastClaimedDate: day1,
            totalEntriesEarned: 10,
            weeklyCurrent: 1,
            weeklyStart: "2026-02-09",
            monthlyCurrent: 3,
            monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: day2)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.monthlyCurrent, 4)
            XCTAssertEqual(newState.monthlyStart, "2026-02-01")
        } else {
            XCTFail("Expected success")
        }
    }

    func testMonthlyStreakResetsOnNewMonth() {
        let lastDay = date("2026-02-28 10:00")
        let firstDay = date("2026-03-01 10:00")

        let state = StreakState(
            currentDay: 1,
            lastClaimedDate: lastDay,
            totalEntriesEarned: 500,
            weeklyCurrent: 3,
            weeklyStart: "2026-02-23",
            monthlyCurrent: 20,
            monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: firstDay)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.monthlyCurrent, 1)
            XCTAssertEqual(newState.monthlyStart, "2026-03-01")
        } else {
            XCTFail("Expected success")
        }
    }

    func testMonthlyStreakIncrementsEvenWhenDailyStreakBreaks() {
        // Monthly counts unique claim days, independent of the daily streak.
        let day1 = date("2026-02-10 10:00")
        let day2 = date("2026-02-14 10:00") // 4-day gap breaks the daily streak

        let state = StreakState(
            currentDay: 5,
            lastClaimedDate: day1,
            totalEntriesEarned: 400,
            weeklyCurrent: 2,
            weeklyStart: "2026-02-09",
            monthlyCurrent: 8,
            monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: day2)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.currentDay, 1, "Daily streak resets on the gap")
            XCTAssertEqual(newState.monthlyCurrent, 9, "Monthly still increments")
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - Daily streak caps at 7

    func testDailyStreakCapsAtSeven() {
        let day6 = date("2026-02-10 10:00")
        let day7 = date("2026-02-11 10:00")
        let state6 = StreakState(currentDay: 6, lastClaimedDate: day6, totalEntriesEarned: 770)
        guard case .success(let state7) = engine.nextState(from: state6, on: day7) else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(state7.currentDay, 7)

        // Claiming again the next consecutive day stays capped at 7.
        let day8 = date("2026-02-12 10:00")
        guard case .success(let state8) = engine.nextState(from: state7, on: day8) else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(state8.currentDay, 7)
    }

    // MARK: - Nil lastClaimedDate treated like new user

    func testNilLastClaimedDateResetsToDay1() {
        let state = StreakState(currentDay: 5, lastClaimedDate: nil, totalEntriesEarned: 200)
        let result = engine.nextState(from: state, on: Date())
        if case .success(let newState) = result {
            XCTAssertEqual(newState.currentDay, 1)
            XCTAssertEqual(newState.totalEntriesEarned, 200, "Earned total is preserved")
        } else {
            XCTFail("Expected success")
        }
    }

    func testNilLastClaimedDateIncrementsLifetime() {
        let state = StreakState(currentDay: 5, lastClaimedDate: nil, totalEntriesEarned: 200, lifetimeCount: 9)
        let result = engine.nextState(from: state, on: Date())
        if case .success(let newState) = result {
            XCTAssertEqual(newState.lifetimeCount, 10)
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - Lifetime count never resets

    func testLifetimeCountAlwaysIncrements() {
        let day1 = date("2026-02-10 10:00")
        let day2 = date("2026-02-20 10:00") // big gap: everything else resets

        let state = StreakState(
            currentDay: 7, lastClaimedDate: day1, totalEntriesEarned: 999,
            weeklyCurrent: 5, weeklyStart: "2026-02-09",
            monthlyCurrent: 9, monthlyStart: "2026-02-01",
            lifetimeCount: 42
        )

        let result = engine.nextState(from: state, on: day2)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.lifetimeCount, 43)
            XCTAssertEqual(newState.currentDay, 1)
        } else {
            XCTFail("Expected success")
        }
    }

    // MARK: - Base entries for out-of-range day

    func testBaseEntriesForDayOutOfRange() {
        XCTAssertEqual(engine.baseEntries(forDay: 0), 60)   // default
        XCTAssertEqual(engine.baseEntries(forDay: 8), 60)   // default
        XCTAssertEqual(engine.baseEntries(forDay: 100), 60)
    }

    // MARK: - Streak ladder values

    func testStreakLadderMatchesExpectedProgression() {
        let expected = [10, 30, 60, 130, 240, 300, 500]
        for (i, val) in expected.enumerated() {
            XCTAssertEqual(engine.baseEntries(forDay: i + 1), val, "Day \(i + 1) mismatch")
        }
    }

    // MARK: - Multi-day gap resets both daily and weekly

    func testThreeDayGapResetsDailyAndWeekly() {
        // Wed → Sat within the same week: the daily streak breaks, and the
        // weekly counter only advances while the daily streak is alive.
        let wed = date("2026-02-18 10:00")
        let sat = date("2026-02-21 10:00")

        let state = StreakState(
            currentDay: 4, lastClaimedDate: wed, totalEntriesEarned: 200,
            weeklyCurrent: 3, weeklyStart: "2026-02-16",
            monthlyCurrent: 10, monthlyStart: "2026-02-01"
        )

        let result = engine.nextState(from: state, on: sat)
        if case .success(let newState) = result {
            XCTAssertEqual(newState.currentDay, 1, "Daily streak should reset on gap > 1 day")
            XCTAssertEqual(newState.weeklyCurrent, 1, "Weekly resets when the daily streak breaks")
            XCTAssertEqual(newState.monthlyCurrent, 11, "Monthly is independent and still increments")
        } else {
            XCTFail("Expected success")
        }
    }
}
