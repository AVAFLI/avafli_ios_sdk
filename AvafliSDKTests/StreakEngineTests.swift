//
//  StreakEngineTests.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import XCTest
@testable import AvafliSDK

final class StreakEngineTests: XCTestCase {

    let engine = StreakEngine()

    // MARK: - New User

    func testNewUserStartsAtDayOne() {
        let result = engine.nextState(from: nil, on: Date())
        switch result {
        case .success(let state):
            XCTAssertEqual(state.currentDay, 1)
            XCTAssertEqual(state.totalEntriesEarned, 0)
        default:
            XCTFail("Expected success")
        }
    }

    // MARK: - Consecutive Days

    func testConsecutiveDayIncrementsStreak() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let state = StreakState(currentDay: 3, lastClaimedDate: yesterday, totalEntriesEarned: 100)
        let result = engine.nextState(from: state, on: Date())
        switch result {
        case .success(let newState):
            XCTAssertEqual(newState.currentDay, 4)
        default:
            XCTFail("Expected success")
        }
    }

    // MARK: - Missed Day Resets

    func testMissedDayResetsToOne() {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let state = StreakState(currentDay: 5, lastClaimedDate: twoDaysAgo, totalEntriesEarned: 500)
        let result = engine.nextState(from: state, on: Date())
        switch result {
        case .success(let newState):
            XCTAssertEqual(newState.currentDay, 1)
        default:
            XCTFail("Expected success, streak should reset")
        }
    }

    // MARK: - Already Claimed Today

    func testAlreadyClaimedTodayReturnsIneligible() {
        let state = StreakState(currentDay: 2, lastClaimedDate: Date(), totalEntriesEarned: 40)
        let result = engine.nextState(from: state, on: Date())
        switch result {
        case .failure(let error):
            if case .ineligibleToday = error {
                // Expected
            } else {
                XCTFail("Expected ineligibleToday error, got \(error)")
            }
        case .success:
            XCTFail("Should not succeed when already claimed today")
        }
    }

    // MARK: - Streak Cap

    func testStreakCapsAtSeven() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let state = StreakState(currentDay: 7, lastClaimedDate: yesterday, totalEntriesEarned: 770)
        let result = engine.nextState(from: state, on: Date())
        switch result {
        case .success(let newState):
            XCTAssertEqual(newState.currentDay, 7)
        default:
            XCTFail("Expected success")
        }
    }

    // MARK: - Base Entries

    func testBaseEntriesForDays() {
        XCTAssertEqual(engine.baseEntries(forDay: 1), 10)
        XCTAssertEqual(engine.baseEntries(forDay: 2), 30)
        XCTAssertEqual(engine.baseEntries(forDay: 3), 60)
        XCTAssertEqual(engine.baseEntries(forDay: 4), 130)
        XCTAssertEqual(engine.baseEntries(forDay: 5), 240)
        XCTAssertEqual(engine.baseEntries(forDay: 6), 300)
        XCTAssertEqual(engine.baseEntries(forDay: 7), 500)
    }
}
