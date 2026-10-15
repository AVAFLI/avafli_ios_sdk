//
//  AvafliV2LadderTests.swift
//  AvafliSDKTests
//
//  Tests for AvafliV2Ladder.entries — the client-side mirror of the backend's
//  entry-ladder math. Explicit ladder values cover days 1..ladder.count;
//  beyond that the daily increment is the bonusEntries of the LATEST passed
//  milestone (the "+N EVERY DAY!" accelerators). No milestones → flat at the
//  ladder top. Empty ladder → fallback of 10.
//

import XCTest
@testable import AvafliSDK

final class AvafliV2LadderTests: XCTestCase {

    private let ladder = [10, 30, 60, 130, 240, 300]

    private func milestone(_ day: Int, _ bonus: Int) -> MilestoneConfigAPI {
        MilestoneConfigAPI(day: day, bonusEntries: bonus, badge: nil)
    }

    // MARK: - Explicit ladder days

    func testExplicitLadderDaysReturnLadderValues() {
        for (i, expected) in ladder.enumerated() {
            XCTAssertEqual(
                AvafliV2Ladder.entries(day: i + 1, ladder: ladder, milestones: nil),
                expected,
                "Day \(i + 1) should come straight from the ladder"
            )
        }
    }

    func testExplicitLadderDaysIgnoreMilestones() {
        // Milestones only affect days beyond the ladder.
        let ms = [milestone(2, 25)]
        for (i, expected) in ladder.enumerated() {
            XCTAssertEqual(
                AvafliV2Ladder.entries(day: i + 1, ladder: ladder, milestones: ms),
                expected
            )
        }
    }

    // MARK: - No milestones → flat at ladder top

    func testNoMilestonesFlatAtLadderTopBeyondLadder() {
        XCTAssertEqual(AvafliV2Ladder.entries(day: 7, ladder: ladder, milestones: nil), 300)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 30, ladder: ladder, milestones: nil), 300)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 365, ladder: ladder, milestones: nil), 300)
    }

    func testEmptyMilestoneArrayBehavesLikeNil() {
        XCTAssertEqual(AvafliV2Ladder.entries(day: 10, ladder: ladder, milestones: []), 300)
    }

    // MARK: - Accelerator accrual past the ladder

    func testSingleAcceleratorAccruesDaily() {
        // Milestone at day 7 (+25/day). Rate applies from the day AFTER the
        // milestone day (m.day < d is strict).
        let ms = [milestone(7, 25)]
        // Day 7: no milestone passed yet (7 < 7 is false) → flat at 300.
        XCTAssertEqual(AvafliV2Ladder.entries(day: 7, ladder: ladder, milestones: ms), 300)
        // Day 8: +25
        XCTAssertEqual(AvafliV2Ladder.entries(day: 8, ladder: ladder, milestones: ms), 325)
        // Day 9: +25 more
        XCTAssertEqual(AvafliV2Ladder.entries(day: 9, ladder: ladder, milestones: ms), 350)
        // Day 30: 300 + 23 * 25
        XCTAssertEqual(AvafliV2Ladder.entries(day: 30, ladder: ladder, milestones: ms), 300 + 23 * 25)
    }

    func testLatestPassedMilestoneWinsRate() {
        // +25/day after day 7, upgraded to +100/day after day 30.
        let ms = [milestone(7, 25), milestone(30, 100)]
        // Day 30 still accrues at 25 (30 < 30 is false): 300 + 23*25 = 875
        XCTAssertEqual(AvafliV2Ladder.entries(day: 30, ladder: ladder, milestones: ms), 875)
        // Day 31 switches to the day-30 rate: 875 + 100
        XCTAssertEqual(AvafliV2Ladder.entries(day: 31, ladder: ladder, milestones: ms), 975)
        // Day 33: 875 + 3*100
        XCTAssertEqual(AvafliV2Ladder.entries(day: 33, ladder: ladder, milestones: ms), 1175)
    }

    func testUnsortedMilestonesAreSortedInternally() {
        let sorted = [milestone(7, 25), milestone(30, 100)]
        let unsorted = [milestone(30, 100), milestone(7, 25)]
        for day in [8, 15, 30, 31, 45] {
            XCTAssertEqual(
                AvafliV2Ladder.entries(day: day, ladder: ladder, milestones: unsorted),
                AvafliV2Ladder.entries(day: day, ladder: ladder, milestones: sorted),
                "Day \(day): milestone order must not matter"
            )
        }
    }

    func testMilestoneInsideLadderRangeStartsAccrualAfterLadder() {
        // Milestone at day 3 (+5/day) with a 6-day ladder: explicit ladder values
        // win through day 6; accrual applies from day 7 onward at the day-3 rate.
        let ms = [milestone(3, 5)]
        XCTAssertEqual(AvafliV2Ladder.entries(day: 6, ladder: ladder, milestones: ms), 300)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 7, ladder: ladder, milestones: ms), 305)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 10, ladder: ladder, milestones: ms), 320)
    }

    func testMilestoneBeyondCurrentDayHasNoEffect() {
        let ms = [milestone(60, 500)]
        XCTAssertEqual(AvafliV2Ladder.entries(day: 10, ladder: ladder, milestones: ms), 300)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 60, ladder: ladder, milestones: ms), 300)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 61, ladder: ladder, milestones: ms), 800)
    }

    // MARK: - Empty-ladder fallback

    func testEmptyLadderFallsBackToTen() {
        XCTAssertEqual(AvafliV2Ladder.entries(day: 1, ladder: [], milestones: nil), 10)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 50, ladder: [], milestones: nil), 10)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 5, ladder: [], milestones: [milestone(2, 25)]), 10)
    }

    // MARK: - Single-entry ladder

    func testSingleEntryLadder() {
        let single = [40]
        XCTAssertEqual(AvafliV2Ladder.entries(day: 1, ladder: single, milestones: nil), 40)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 2, ladder: single, milestones: nil), 40)
        let ms = [milestone(1, 10)]
        // Day 2: rate from day-1 milestone applies → 40 + 10
        XCTAssertEqual(AvafliV2Ladder.entries(day: 2, ladder: single, milestones: ms), 50)
        XCTAssertEqual(AvafliV2Ladder.entries(day: 4, ladder: single, milestones: ms), 70)
    }
}
