import XCTest
@testable import AvafliSDK

// MARK: - Presentation control (3.1.4): autoOpen mode, present(), hold/release

/// The three-way auto-open mode, the server-side mode, and the "most
/// restrictive wins" rule that combines them inside the auto-open gate.
final class AvafliAutoOpenModeTests: XCTestCase {

    // MARK: Configuration surface

    /// Non-negotiable #1: with no new options set, nothing changes.
    func testConfigurationDefaultsToAlways() {
        let config = AvafliConfiguration(
            apiKey: "k",
            bundleId: "com.test",
            user: AvafliUser(id: "u1")
        )
        XCTAssertEqual(config.autoOpen, .always)
    }

    /// The pre-3.1.4 initializer shape (every argument, no `autoOpen`) must
    /// keep compiling — publishers on 3.1.3 upgrade without a source change.
    func testExistingInitializerStaysSourceCompatible() {
        let config = AvafliConfiguration(
            apiKey: "k",
            environment: .production,
            bundleId: "com.test",
            user: AvafliUser(id: "u1", firstName: "A", lastName: "B"),
            options: AvafliOptions(logging: .none)
        )
        XCTAssertEqual(config.autoOpen, .always)
    }

    func testConfigurationAcceptsEveryMode() {
        for mode in [AvafliAutoOpen.always, .returningUsersOnly, .never] {
            let config = AvafliConfiguration(
                apiKey: "k", bundleId: "com.test", user: AvafliUser(id: "u1"), autoOpen: mode
            )
            XCTAssertEqual(config.autoOpen, mode)
        }
    }

    // MARK: Server mode parsing

    func testServerModeParsesKnownValues() {
        XCTAssertEqual(AvafliAutoOpen(serverValue: "always"), .always)
        XCTAssertEqual(AvafliAutoOpen(serverValue: "returningUsersOnly"), .returningUsersOnly)
        XCTAssertEqual(AvafliAutoOpen(serverValue: "never"), .never)
    }

    /// Unknown / absent server values are ignored → `always` (the spec's
    /// forward-compat rule), never a silent lock-out.
    func testServerModeIgnoresUnknownAndAbsentValues() {
        XCTAssertEqual(AvafliAutoOpen(serverValue: nil), .always)
        XCTAssertEqual(AvafliAutoOpen(serverValue: ""), .always)
        XCTAssertEqual(AvafliAutoOpen(serverValue: "sometimes"), .always)
        XCTAssertEqual(AvafliAutoOpen(serverValue: "NEVER"), .always)
    }

    func testExperienceConfigDecodesAutoOpenMode() throws {
        let json = """
        { "autoOpenEnabled": true, "autoOpenMode": "returningUsersOnly" }
        """.data(using: .utf8)!
        let experience = try JSONDecoder().decode(ExperienceConfig.self, from: json)
        XCTAssertEqual(experience.autoOpenMode, "returningUsersOnly")
        XCTAssertEqual(experience.resolvedAutoOpenMode, .returningUsersOnly)
    }

    /// Older backends don't send the field at all — the SDK must not care.
    func testExperienceConfigWithoutAutoOpenModeResolvesToAlways() throws {
        let json = """
        { "autoOpenEnabled": true }
        """.data(using: .utf8)!
        let experience = try JSONDecoder().decode(ExperienceConfig.self, from: json)
        XCTAssertNil(experience.autoOpenMode)
        XCTAssertEqual(experience.resolvedAutoOpenMode, .always)
    }

    // MARK: Effective mode = most restrictive of (server kill switch, server mode, client mode)

    func testEffectiveModeDefaultsToAlways() {
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .always, serverEnabled: nil, serverMode: .always),
            .always
        )
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .always, serverEnabled: true, serverMode: .always),
            .always
        )
    }

    func testServerKillSwitchAlwaysWins() {
        for client in [AvafliAutoOpen.always, .returningUsersOnly, .never] {
            for server in [AvafliAutoOpen.always, .returningUsersOnly, .never] {
                XCTAssertEqual(
                    AvafliAutoOpen.effective(client: client, serverEnabled: false, serverMode: server),
                    .never,
                    "autoOpenEnabled=false must be a hard kill switch (client \(client), server \(server))"
                )
            }
        }
    }

    func testMostRestrictiveOfClientAndServerWins() {
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .returningUsersOnly, serverEnabled: true, serverMode: .always),
            .returningUsersOnly
        )
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .always, serverEnabled: true, serverMode: .returningUsersOnly),
            .returningUsersOnly
        )
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .never, serverEnabled: true, serverMode: .always),
            .never
        )
        XCTAssertEqual(
            AvafliAutoOpen.effective(client: .returningUsersOnly, serverEnabled: nil, serverMode: .never),
            .never
        )
    }

    // MARK: The mode gate inside autoPresentIfEligible

    func testAlwaysOpensForNewAndReturningUsers() {
        XCTAssertTrue(Avafli.autoOpenAllowed(mode: .always, isNewUserThisSession: true))
        XCTAssertTrue(Avafli.autoOpenAllowed(mode: .always, isNewUserThisSession: false))
    }

    func testReturningUsersOnlySkipsOnlyTheFirstSession() {
        XCTAssertFalse(Avafli.autoOpenAllowed(mode: .returningUsersOnly, isNewUserThisSession: true))
        XCTAssertTrue(Avafli.autoOpenAllowed(mode: .returningUsersOnly, isNewUserThisSession: false))
    }

    func testNeverNeverOpens() {
        XCTAssertFalse(Avafli.autoOpenAllowed(mode: .never, isNewUserThisSession: true))
        XCTAssertFalse(Avafli.autoOpenAllowed(mode: .never, isNewUserThisSession: false))
    }

    // MARK: isNewUser on the register response

    func testRegisterDeviceResponseDecodesIsNewUser() throws {
        let json = """
        { "token": "t", "refreshToken": "r", "uuid": "u", "isNewUser": true }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertEqual(response.isNewUser, true)
    }

    /// An older backend omits the flag → treated as returning (auto-open).
    func testRegisterDeviceResponseWithoutIsNewUserIsReturning() throws {
        let json = """
        { "token": "t", "refreshToken": "r", "uuid": "u" }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(RegisterDeviceResponse.self, from: json)
        XCTAssertNil(response.isNewUser)
        XCTAssertTrue(Avafli.autoOpenAllowed(mode: .returningUsersOnly, isNewUserThisSession: response.isNewUser == true))
    }
}

/// `Avafli.present()`, `holdAutoOpen()` / `releaseAutoOpen()` and the
/// non-negotiable that registration runs on `configure()` in every mode.
final class AvafliPresentationControlTests: XCTestCase {

    override func tearDown() {
        Avafli._setRegistrationOverrideForTests(nil)
        Avafli._resetPresentationStateForTests()
        super.tearDown()
    }

    private func makeConfig(autoOpen: AvafliAutoOpen) -> AvafliConfiguration {
        AvafliConfiguration(
            apiKey: "avafli_test_presentation",
            bundleId: "com.avafli.tests.presentation",
            user: AvafliUser(id: "u-presentation"),
            options: AvafliOptions(logging: .none, analyticsAdapter: nil, enablePushReminders: false),
            autoOpen: autoOpen
        )
    }

    // MARK: Hold / release

    func testHoldAndReleaseBeforeConfigureAreSafeAndIdempotent() {
        Avafli._resetPresentationStateForTests()
        XCTAssertFalse(Avafli._isAutoOpenHeldForTests())

        Avafli.holdAutoOpen()
        Avafli.holdAutoOpen()
        XCTAssertTrue(Avafli._isAutoOpenHeldForTests())

        Avafli.releaseAutoOpen()
        Avafli.releaseAutoOpen()
        XCTAssertFalse(Avafli._isAutoOpenHeldForTests())
    }

    /// A hold set before `configure()` must survive it — the whole point is
    /// "hold during boot, release once the main screen is up".
    func testConfigureDoesNotClearAHold() async {
        Avafli._setRegistrationOverrideForTests { _ in }
        Avafli.holdAutoOpen()

        Avafli.configure(makeConfig(autoOpen: .always))
        await Avafli._awaitRegistrationForTests()

        XCTAssertTrue(Avafli._isAutoOpenHeldForTests())
        Avafli.releaseAutoOpen()
        XCTAssertFalse(Avafli._isAutoOpenHeldForTests())
    }

    // MARK: Non-negotiable #2: tracking is unaffected by the presentation mode

    /// `registerDevice` (lastSeenAt / sdk_version / platform → DAU/MAU) must
    /// still run inside `configure()` when the publisher opts out of auto-open.
    func testNeverModeStillRegistersOnConfigure() async {
        let registered = expectation(description: "registration ran on configure")
        var seenMode: AvafliAutoOpen?
        Avafli._setRegistrationOverrideForTests { configuration in
            seenMode = configuration.autoOpen
            registered.fulfill()
        }

        Avafli.configure(makeConfig(autoOpen: .never))

        await fulfillment(of: [registered], timeout: 5)
        XCTAssertEqual(seenMode, .never)
    }

    func testReturningUsersOnlyModeStillRegistersOnConfigure() async {
        let registered = expectation(description: "registration ran on configure")
        Avafli._setRegistrationOverrideForTests { _ in registered.fulfill() }

        Avafli.configure(makeConfig(autoOpen: .returningUsersOnly))

        await fulfillment(of: [registered], timeout: 5)
    }

    // MARK: present()

    func testPresentBeforeConfigureFailsWithNotConfigured() {
        Avafli._resetPresentationStateForTests()
        var result: Result<DailyEntryGrant, AvafliError>?
        let accepted = Avafli.present { result = $0 }
        XCTAssertFalse(accepted)
        guard case .failure(.notConfigured)? = result else {
            return XCTFail("Expected .notConfigured, got \(String(describing: result))")
        }
    }

    /// While registration is in flight `present()` must WAIT for it (never
    /// race registerDevice) and then decide. Here registration settles with
    /// no giveaway, so the deferred decision is a clean `giveawayNotActive`
    /// on the completion — never a throw to the host.
    func testPresentDuringRegistrationWaitsThenReportsNoGiveaway() async {
        let gate = AsyncGate()
        let registrationStarted = expectation(description: "registration started")
        Avafli._setRegistrationOverrideForTests { _ in
            registrationStarted.fulfill()
            await gate.wait()
        }
        Avafli.configure(makeConfig(autoOpen: .never))
        await fulfillment(of: [registrationStarted], timeout: 5)

        let completed = expectation(description: "present completion")
        var result: Result<DailyEntryGrant, AvafliError>?
        let accepted = Avafli.present { r in
            result = r
            completed.fulfill()
        }
        XCTAssertTrue(accepted, "present() during registration is accepted and deferred, not refused")
        XCTAssertNil(result, "must not decide before registration settles")

        await gate.open()
        await fulfillment(of: [completed], timeout: 5)
        guard case .failure(.giveawayNotActive)? = result else {
            return XCTFail("Expected .giveawayNotActive, got \(String(describing: result))")
        }
    }

    /// After a boot with no giveaway cached (registration failed / nothing
    /// running), `present()` is a logged no-op that resolves false.
    func testPresentWithoutGiveawayIsANoOp() async {
        Avafli._setRegistrationOverrideForTests { _ in }
        Avafli.configure(makeConfig(autoOpen: .never))
        await Avafli._awaitRegistrationForTests()

        var result: Result<DailyEntryGrant, AvafliError>?
        let accepted = Avafli.present { result = $0 }
        XCTAssertFalse(accepted)
        guard case .failure(.giveawayNotActive)? = result else {
            return XCTFail("Expected .giveawayNotActive, got \(String(describing: result))")
        }
    }
}

/// A one-shot latch a test can hold an async step on, then open.
private actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
