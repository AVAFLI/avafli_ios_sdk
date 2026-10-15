//
//  AvafliV2KeyboardAvoidanceTests.swift
//  AvafliSDKTests
//
//  Logic-level tests for the keyboard machinery every input screen shares:
//  the inset (overlap) math behind `.avafliKeyboardAvoiding()`, the shared
//  scroll-to-field delay, and the iOS 15 keyboard-dismiss configurator's
//  scroll-view resolution.
//

import XCTest
import UIKit
@testable import AvafliSDK

final class AvafliV2KeyboardAvoidanceTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 390, height: 844)

    // MARK: - Inset (overlap) math

    /// Docked keyboard: the padding equals exactly the covered strip.
    func testDockedKeyboardOverlapEqualsKeyboardHeight() {
        let keyboard = CGRect(x: 0, y: 844 - 336, width: 390, height: 336)
        XCTAssertEqual(
            AvafliKeyboardObserver.overlap(keyboardFrame: keyboard, screenBounds: screen),
            336
        )
    }

    /// Hidden keyboard reports an off-screen end frame (minY == screen maxY):
    /// the inset must collapse to 0 — no blank gap left behind after dismissal.
    func testHiddenKeyboardFrameYieldsZeroOverlap() {
        let keyboard = CGRect(x: 0, y: 844, width: 390, height: 336)
        XCTAssertEqual(
            AvafliKeyboardObserver.overlap(keyboardFrame: keyboard, screenBounds: screen),
            0
        )
    }

    /// A frame fully below the screen (some transitions report minY beyond
    /// maxY) must clamp at 0, never go negative (a negative padding would
    /// corrupt the layout).
    func testOffscreenKeyboardFrameClampsAtZero() {
        let keyboard = CGRect(x: 0, y: 900, width: 390, height: 336)
        XCTAssertEqual(
            AvafliKeyboardObserver.overlap(keyboardFrame: keyboard, screenBounds: screen),
            0
        )
    }

    /// Mid-transition (interactive drag-to-dismiss) frames overlap partially:
    /// the inset tracks just the still-covered strip.
    func testPartiallyDismissedKeyboardYieldsPartialOverlap() {
        let keyboard = CGRect(x: 0, y: 844 - 120, width: 390, height: 336)
        XCTAssertEqual(
            AvafliKeyboardObserver.overlap(keyboardFrame: keyboard, screenBounds: screen),
            120
        )
    }

    // MARK: - Scroll-to-field delay

    /// The shared focus-scroll delay must stay in the "keyboard padding has
    /// landed but still feels immediate" band. Guards accidental edits.
    func testFocusScrollDelayIsShortButNonZero() {
        XCTAssertGreaterThan(AvafliKeyboardScroll.focusScrollDelay, 0)
        XCTAssertLessThanOrEqual(AvafliKeyboardScroll.focusScrollDelay, 0.5)
    }

    // MARK: - iOS 15 dismiss configurator resolution

    /// The probe finds a sibling scroll view through the shared ancestor and
    /// flips it to interactive dismissal.
    func testConfiguratorSetsInteractiveDismissOnSiblingScrollView() {
        let container = UIView()
        let scrollView = UIScrollView()
        let probe = UIView()
        container.addSubview(scrollView)
        container.addSubview(probe)
        XCTAssertEqual(scrollView.keyboardDismissMode, .none)

        AvafliScrollKeyboardDismissConfigurator.configureNearestScrollView(from: probe)

        XCTAssertEqual(scrollView.keyboardDismissMode, .interactive)
    }

    /// The NEAREST scroll view wins — a distant (host-app-level) scroll view
    /// higher in the hierarchy is left untouched.
    func testConfiguratorPrefersNearestScrollView() {
        let hostScroll = UIScrollView()
        let container = UIView()
        let nearScroll = UIScrollView()
        let probe = UIView()
        hostScroll.addSubview(container)
        container.addSubview(nearScroll)
        container.addSubview(probe)

        AvafliScrollKeyboardDismissConfigurator.configureNearestScrollView(from: probe)

        XCTAssertEqual(nearScroll.keyboardDismissMode, .interactive)
        XCTAssertEqual(hostScroll.keyboardDismissMode, .none)
    }

    /// No scroll view anywhere: the walk terminates without touching anything
    /// (bounded ancestor hops — no runaway traversal).
    func testConfiguratorNoScrollViewIsHarmless() {
        let container = UIView()
        let probe = UIView()
        container.addSubview(probe)

        AvafliScrollKeyboardDismissConfigurator.configureNearestScrollView(from: probe)
        // Nothing to assert beyond "did not crash / did not hang".
    }
}
