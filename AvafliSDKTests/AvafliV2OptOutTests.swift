//
//  AvafliV2OptOutTests.swift
//  AvafliSDKTests
//
//  The in-experience privacy opt-out (since 2.9.4 raised by the privacy
//  webview's winr://delete bridge; the confirmation renders at the experience
//  root): the AvafliV2OptOutCoordinator state machine, with the network action
//  stubbed.
//
//      idle → confirming → inFlight → done → dismiss whole experience
//                      ↘ failed (inline error, retryable) ↗
//

import XCTest
@testable import AvafliSDK

@MainActor
final class AvafliV2OptOutTests: XCTestCase {

    /// Reference box so the stubbed action can count invocations.
    private final class Counter { var value = 0 }

    private func makeCoordinator(
        succeed: Bool,
        dismissed: XCTestExpectation? = nil,
        attempts: Counter? = nil
    ) -> AvafliV2OptOutCoordinator {
        AvafliV2OptOutCoordinator(
            successHold: 0.05,
            action: {
                attempts?.value += 1
                if !succeed { throw AvafliError.serviceUnavailable }
            },
            dismissExperience: { dismissed?.fulfill() }
        )
    }

    // MARK: - Raising / cancelling the confirmation

    func testBeginRaisesConfirmationFromIdleOnly() {
        let coordinator = makeCoordinator(succeed: true)
        XCTAssertEqual(coordinator.phase, .idle)
        coordinator.begin()
        XCTAssertEqual(coordinator.phase, .confirming)
        // begin() while already confirming is a no-op.
        coordinator.begin()
        XCTAssertEqual(coordinator.phase, .confirming)
    }

    func testCancelReturnsToIdleFromConfirming() {
        let coordinator = makeCoordinator(succeed: true)
        coordinator.begin()
        coordinator.cancel()
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: - Confirm → success → dismiss

    func testConfirmSuccessShowsDeletedThenDismissesExperience() async {
        let dismissed = expectation(description: "whole experience dismissed")
        let coordinator = makeCoordinator(succeed: true, dismissed: dismissed)
        coordinator.begin()
        coordinator.confirm()
        // In flight immediately (synchronous transition).
        XCTAssertEqual(coordinator.phase, .inFlight)

        await fulfillment(of: [dismissed], timeout: 2.0)
        // The success state was reached (and held) before the dismiss fired.
        XCTAssertEqual(coordinator.phase, .done)
    }

    func testConfirmFromIdleIsANoOp() {
        let coordinator = makeCoordinator(succeed: true)
        coordinator.confirm()
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: - Confirm → failure → retryable, never pretends success

    func testConfirmFailureShowsErrorAndStaysRetryable() async {
        let attempts = Counter()
        let coordinator = makeCoordinator(succeed: false, attempts: attempts)
        coordinator.begin()
        coordinator.confirm()

        // Wait for the failure to land.
        for _ in 0..<50 where coordinator.phase == .inFlight {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(coordinator.phase, .failed(AvafliV2Strings.optOutFailed))
        XCTAssertEqual(attempts.value, 1)

        // The destructive button remains live: confirm() retries from .failed.
        coordinator.confirm()
        XCTAssertEqual(coordinator.phase, .inFlight)
    }

    func testCancelAfterFailureReturnsToIdle() async {
        let coordinator = makeCoordinator(succeed: false)
        coordinator.begin()
        coordinator.confirm()
        for _ in 0..<50 where coordinator.phase == .inFlight {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        coordinator.cancel()
        XCTAssertEqual(coordinator.phase, .idle)
    }

    // MARK: - Mandated copy

    func testOptOutStringsMatchSpec() {
        XCTAssertEqual(AvafliV2Strings.optOutTitle, "Delete my data & stop participating")
        XCTAssertEqual(
            AvafliV2Strings.optOutBody,
            // 3.2.0: deletion blocks for 24 hours, not forever.
            "This permanently erases your information and ends your participation. Entries and streaks are forfeited and cannot be restored. You can join again as a new participant after 24 hours."
        )
        XCTAssertEqual(AvafliV2Strings.optOutConfirm, "DELETE MY DATA")
        XCTAssertEqual(AvafliV2Strings.optOutSuccess, "Your data has been deleted.")
        XCTAssertEqual(
            AvafliV2Strings.optOutFailed,
            "Something went wrong. Please check your connection and try again."
        )
    }
}
