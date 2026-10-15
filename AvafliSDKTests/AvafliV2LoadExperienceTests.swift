//
//  AvafliV2LoadExperienceTests.swift
//  AvafliSDKTests
//
//  The 2.3.3 "load experience" behaviours:
//
//  1. AvafliV2CacheRender.canHydrate — whether the drawer may paint the real
//     dashboard from cache on its first frame, or must fall back to the
//     cold-start skeleton. The email gate is the load-bearing rule: an
//     unconsented user must NEVER see a cached dashboard.
//  2. AvafliV2ImageWarmer — prewarming the publisher's remote art. A repeated
//     refresh is a no-op; a failed URL is dropped so the next refresh retries.
//

import XCTest
import UIKit
@testable import AvafliSDK

final class AvafliV2CacheRenderTests: XCTestCase {

    private func giveaway(ladder: [Int] = [10, 30, 60]) -> GiveawayConfig {
        GiveawayConfig(
            id: "g1",
            title: "Giveaway",
            prizeDescription: "Cash",
            prizeValue: 1000,
            streakLadder: ladder,
            doublingEnabled: false,
            maxDailyBaseEntries: 60,
            rulesUrl: "https://example.com/rules",
            startDate: "2026-08-01",
            endDate: "2026-08-31",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 1,
                monthlyResetDay: 1,
                weeklyBonusThreshold: nil,
                weeklyBonusEntries: nil,
                monthlyBonusThreshold: nil,
                monthlyBonusEntries: nil,
                monthlyMilestones: nil
            ),
            prizeImageUrl: "https://cdn.example.com/prize.png"
        )
    }

    private func streak(day: Int = 3) -> StreakState {
        StreakState(currentDay: day, totalEntriesEarned: 100)
    }

    // MARK: - The warm path

    func testHydratesWhenGiveawayStreakAndConsentAllPresent() {
        XCTAssertTrue(AvafliV2CacheRender.canHydrate(
            giveaway: giveaway(),
            streak: streak(),
            hasEmailConsent: true,
            isLoading: true
        ))
    }

    // MARK: - A parked cross-device link owns the open (Sept 2026)

    func testParkedLinkNeverHydratesTheDashboardEvenWhenWarmAndConsented() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: giveaway(),
            streak: streak(),
            hasEmailConsent: true,
            isLoading: true,
            adoptionPending: true
        ))
    }

    // MARK: - Bail-outs (the skeleton stays up)

    func testNoCachedGiveawayFallsBackToSkeleton() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: nil,
            streak: streak(),
            hasEmailConsent: true,
            isLoading: true
        ))
    }

    func testNoPersistedStreakFallsBackToSkeleton() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: giveaway(),
            streak: nil,
            hasEmailConsent: true,
            isLoading: true
        ))
    }

    /// The email gate: a fully cached device whose user has NOT consented must
    /// still land on email capture, never on a dashboard.
    func testUnconsentedUserNeverSeesCachedDashboard() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: giveaway(),
            streak: streak(),
            hasEmailConsent: false,
            isLoading: true
        ))
    }

    /// A fresh network response already resolved the phase — never stomp
    /// fresher truth with cached values.
    func testResolvedPhaseIsNeverOverwrittenByCache() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: giveaway(),
            streak: streak(),
            hasEmailConsent: true,
            isLoading: false
        ))
    }

    /// Everything missing at once (a genuine first-ever open).
    func testColdStartFallsBackToSkeleton() {
        XCTAssertFalse(AvafliV2CacheRender.canHydrate(
            giveaway: nil,
            streak: nil,
            hasEmailConsent: false,
            isLoading: true
        ))
    }
}

final class AvafliV2SkeletonPulseTests: XCTestCase {

    /// The cold-start skeleton breathes between 0.45 and 0.85. It is driven off
    /// the timeline rather than an implicit `repeatForever` animation, which
    /// freezes on its target value inside the drawer's slide-up transaction.
    func testPulseStaysWithinTheDesignedOpacityRange() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        for step in 0...180 {
            let o = AvafliV2LoadingView.pulseOpacity(at: base.addingTimeInterval(Double(step) * 0.01))
            XCTAssertGreaterThanOrEqual(o, 0.45 - 0.0001)
            XCTAssertLessThanOrEqual(o, 0.85 + 0.0001)
        }
    }

    func testPulseReachesBothExtremesWithinOneCycle() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        var minimum = 1.0
        var maximum = 0.0
        for step in 0...180 {
            let o = AvafliV2LoadingView.pulseOpacity(at: base.addingTimeInterval(Double(step) * 0.01))
            minimum = min(minimum, o)
            maximum = max(maximum, o)
        }
        XCTAssertEqual(minimum, 0.45, accuracy: 0.01)
        XCTAssertEqual(maximum, 0.85, accuracy: 0.01)
    }

    /// One breath is 1.8s (0.9s in each direction), so the opacity repeats.
    func testPulseRepeatsEveryFullCycle() {
        let base = Date(timeIntervalSinceReferenceDate: 12.34)
        XCTAssertEqual(
            AvafliV2LoadingView.pulseOpacity(at: base),
            AvafliV2LoadingView.pulseOpacity(at: base.addingTimeInterval(1.8)),
            accuracy: 0.0001
        )
    }

    /// It must actually move — a still skeleton is the bug this replaced.
    func testPulseMovesAcrossAHalfPeriod() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let a = AvafliV2LoadingView.pulseOpacity(at: base)
        let b = AvafliV2LoadingView.pulseOpacity(at: base.addingTimeInterval(0.9))
        XCTAssertGreaterThan(abs(a - b), 0.3)
    }
}

final class AvafliV2ImageWarmerTests: XCTestCase {

    private let url = "https://cdn.example.com/prize.png"
    private let other = "https://cdn.example.com/logo.png"

    override func setUp() {
        super.setUp()
        AvafliV2ImageWarmer.resetForTesting()
    }

    override func tearDown() {
        AvafliV2ImageWarmer.resetForTesting()
        super.tearDown()
    }

    private func stubImage() -> UIImage {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    /// Installs a fetch that always succeeds, counting calls per URL.
    private func succeedingFetch(_ counter: @escaping (String) -> Void) {
        let image = stubImage()
        AvafliV2ImageWarmer.fetch = { url, completion in
            counter(url)
            completion(image)
        }
    }

    // MARK: - Warm once, then no-op

    func testPrewarmDecodesAndCachesTheImage() {
        var calls: [String] = []
        succeedingFetch { calls.append($0) }

        AvafliV2ImageWarmer.prewarm(url)

        XCTAssertEqual(calls, [url])
        XCTAssertTrue(AvafliV2ImageWarmer.isWarmed(url))
        XCTAssertNotNil(AvafliV2ImageWarmer.cached(url), "A warmed URL must be readable synchronously")
    }

    func testRepeatedRefreshIsANoOp() {
        var calls: [String] = []
        succeedingFetch { calls.append($0) }

        AvafliV2ImageWarmer.prewarm(url)
        AvafliV2ImageWarmer.prewarm(url)
        AvafliV2ImageWarmer.prewarm(url)

        XCTAssertEqual(calls, [url], "Every giveaway refresh must not re-download warmed art")
    }

    func testDistinctURLsAreWarmedIndependently() {
        var calls: [String] = []
        succeedingFetch { calls.append($0) }

        AvafliV2ImageWarmer.prewarm(url)
        AvafliV2ImageWarmer.prewarm(other)

        XCTAssertEqual(Set(calls), [url, other])
    }

    // MARK: - Failures retry

    func testFailedURLIsDroppedSoTheNextRefreshRetries() {
        var calls = 0
        AvafliV2ImageWarmer.fetch = { _, completion in
            calls += 1
            completion(nil)
        }

        AvafliV2ImageWarmer.prewarm(url)
        XCTAssertFalse(AvafliV2ImageWarmer.isWarmed(url), "A failed URL must not stay marked as warmed")
        XCTAssertNil(AvafliV2ImageWarmer.cached(url))

        AvafliV2ImageWarmer.prewarm(url)
        XCTAssertEqual(calls, 2, "The next refresh must retry a URL that failed")
    }

    // MARK: - Nothing to warm

    func testNilEmptyAndUnparseableURLsAreIgnored() {
        var calls = 0
        succeedingFetch { _ in calls += 1 }

        AvafliV2ImageWarmer.prewarm(nil)
        AvafliV2ImageWarmer.prewarm("")

        XCTAssertEqual(calls, 0)
    }

    // MARK: - Display-time load

    func testLoadReturnsTheWarmedImageSynchronously() {
        succeedingFetch { _ in }
        AvafliV2ImageWarmer.prewarm(url)

        var delivered: UIImage?
        var wasSynchronous = false
        var finished = false
        AvafliV2ImageWarmer.load(url) { image in
            delivered = image
            wasSynchronous = !finished
        }
        finished = true

        XCTAssertNotNil(delivered)
        XCTAssertTrue(wasSynchronous, "A cache hit must paint on the first frame, not a frame later")
    }
}

final class AvafliV2EmailConsentCacheTests: XCTestCase {

    override func tearDown() {
        Avafli._resetEmailConsentForTests()
        super.tearDown()
    }

    /// The cached consent flag is otherwise only refreshed by
    /// getActiveGiveaway; a successful submit must record it immediately so the
    /// auto-present engine can't treat a just-registered user as unregistered.
    func testMarkEmailConsentGrantedSetsTheCachedFlag() {
        Avafli._resetEmailConsentForTests()
        XCTAssertNil(Avafli._cachedEmailConsentForTests())

        Avafli.markEmailConsentGranted()

        XCTAssertEqual(Avafli._cachedEmailConsentForTests(), true)
    }
}
