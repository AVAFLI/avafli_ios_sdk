//
//  ClaimVerificationTests.swift
//  AvafliSDKTests
//
//  3.2.0 — the six-digit email-ownership code before the prize-claim form.
//
//  1. Wire contract: the `prizeClaim.verification` block, the two new
//     callables, `supportsClaimVerification` on the claim submit, and the
//     callable error `details` reaching the claim flow (and ONLY the claim
//     flow — every other caller sees the errors it always has).
//  2. The flow itself, driven through the real view model over a stubbed
//     network: which screen CONTINUE opens, the idempotent send, the resend
//     countdown, every failure's next action, and resuming from server state.
//

import XCTest
import Combine
import SwiftUI
import UIKit
@testable import AvafliSDK

// MARK: - Wire contract

final class ClaimVerificationContractTests: XCTestCase {

    private func block(_ verification: String?) throws -> PrizeClaimBlock {
        let extra = verification.map { ", \"verification\": \($0)" } ?? ""
        let json = """
        {
            "status": "pending",
            "giveawayId": "gw_123",
            "prizeDescription": "Cash Prize",
            "prizeValue": 1000,
            "maskedEmail": "d********r@example.com"\(extra)
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PrizeClaimBlock.self, from: json)
    }

    func testBlockWithoutVerificationDecodesAsBefore() throws {
        let claim = try block(nil)
        XCTAssertNil(claim.verification)
        XCTAssertTrue(claim.isPending)
    }

    func testVerificationNotRequiredDecodes() throws {
        let claim = try block(#"{ "required": false }"#)
        XCTAssertEqual(claim.verification, ClaimVerificationBlock(required: false))
    }

    func testVerificationWithLiveCodeDecodes() throws {
        let claim = try block("""
        {
            "required": true,
            "codeSentAt": "2026-09-29T12:00:00.000Z",
            "codeExpiresAt": "2026-09-29T12:10:00.000Z",
            "resendAvailableAt": "2026-09-29T12:01:00.000Z"
        }
        """)
        XCTAssertEqual(claim.verification?.required, true)
        XCTAssertEqual(claim.verification?.codeSentAt, "2026-09-29T12:00:00.000Z")
        XCTAssertEqual(claim.verification?.codeExpiresAt, "2026-09-29T12:10:00.000Z")
        XCTAssertEqual(claim.verification?.resendAvailableAt, "2026-09-29T12:01:00.000Z")
    }

    /// A shape this build doesn't understand must degrade to "no block"
    /// (today's flow), never fail the whole giveaway response.
    func testMalformedVerificationDegradesToAbsent() throws {
        XCTAssertNil(try block(#""yes""#).verification)
        XCTAssertNil(try block(#"{ "codeSentAt": "2026-09-29T12:00:00Z" }"#).verification)
    }

    private func data(of body: Data?) throws -> [String: Any] {
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        return try XCTUnwrap(envelope["data"] as? [String: Any])
    }

    func testSendRequestOmitsResendUnlessAsked() throws {
        let open = SendClaimVerificationCodeRequest(giveawayId: "gw_123")
        XCTAssertEqual(open.path, "sendClaimVerificationCode")
        XCTAssertEqual(open.method, "POST")
        let openData = try data(of: open.body)
        XCTAssertEqual(openData["giveawayId"] as? String, "gw_123")
        XCTAssertNil(openData["resend"])

        let resend = SendClaimVerificationCodeRequest(giveawayId: "gw_123", resend: true)
        XCTAssertEqual(try data(of: resend.body)["resend"] as? Bool, true)
    }

    func testSendResponseDecodes() throws {
        let json = #"{ "sent": true, "verification": { "required": true, "codeSentAt": "2026-09-29T12:00:00Z" } }"#
        let response = try JSONDecoder().decode(SendClaimVerificationCodeResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.sent)
        XCTAssertEqual(response.verification?.required, true)
    }

    func testConfirmRequestAndResponse() throws {
        let request = ConfirmClaimVerificationCodeRequest(giveawayId: "gw_123", code: "123456")
        XCTAssertEqual(request.path, "confirmClaimVerificationCode")
        let body = try data(of: request.body)
        XCTAssertEqual(body["giveawayId"] as? String, "gw_123")
        XCTAssertEqual(body["code"] as? String, "123456")

        let json = #"{ "verified": true, "verification": { "required": false } }"#
        let response = try JSONDecoder().decode(ConfirmClaimVerificationCodeResponse.self, from: Data(json.utf8))
        XCTAssertTrue(response.verified)
        XCTAssertEqual(response.verification, ClaimVerificationBlock(required: false))
    }

    func testSubmitPrizeClaimDeclaresSupportForTheStep() throws {
        let request = SubmitPrizeClaimRequest(
            giveawayId: "gw_123", firstName: "Catherine", lastName: "Cinosta", phone: nil,
            street: "5 Haide Pl.", apt: nil, city: "Brooklyn", state: "New York", zip: "11737",
            country: "United States", photoBase64: nil, promoConsentGranted: false
        )
        XCTAssertEqual(try data(of: request.body)["supportsClaimVerification"] as? Bool, true)
    }

    // MARK: Copy (verbatim)

    func testCodeScreenCopy() {
        XCTAssertEqual(
            AvafliV2Strings.claimCodeSubtitle(maskedEmail: "d********r@example.com"),
            "Enter the 6-digit code we sent to d********r@example.com"
        )
        XCTAssertEqual(
            AvafliV2Strings.claimCodeSubtitle(maskedEmail: nil),
            "Enter the 6-digit code we sent to your email"
        )
        XCTAssertEqual(AvafliV2Strings.claimCodeSending, "Sending your code…")
        XCTAssertEqual(AvafliV2Strings.claimCodeSent, "Code sent")
        XCTAssertEqual(
            AvafliV2Strings.claimCodeHelp + AvafliV2Strings.claimCodeHelpLink,
            "Can't get to this email? Contact info@avafli.com"
        )
        XCTAssertEqual(AvafliV2Strings.claimCodeHelpMailto, "mailto:info@avafli.com")
        XCTAssertEqual(
            AvafliV2Strings.claimCodeMismatch(attemptsRemaining: 4),
            "That code didn't match. 4 tries left."
        )
        XCTAssertEqual(
            AvafliV2Strings.claimCodeMismatch(attemptsRemaining: 1),
            "That code didn't match. 1 try left."
        )
        XCTAssertEqual(
            AvafliV2Strings.claimCodeUnreachable,
            "We couldn't reach the server. Check your connection and try again."
        )
    }

    /// Plain English on screen: "code", never the jargon.
    func testCodeScreenCopyAvoidsJargon() {
        let copy = [
            AvafliV2Strings.claimCodeSubtitle(maskedEmail: nil),
            AvafliV2Strings.claimCodeSending, AvafliV2Strings.claimCodeSent,
            AvafliV2Strings.claimCodeResendCountdown(seconds: 30),
            AvafliV2Strings.claimCodeHelp, AvafliV2Strings.claimCodeHelpLink,
            AvafliV2Strings.claimCodeMismatch(attemptsRemaining: 2),
            AvafliV2Strings.claimCodeFreshSent,
            AvafliV2Strings.claimCodeResendCooldown(seconds: 30),
            AvafliV2Strings.claimCodeSendLimit, AvafliV2Strings.claimCodeSendFailed,
            AvafliV2Strings.claimCodeNoEmailOnFile, AvafliV2Strings.claimCodeUnreachable,
        ]
        for text in copy {
            let lowered = text.lowercased()
            XCTAssertFalse(lowered.contains("otp"), text)
            XCTAssertFalse(lowered.contains("2fa"), text)
            XCTAssertFalse(lowered.contains("token"), text)
        }
    }

    // MARK: Resend cooldown on this device's clock

    func testResendDateForAJustSentCodeCountsFromNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // The server's clock is five minutes ahead of this device's.
        let block = ClaimVerificationBlock(
            required: true,
            codeSentAt: "2027-01-15T08:05:00.000Z",
            codeExpiresAt: "2027-01-15T08:15:00.000Z",
            resendAvailableAt: "2027-01-15T08:06:00.000Z"
        )
        let date = AvafliExperienceViewModel.claimResendDate(from: block, now: now, justSent: true)
        XCTAssertEqual(date, now.addingTimeInterval(60))
    }

    func testResendDateIsNilWithoutALiveCode() {
        let now = Date()
        XCTAssertNil(AvafliExperienceViewModel.claimResendDate(from: nil, now: now, justSent: false))
        XCTAssertNil(AvafliExperienceViewModel.claimResendDate(
            from: ClaimVerificationBlock(required: true), now: now, justSent: false
        ))
        XCTAssertNil(AvafliExperienceViewModel.claimResendDate(
            from: ClaimVerificationBlock(required: false), now: now, justSent: false
        ))
    }
}

// MARK: - Callable error details reach the claim flow

/// Answers every request of the test session with one scripted response.
private final class ClaimStubURLProtocol: URLProtocol {
    static let lock = NSLock()
    static var status = 200
    static var body = Data()
    static var requestCount = 0

    static func respond(status: Int, body: String) {
        lock.lock()
        self.status = status
        self.body = Data(body.utf8)
        requestCount = 0
        lock.unlock()
    }

    static func seen() -> Int {
        lock.lock(); defer { lock.unlock() }
        return requestCount
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        let status = Self.status
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ClaimVerificationErrorDetailsTests: XCTestCase {

    private final class Counter { var value = 0 }

    private func makeClient(refreshes: Counter = Counter()) -> URLSessionNetworkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClaimStubURLProtocol.self]
        return URLSessionNetworkClient(
            baseURL: URL(string: "https://stub.avafli.test")!,
            apiKey: "avafli_test_stub",
            tokenProvider: { "not-a-jwt" },
            refreshHandler: {
                refreshes.value += 1
                return "not-a-jwt"
            },
            session: URLSession(configuration: configuration)
        )
    }

    private func failure<R: APIRequest>(of request: R, client: URLSessionNetworkClient) async -> Error? {
        do {
            _ = try await client.send(request)
            return nil
        } catch {
            return error
        }
    }

    /// `code_mismatch` is a permission-denied (HTTP 403). It must arrive with
    /// its details, and must NOT take the refresh-and-retry path — a retry
    /// would spend a second try on the same wrong code.
    func testCodeMismatchArrivesWithTriesLeftAndIsNotRetried() async {
        ClaimStubURLProtocol.respond(status: 403, body: """
        {"error":{"status":"PERMISSION_DENIED","message":"That code didn't match. Check the email and try again.","details":{"reason":"code_mismatch","attemptsRemaining":3}}}
        """)
        let refreshes = Counter()
        let error = await failure(
            of: ConfirmClaimVerificationCodeRequest(giveawayId: "gw", code: "123456"),
            client: makeClient(refreshes: refreshes)
        )
        let callable = error as? AvafliCallableFailure
        XCTAssertEqual(callable?.reason, "code_mismatch")
        XCTAssertEqual(callable?.attemptsRemaining, 3)
        XCTAssertEqual(callable?.status, "PERMISSION_DENIED")
        XCTAssertEqual(ClaimStubURLProtocol.seen(), 1)
        XCTAssertEqual(refreshes.value, 0)
    }

    func testFreshCodeSentCarriesTheNewBlock() async {
        ClaimStubURLProtocol.respond(status: 400, body: """
        {"error":{"status":"FAILED_PRECONDITION","message":"That code expired, so we sent you a new one. Check your email.","details":{"reason":"fresh_code_sent","verification":{"required":true,"codeSentAt":"2026-09-29T12:00:00.000Z","codeExpiresAt":"2026-09-29T12:10:00.000Z","resendAvailableAt":"2026-09-29T12:01:00.000Z"}}}}
        """)
        let error = await failure(
            of: ConfirmClaimVerificationCodeRequest(giveawayId: "gw", code: "123456"),
            client: makeClient()
        )
        let callable = error as? AvafliCallableFailure
        XCTAssertEqual(callable?.reason, "fresh_code_sent")
        XCTAssertEqual(callable?.message, "That code expired, so we sent you a new one. Check your email.")
        XCTAssertEqual(callable?.verification?.resendAvailableAt, "2026-09-29T12:01:00.000Z")
    }

    func testCooldownCarriesRetryAfterSeconds() async {
        ClaimStubURLProtocol.respond(status: 429, body: """
        {"error":{"status":"RESOURCE_EXHAUSTED","message":"Please wait 42 seconds before requesting another code.","details":{"reason":"resend_cooldown","retryAfterSeconds":42}}}
        """)
        let error = await failure(
            of: SendClaimVerificationCodeRequest(giveawayId: "gw", resend: true),
            client: makeClient()
        )
        let callable = error as? AvafliCallableFailure
        XCTAssertEqual(callable?.reason, "resend_cooldown")
        XCTAssertEqual(callable?.retryAfterSeconds, 42)
    }

    /// The claim-state rejections carry no reason — the status tells them
    /// apart, and the message stays readable for callers that match on text.
    func testReasonlessRejectionKeepsStatusAndMessage() async {
        ClaimStubURLProtocol.respond(status: 400, body: """
        {"error":{"status":"FAILED_PRECONDITION","message":"The claim window for this prize has expired"}}
        """)
        let error = await failure(
            of: SendClaimVerificationCodeRequest(giveawayId: "gw"),
            client: makeClient()
        )
        let callable = error as? AvafliCallableFailure
        XCTAssertNil(callable?.reason)
        XCTAssertEqual(callable?.status, "FAILED_PRECONDITION")
        XCTAssertTrue("\(String(describing: error))".contains("The claim window for this prize has expired"))
    }

    func testSubmitRejectionsStillMatchOnText() async {
        ClaimStubURLProtocol.respond(status: 409, body: """
        {"error":{"status":"ALREADY_EXISTS","message":"Already submitted","details":{"claimNumber":"9823457758"}}}
        """)
        let request = SubmitPrizeClaimRequest(
            giveawayId: "gw", firstName: "A", lastName: "B", phone: nil, street: "1 St", apt: nil,
            city: "C", state: "New York", zip: "11737", country: "United States",
            photoBase64: nil, promoConsentGranted: false
        )
        let error = await failure(of: request, client: makeClient())
        XCTAssertTrue("\(String(describing: error))".contains("Already submitted"))
    }

    // Every OTHER caller: unchanged.

    private struct PlainRequest: APIRequest {
        struct Response: Decodable { let ok: Bool }
        var path: String { "getActiveGiveaway" }
        var method: String { "POST" }
        var body: Data? { Data("{}".utf8) }
    }

    func testOtherCallersStillGetTheMessageOnlyError() async {
        ClaimStubURLProtocol.respond(status: 400, body: """
        {"error":{"status":"FAILED_PRECONDITION","message":"Nope","details":{"reason":"code_mismatch","attemptsRemaining":3}}}
        """)
        let error = await failure(of: PlainRequest(), client: makeClient())
        guard case AvafliError.internalError("Nope")? = error else {
            return XCTFail("Expected internalError(\"Nope\"), got \(String(describing: error))")
        }
    }

    func testOtherCallersStillTreat403AsAnAuthFailure() async {
        ClaimStubURLProtocol.respond(status: 403, body: """
        {"error":{"status":"PERMISSION_DENIED","message":"Nope","details":{"reason":"code_mismatch"}}}
        """)
        let refreshes = Counter()
        let error = await failure(of: PlainRequest(), client: makeClient(refreshes: refreshes))
        guard case AvafliError.authenticationRequired? = error else {
            return XCTFail("Expected authenticationRequired, got \(String(describing: error))")
        }
        XCTAssertEqual(refreshes.value, 1)
    }

    /// Details of an unexpected shape must never cost a caller the message.
    func testUnexpectedDetailsShapeKeepsTheMessage() async {
        ClaimStubURLProtocol.respond(status: 400, body: """
        {"error":{"status":"INVALID_ARGUMENT","message":"Bad input","details":"see logs"}}
        """)
        let error = await failure(of: PlainRequest(), client: makeClient())
        guard case AvafliError.internalError("Bad input")? = error else {
            return XCTFail("Expected internalError(\"Bad input\"), got \(String(describing: error))")
        }
    }
}

// MARK: - The flow

/// A scripted backend: each path answers from its own queue (the last answer
/// repeats), and every call is recorded with its `data` payload.
private final class ClaimStubNetwork: NetworkClient {
    struct Call {
        let path: String
        let data: [String: Any]
    }

    private let lock = NSLock()
    private var scripts: [String: [Result<String, Error>]] = [:]
    private var recorded: [Call] = []

    func script(_ path: String, _ answers: Result<String, Error>...) {
        lock.lock()
        scripts[path] = answers
        lock.unlock()
    }

    func calls(to path: String) -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.path == path }
    }

    func hasScript(for path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return scripts[path] != nil
    }

    func send<R>(_ request: R) async throws -> R.Response where R: APIRequest {
        let payload = request.body
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["data"] as? [String: Any] } ?? [:]
        lock.lock()
        recorded.append(Call(path: request.path, data: payload))
        var queue = scripts[request.path] ?? []
        let answer = queue.first
        if queue.count > 1 {
            queue.removeFirst()
            scripts[request.path] = queue
        }
        lock.unlock()

        switch answer {
        case .success(let json)?:
            return try JSONDecoder().decode(R.Response.self, from: Data(json.utf8))
        case .failure(let error)?:
            throw error
        case nil:
            throw URLError(.notConnectedToInternet)
        }
    }
}

@MainActor
final class ClaimVerificationFlowTests: XCTestCase {

    private static let sendPath = "sendClaimVerificationCode"
    private static let confirmPath = "confirmClaimVerificationCode"
    private static let submitPath = "submitPrizeClaim"

    private var suiteName = ""
    private var keychain = KeychainStorage(service: "com.winr.sdk.tests.claimverification")
    /// The device clock the view model runs on.
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)
    /// Every screen the drawer showed since it opened, in order.
    private var screens: [String] = []
    private var screenWatch: AnyCancellable?
    /// How many times the drawer asked to be closed.
    private var dismissals = 0
    private var dismissWatch: NSObjectProtocol?

    override func setUp() {
        super.setUp()
        suiteName = "com.avafli.tests.claimverification.\(UUID().uuidString)"
        clock = Date(timeIntervalSince1970: 1_790_000_000)
        screens = []
        dismissals = 0
        dismissWatch = NotificationCenter.default.addObserver(
            forName: .avafliCloseRequested, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissals += 1 }
        }
    }

    override func tearDown() {
        screenWatch = nil
        if let dismissWatch { NotificationCenter.default.removeObserver(dismissWatch) }
        dismissWatch = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        keychain.deleteAll()
        // The experience reports a pending claim to the auto-open engine.
        Avafli.notePendingPrizeClaim(false)
        super.tearDown()
    }

    // MARK: Harness

    private func iso(_ offset: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: clock.addingTimeInterval(offset))
    }

    /// A block whose code was sent `age` seconds ago.
    private func liveCode(sentAgo age: TimeInterval) -> String {
        """
        { "required": true, "codeSentAt": "\(iso(-age))", "codeExpiresAt": "\(iso(600 - age))", "resendAvailableAt": "\(iso(60 - age))" }
        """
    }

    private var runningGiveaway: GiveawayConfig {
        GiveawayConfig(
            id: "g_next", title: "Next giveaway", prizeDescription: "Cash", prizeValue: 500,
            streakLadder: [10, 20, 30], doublingEnabled: false, maxDailyBaseEntries: 30,
            rulesUrl: "https://example.com/rules", startDate: "2026-10-01", endDate: "2026-10-31",
            streakConfig: StreakConfigAPI(
                weeklyResetDay: 1, monthlyResetDay: 1, weeklyBonusThreshold: nil,
                weeklyBonusEntries: nil, monthlyBonusThreshold: nil, monthlyBonusEntries: nil,
                monthlyMilestones: nil
            )
        )
    }

    private var runningGiveawayJSON: String {
        String(data: try! JSONEncoder().encode(runningGiveaway), encoding: .utf8)!
    }

    private static func name(of state: AvafliExperienceViewModel.State) -> String {
        switch state {
        case .loading: return "loading"
        case .noActiveGiveaway: return "empty"
        case .emailCapture: return "emailCapture"
        case .codeEntry, .emailVerification, .adoptionReentry: return "code"
        case .streak, .dailyConfirmed, .completed, .milestoneCelebration: return "dashboard"
        case .howItWorks: return "howItWorks"
        case .winnerClaim: return "winner"
        case .error: return "error"
        }
    }

    /// The default backend of these tests has NO giveaway running — the one
    /// the winner was drawn from has ended — only the pending claim.
    private func giveawayResponse(verification: String?, giveaway: String = "null") -> String {
        let extra = verification.map { ", \"verification\": \($0)" } ?? ""
        return """
        {
            "giveaway": \(giveaway),
            "prizeClaim": {
                "status": "pending",
                "giveawayId": "gw_123",
                "prizeDescription": "Cash Prize",
                "prizeValue": 1000,
                "maskedEmail": "d********r@example.com"\(extra)
            }
        }
        """
    }

    /// A fresh view model (a fresh drawer open) whose backend reports the
    /// given verification block. Returns once the winner splash is up.
    private func openDrawer(
        verification: String?,
        network: ClaimStubNetwork = ClaimStubNetwork()
    ) async -> (AvafliExperienceViewModel, ClaimStubNetwork) {
        if !network.hasScript(for: "getActiveGiveaway") {
            network.script("getActiveGiveaway", .success(giveawayResponse(verification: verification)))
        }
        let viewModel = makeViewModel(network: network)
        await waitUntil("winner splash") { self.claim(of: viewModel) != nil }
        return (viewModel, network)
    }

    /// A drawer open. `cachedGiveaway` / `pendingPrizeClaim` are what the SDK
    /// learned at registration and hands the experience.
    private func makeViewModel(
        network: ClaimStubNetwork,
        cachedGiveaway: GiveawayConfig? = nil,
        pendingPrizeClaim: Bool = false
    ) -> AvafliExperienceViewModel {
        let configuration = AvafliConfiguration(
            apiKey: "avafli_test_claimverification",
            bundleId: "com.avafli.tests.claimverification",
            user: AvafliUser(id: "u-claim"),
            options: AvafliOptions(logging: .none, analyticsAdapter: nil, enablePushReminders: false)
        )
        var container = DependencyContainer(
            configuration: configuration,
            user: configuration.user,
            network: network,
            storage: UserDefaultsStorage(defaults: UserDefaults(suiteName: suiteName)!),
            keychain: keychain
        )
        container.cachedGiveaway = cachedGiveaway
        container.pendingPrizeClaim = pendingPrizeClaim
        let viewModel = AvafliExperienceViewModel(
            container: container,
            presentingViewController: UIViewController(),
            completion: { _ in }
        )
        viewModel.now = { [unowned self] in self.clock }
        viewModel.claimVerifiedHold = 0.01
        screenWatch = viewModel.$state.sink { [weak self] state in
            let name = Self.name(of: state)
            if self?.screens.last != name { self?.screens.append(name) }
        }
        return viewModel
    }

    private func claim(of viewModel: AvafliExperienceViewModel) -> PrizeClaimBlock? {
        if case let .winnerClaim(claim) = viewModel.state { return claim }
        return nil
    }

    private func waitUntil(
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(what)", file: file, line: line)
    }

    private var validForm: AvafliPrizeClaimForm {
        var form = AvafliPrizeClaimForm()
        form.firstName = "Catherine"
        form.lastName = "Cinosta"
        form.phone = "7185550123"
        form.street = "5 Haide Pl."
        form.apt = "4B"
        form.city = "Brooklyn"
        form.state = "New York"
        form.zip = "11737"
        form.authorizesLikeness = true
        return form
    }

    private func mismatch(triesLeft: Int) -> AvafliCallableFailure {
        AvafliCallableFailure(
            status: "PERMISSION_DENIED",
            message: "That code didn't match. Check the email and try again.",
            reason: "code_mismatch",
            attemptsRemaining: triesLeft
        )
    }

    // MARK: Which screen CONTINUE opens

    func testNoVerificationBlockIsTodaysFlow() async {
        let (viewModel, network) = await openDrawer(verification: nil)
        XCTAssertEqual(viewModel.winnerClaimStep, .splash)

        viewModel.winnerClaimContinue()

        XCTAssertEqual(viewModel.winnerClaimStep, .form)
        XCTAssertTrue(network.calls(to: Self.sendPath).isEmpty)
    }

    func testVerificationNotRequiredGoesStraightToTheForm() async {
        let (viewModel, network) = await openDrawer(verification: #"{ "required": false }"#)

        viewModel.winnerClaimContinue()

        XCTAssertEqual(viewModel.winnerClaimStep, .form)
        XCTAssertTrue(network.calls(to: Self.sendPath).isEmpty)
    }

    func testVerificationRequiredOpensTheCodeScreenAndSendsOnce() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)

        viewModel.winnerClaimContinue()

        // First frame: the code screen, already naming the masked address —
        // the send is still in flight.
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)
        XCTAssertEqual(viewModel.claimCodeSendStatus, .sending)
        XCTAssertEqual(
            AvafliV2Strings.claimCodeSubtitle(maskedEmail: claim(of: viewModel)?.maskedEmail),
            "Enter the 6-digit code we sent to d********r@example.com"
        )

        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }
        let sends = network.calls(to: Self.sendPath)
        XCTAssertEqual(sends.count, 1)
        XCTAssertEqual(sends.first?.data["giveawayId"] as? String, "gw_123")
        XCTAssertNil(sends.first?.data["resend"])
        XCTAssertEqual(viewModel.claimResendAvailableAt, clock.addingTimeInterval(60))
    }

    func testLiveCodeIsReusedWithoutACodeSentBanner() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 20)) }"#))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 20), network: network)

        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }

        let sends = network.calls(to: Self.sendPath)
        XCTAssertEqual(sends.count, 1)
        XCTAssertNil(sends.first?.data["resend"])
        XCTAssertNotEqual(viewModel.claimCodeSendStatus, .sent)
        XCTAssertNil(viewModel.claimCodeNotice)
        // The countdown picks up where the live code's cooldown is.
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 40)
    }

    // MARK: Entering the code

    func testCorrectCodeOpensTheFormAndIsNotAskedAgain() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        network.script(Self.confirmPath, .success(#"{ "verified": true, "verification": { "required": false } }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }

        viewModel.confirmClaimCode("123456")
        await waitUntil("claim form") { viewModel.winnerClaimStep == .form }

        XCTAssertEqual(network.calls(to: Self.confirmPath).first?.data["code"] as? String, "123456")
        XCTAssertEqual(claim(of: viewModel)?.verification, ClaimVerificationBlock(required: false))
        XCTAssertFalse(viewModel.isConfirmingClaimCode)

        // The rest of the session: CONTINUE goes to the form, nothing is sent.
        viewModel.winnerClaimStep = .splash
        viewModel.winnerClaimContinue()
        XCTAssertEqual(viewModel.winnerClaimStep, .form)
        XCTAssertEqual(network.calls(to: Self.sendPath).count, 1)
    }

    func testWrongCodeShowsTriesLeftAndClearsTheField() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 5)) }"#))
        network.script(Self.confirmPath, .failure(mismatch(triesLeft: 4)))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 5), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }
        let cleared = viewModel.claimCodeClearCount

        viewModel.confirmClaimCode("000000")
        await waitUntil("mismatch shown") { viewModel.claimCodeNotice != nil }

        XCTAssertEqual(viewModel.claimCodeNotice, .error("That code didn't match. 4 tries left."))
        XCTAssertEqual(viewModel.claimCodeClearCount, cleared + 1)
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)
        XCTAssertFalse(viewModel.isConfirmingClaimCode)
    }

    func testFreshCodeSentIsInformationAndRestartsTheCountdown() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 500)) }"#))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 500), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 0)
        let cleared = viewModel.claimCodeClearCount

        // Eleven minutes later the code is dead; the server has already
        // emailed a new one.
        clock = clock.addingTimeInterval(660)
        let fresh = try? JSONDecoder().decode(ClaimVerificationBlock.self, from: Data(liveCode(sentAgo: 0).utf8))
        network.script(Self.confirmPath, .failure(AvafliCallableFailure(
            status: "FAILED_PRECONDITION",
            message: "That code expired, so we sent you a new one. Check your email.",
            reason: "fresh_code_sent",
            verification: fresh
        )))

        viewModel.confirmClaimCode("123456")
        await waitUntil("fresh code notice") { viewModel.claimCodeNotice != nil }

        XCTAssertEqual(
            viewModel.claimCodeNotice,
            .info("That code expired, so we sent you a new one. Check your email.")
        )
        XCTAssertEqual(viewModel.claimCodeClearCount, cleared + 1)
        XCTAssertEqual(viewModel.claimResendAvailableAt, clock.addingTimeInterval(60))
        XCTAssertEqual(claim(of: viewModel)?.verification, fresh)
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)
    }

    func testNetworkFailureOnTheCheckKeepsWhatWasTyped() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 5)) }"#))
        network.script(Self.confirmPath, .failure(URLError(.notConnectedToInternet)))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 5), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }
        let cleared = viewModel.claimCodeClearCount

        viewModel.confirmClaimCode("123456")
        await waitUntil("error shown") { viewModel.claimCodeNotice != nil }

        XCTAssertEqual(
            viewModel.claimCodeNotice,
            .error("We couldn't reach the server. Check your connection and try again.")
        )
        XCTAssertEqual(viewModel.claimCodeClearCount, cleared, "the field must keep what was typed")
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)
    }

    /// With a giveaway running, an expired claim falls back to the normal
    /// experience — as before.
    func testExpiredClaimWithAGiveawayRunningFallsBackToTheExperience() async {
        let network = ClaimStubNetwork()
        network.script(
            "getActiveGiveaway",
            .success(giveawayResponse(verification: liveCode(sentAgo: 5), giveaway: runningGiveawayJSON)),
            // The reload after the rejection: the claim is gone.
            .success(#"{ "giveaway": \#(runningGiveawayJSON) }"#)
        )
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 5)) }"#))
        network.script(Self.confirmPath, .failure(AvafliCallableFailure(
            status: "FAILED_PRECONDITION",
            message: "The claim window for this prize has expired"
        )))
        let (viewModel, _) = await openDrawer(verification: nil, network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }

        viewModel.confirmClaimCode("123456")

        await waitUntil("claim flow left") { self.claim(of: viewModel) == nil && self.screens.last != "loading" }
        XCTAssertEqual(screens.last, "emailCapture")
        XCTAssertEqual(dismissals, 0)
        XCTAssertFalse(Avafli._isPrizeClaimPendingForTests())
        XCTAssertEqual(network.calls(to: "getActiveGiveaway").count, 2)
    }

    // MARK: A winner with no giveaway running

    /// A giveaway has ENDED by the time its winner is drawn: unless the next
    /// one already started, the response is `{ giveaway: null, prizeClaim }`.
    func testPendingClaimWithoutAGiveawayLandsOnTheWinnerSplash() async {
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#)

        XCTAssertEqual(viewModel.winnerClaimStep, .splash)
        XCTAssertNil(viewModel.activeGiveawayConfig)
        // Prize text comes from the claim itself.
        XCTAssertEqual(claim(of: viewModel)?.prizeDescription, "Cash Prize")
        XCTAssertEqual(claim(of: viewModel)?.prizeValue, 1000)
        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertTrue(Avafli._isPrizeClaimPendingForTests())
    }

    /// The cache of the giveaway that ended must not paint a dashboard in
    /// front of (or behind) the winner flow.
    func testNoDashboardFromTheCacheWhenOpenedForAClaimWithoutAGiveaway() async {
        let storage = UserDefaultsStorage(defaults: UserDefaults(suiteName: suiteName)!)
        try? storage.save(runningGiveaway, for: "winr.com.avafli.tests.claimverification.giveaway")
        try? storage.save(
            StreakState(currentDay: 4, totalEntriesEarned: 100),
            for: "winr.com.avafli.tests.claimverification.user.u-claim.streak"
        )
        try? storage.save(true, for: "winr.com.avafli.tests.claimverification.user.u-claim.emailSubmitted")
        keychain.saveUUID("u-claim-uuid")
        let network = ClaimStubNetwork()
        network.script("getActiveGiveaway", .success(giveawayResponse(verification: #"{ "required": false }"#)))
        network.script("claimDailyEntries", .failure(AvafliError.internalError("Already claimed today")))

        let viewModel = makeViewModel(network: network, pendingPrizeClaim: true)
        XCTAssertEqual(screens, ["loading"], "first frame: the skeleton, not a cached dashboard")
        await waitUntil("winner splash") { self.claim(of: viewModel) != nil }

        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertNil(viewModel.activeGiveawayConfig)
    }

    func testClosingTheWinnerFlowDismissesWithNoDashboardFrame() async {
        let (viewModel, network) = await openDrawer(verification: #"{ "required": true }"#)
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        viewModel.winnerClaimContinue()
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }

        viewModel.requestDismiss()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertNotNil(claim(of: viewModel))
        // Still pending: the auto-open brings it back.
        XCTAssertTrue(Avafli._isPrizeClaimPendingForTests())
    }

    func testExpiredClaimWithoutAGiveawayDismissesTheDrawer() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 5)) }"#))
        network.script(Self.confirmPath, .failure(AvafliCallableFailure(
            status: "FAILED_PRECONDITION",
            message: "The claim window for this prize has expired"
        )))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 5), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }

        viewModel.confirmClaimCode("123456")
        await waitUntil("drawer dismissed") { self.dismissals == 1 }

        // No dashboard, no empty state — nothing was painted behind it.
        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertEqual(network.calls(to: "getActiveGiveaway").count, 1)
        XCTAssertFalse(Avafli._isPrizeClaimPendingForTests())
    }

    /// Tagged by the current backend, untagged by one deployed before the
    /// tags — both mean the claim itself is the problem. The step's own
    /// reasons and unrelated failures do not.
    func testClaimStateRejectionsAreRecognisedTaggedOrNot() {
        for reason in ["claim_expired", "claim_unavailable", "claim_not_open"] {
            XCTAssertTrue(AvafliExperienceViewModel.isClaimStateRejection(
                AvafliCallableFailure(status: "FAILED_PRECONDITION", message: "…", reason: reason)
            ), reason)
        }
        XCTAssertTrue(AvafliExperienceViewModel.isClaimStateRejection(
            AvafliCallableFailure(status: "FAILED_PRECONDITION", message: "The claim window for this prize has expired")
        ))
        for reason in ["fresh_code_sent", "no_email_on_file", "claim_verification_required", "code_mismatch"] {
            XCTAssertFalse(AvafliExperienceViewModel.isClaimStateRejection(
                AvafliCallableFailure(status: "FAILED_PRECONDITION", message: "…", reason: reason)
            ), reason)
        }
        XCTAssertFalse(AvafliExperienceViewModel.isClaimStateRejection(
            AvafliCallableFailure(status: "INTERNAL", message: "boom")
        ))
    }

    func testTaggedExpiredClaimLeavesTheCodeScreenFromTheSendToo() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .failure(AvafliCallableFailure(
            status: "FAILED_PRECONDITION",
            message: "The claim window for this prize has expired",
            reason: "claim_expired"
        )))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)

        viewModel.winnerClaimContinue()
        await waitUntil("drawer dismissed") { self.dismissals == 1 }

        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertFalse(Avafli._isPrizeClaimPendingForTests())
    }

    func testRejectedSubmitIsNoLongerPendingAndDismissesWithoutAGiveaway() async {
        let rejections: [Error] = [
            AvafliCallableFailure(status: "ALREADY_EXISTS", message: "Already submitted"),
            AvafliError.internalError("Not the winner"),
            AvafliCallableFailure(status: "FAILED_PRECONDITION", message: "This prize claim is no longer available"),
            AvafliCallableFailure(
                status: "FAILED_PRECONDITION",
                message: "The claim window for this prize has expired",
                reason: "claim_expired"
            ),
        ]
        for (index, rejection) in rejections.enumerated() {
            let network = ClaimStubNetwork()
            network.script(Self.submitPath, .failure(rejection))
            let (viewModel, _) = await openDrawer(verification: nil, network: network)
            XCTAssertTrue(Avafli._isPrizeClaimPendingForTests())
            viewModel.winnerClaimContinue()

            viewModel.submitPrizeClaim(validForm)
            await waitUntil("drawer dismissed (\(rejection))") { self.dismissals == index + 1 }

            XCTAssertFalse(Avafli._isPrizeClaimPendingForTests(), "\(rejection)")
            XCTAssertNil(viewModel.claimSubmitError)
            XCTAssertEqual(Self.name(of: viewModel.state), "winner", "nothing painted behind it")
        }
    }

    func testSubmittedWithoutAGiveawayConfirmsThenDismisses() async {
        let network = ClaimStubNetwork()
        network.script(Self.submitPath, .success(#"{ "claimNumber": "9823457758", "submittedAt": "2026-09-29T12:00:00Z" }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": false }"#, network: network)
        viewModel.winnerClaimContinue()
        viewModel.submitPrizeClaim(validForm)
        await waitUntil("share step") {
            viewModel.winnerClaimStep == .share(claimNumber: "9823457758", submittedAt: "2026-09-29T12:00:00Z")
        }

        viewModel.winnerShareDone()
        XCTAssertEqual(
            viewModel.winnerClaimStep,
            .confirmation(claimNumber: "9823457758", submittedAt: "2026-09-29T12:00:00Z")
        )
        XCTAssertEqual(dismissals, 0)

        viewModel.winnerConfirmationDone()

        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(screens, ["loading", "winner"])
        XCTAssertFalse(Avafli._isPrizeClaimPendingForTests())
    }

    /// Opened for a pending claim, nothing cached to fall back on, no
    /// network: a message and a retry — never a blank drawer.
    func testOfflineOpenForAPendingClaimShowsRetryNotABlankScreen() async {
        let network = ClaimStubNetwork()
        network.script("getActiveGiveaway", .failure(URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(network: network, pendingPrizeClaim: true)

        await waitUntil("connection state") { self.screens.last == "error" }
        guard case .error(.network) = viewModel.state else {
            return XCTFail("Expected the connection retry state, got \(viewModel.state)")
        }
        XCTAssertEqual(screens, ["loading", "error"])

        // Back online.
        network.script("getActiveGiveaway", .success(giveawayResponse(verification: #"{ "required": true }"#)))
        viewModel.retryLoad()
        await waitUntil("winner splash") { self.claim(of: viewModel) != nil }
        XCTAssertEqual(screens, ["loading", "error", "loading", "winner"])
        XCTAssertEqual(viewModel.winnerClaimStep, .splash)
    }

    /// No pending claim known: the offline path is what it always was.
    func testOfflineOpenWithoutAPendingClaimIsUnchanged() async {
        let network = ClaimStubNetwork()
        network.script("getActiveGiveaway", .failure(URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(network: network, pendingPrizeClaim: false)

        await waitUntil("settled") { self.screens.last != "loading" }
        XCTAssertEqual(screens, ["loading", "emailCapture"])
        _ = viewModel
    }

    // MARK: Send a new code

    func testResendWaitsForTheCooldownThenSendsWithResend() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 10)) }"#))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 10), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 50)

        // Still cooling down: the action does nothing.
        viewModel.resendClaimCode()
        XCTAssertEqual(network.calls(to: Self.sendPath).count, 1)
        XCTAssertEqual(viewModel.claimCodeSendStatus, .idle)

        clock = clock.addingTimeInterval(50)
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 0)
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        viewModel.resendClaimCode()
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }

        let sends = network.calls(to: Self.sendPath)
        XCTAssertEqual(sends.count, 2)
        XCTAssertEqual(sends.last?.data["resend"] as? Bool, true)
        // A new code, a new cooldown.
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 60)
    }

    func testCooldownAndSendLimitFollowRetryAfterSeconds() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 120)) }"#))
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 120), network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("send settled") { viewModel.claimCodeSendStatus == .idle }

        network.script(Self.sendPath, .failure(AvafliCallableFailure(
            status: "RESOURCE_EXHAUSTED",
            message: "Please wait 42 seconds before requesting another code.",
            reason: "resend_cooldown",
            retryAfterSeconds: 42
        )))
        viewModel.resendClaimCode()
        await waitUntil("cooldown notice") { viewModel.claimCodeNotice != nil }
        XCTAssertEqual(
            viewModel.claimCodeNotice,
            .info("Please wait 42 seconds before requesting another code.")
        )
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 42)
        XCTAssertEqual(viewModel.claimCodeSendStatus, .idle)

        clock = clock.addingTimeInterval(42)
        network.script(Self.sendPath, .failure(AvafliCallableFailure(
            status: "RESOURCE_EXHAUSTED",
            message: "You've requested several codes.",
            reason: "send_limit",
            retryAfterSeconds: 1800
        )))
        viewModel.resendClaimCode()
        await waitUntil("send limit notice") {
            viewModel.claimCodeNotice == .info(AvafliV2Strings.claimCodeSendLimit)
        }
        XCTAssertEqual(viewModel.claimResendSecondsRemaining(at: clock), 1800)
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)
    }

    func testFailedSendIsInlineRetryableAndLeavesTheFieldUsable() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .failure(URLError(.timedOut)))
        network.script(Self.confirmPath, .failure(mismatch(triesLeft: 4)))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)

        viewModel.winnerClaimContinue()
        await waitUntil("send failure shown") {
            viewModel.claimCodeSendStatus == .failed(AvafliV2Strings.claimCodeUnreachable)
        }
        XCTAssertEqual(viewModel.winnerClaimStep, .verifyCode)

        // A code from an earlier send may be in the inbox: checking one works.
        viewModel.confirmClaimCode("123456")
        await waitUntil("check went out") { !network.calls(to: Self.confirmPath).isEmpty }
        await waitUntil("check settled") { !viewModel.isConfirmingClaimCode }

        // Retry asks again — still without `resend`.
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        viewModel.retryClaimCodeSend()
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }
        let sends = network.calls(to: Self.sendPath)
        XCTAssertEqual(sends.count, 2)
        XCTAssertNil(sends.last?.data["resend"])
    }

    func testServerSideSendFailureNamesTheNextStep() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .failure(AvafliCallableFailure(
            status: "UNAVAILABLE",
            message: "We couldn't send your code just now. Please try again in a minute.",
            reason: "send_failed"
        )))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)

        viewModel.winnerClaimContinue()
        await waitUntil("send failure shown") {
            viewModel.claimCodeSendStatus == .failed("We couldn't send your code just now. Please try again in a minute.")
        }

        network.script(Self.sendPath, .failure(AvafliCallableFailure(
            status: "FAILED_PRECONDITION",
            message: "We don't have an email on file for this account.",
            reason: "no_email_on_file"
        )))
        viewModel.retryClaimCodeSend()
        await waitUntil("contact address shown") {
            viewModel.claimCodeSendStatus == .failed(AvafliV2Strings.claimCodeNoEmailOnFile)
        }
        XCTAssertTrue(AvafliV2Strings.claimCodeNoEmailOnFile.contains("info@avafli.com"))
    }

    // MARK: Back / close / reopen

    func testBackReturnsToTheSplashWithoutSendingAnything() async {
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": true }"#, network: network)
        viewModel.winnerClaimContinue()
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }

        viewModel.winnerClaimCodeBack()

        XCTAssertEqual(viewModel.winnerClaimStep, .splash)
        XCTAssertEqual(network.calls(to: Self.sendPath).count, 1)
        XCTAssertTrue(network.calls(to: Self.confirmPath).isEmpty)
        // The live code is still the live code.
        XCTAssertEqual(claim(of: viewModel)?.verification?.required, true)
        XCTAssertNotNil(claim(of: viewModel)?.verification?.codeSentAt)
    }

    /// Nothing about the step is kept on the device: a reopened drawer (a
    /// fresh view model) resumes from whatever the server reports.
    func testReopenResumesFromServerState() async {
        // Closed on the code screen; the code is still live.
        let live = ClaimStubNetwork()
        live.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 90)) }"#))
        let (resumed, _) = await openDrawer(verification: liveCode(sentAgo: 90), network: live)
        XCTAssertEqual(resumed.winnerClaimStep, .splash)
        resumed.winnerClaimContinue()
        XCTAssertEqual(resumed.winnerClaimStep, .verifyCode)
        await waitUntil("send settled") { resumed.claimCodeSendStatus == .idle }
        XCTAssertEqual(live.calls(to: Self.sendPath).count, 1)
        XCTAssertNil(live.calls(to: Self.sendPath).first?.data["resend"])

        // Closed after the code was accepted.
        let (verified, network) = await openDrawer(verification: #"{ "required": false }"#)
        verified.winnerClaimContinue()
        XCTAssertEqual(verified.winnerClaimStep, .form)
        XCTAssertTrue(network.calls(to: Self.sendPath).isEmpty)

        // And the device itself holds nothing about the step.
        let stored = UserDefaults(suiteName: suiteName)?.dictionaryRepresentation().keys ?? [:].keys
        XCTAssertFalse(stored.contains { $0.lowercased().contains("verif") || $0.lowercased().contains("claimcode") })
    }

    // MARK: Auto-submit on the sixth digit

    private func textField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    /// The real claim flow on screen, over the stubbed backend: typing the
    /// sixth digit sends the check — VERIFY is never tapped. A wrong code
    /// empties the field, and the next six digits go out the same way.
    func testTypingTheSixthDigitSubmitsWithoutTappingVerify() async throws {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("No window scene to host the claim screen in")
        }
        let network = ClaimStubNetwork()
        network.script(Self.sendPath, .success(#"{ "sent": false, "verification": \#(liveCode(sentAgo: 5)) }"#))
        network.script(
            Self.confirmPath,
            .failure(mismatch(triesLeft: 4)),
            .success(#"{ "verified": true, "verification": { "required": false } }"#)
        )
        let (viewModel, _) = await openDrawer(verification: liveCode(sentAgo: 5), network: network)
        guard let claim = claim(of: viewModel) else { return XCTFail("no claim") }

        let host = UIHostingController(rootView: AvafliV2WinnerClaimFlow(
            viewModel: viewModel, accent: .blue, logoUrl: nil, appName: nil, shareUrl: nil, claim: claim
        ))
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        viewModel.winnerClaimContinue()
        await waitUntil("code field on screen") { self.textField(in: host.view) != nil }
        guard let field = textField(in: host.view) else { return }
        XCTAssertEqual(field.textContentType, .oneTimeCode)
        XCTAssertEqual(field.keyboardType, .numberPad)

        for digit in "000000" {
            XCTAssertTrue(network.calls(to: Self.confirmPath).isEmpty, "nothing goes out before the sixth digit")
            field.insertText(String(digit))
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        await waitUntil("first check sent") { network.calls(to: Self.confirmPath).count == 1 }
        XCTAssertEqual(network.calls(to: Self.confirmPath).first?.data["code"] as? String, "000000")

        await waitUntil("wrong code reported") { viewModel.claimCodeNotice != nil }
        await waitUntil("field emptied") { (self.textField(in: host.view)?.text ?? "").isEmpty }

        // Pasted in one go this time.
        textField(in: host.view)?.insertText("123456")
        await waitUntil("second check sent") { network.calls(to: Self.confirmPath).count == 2 }
        XCTAssertEqual(network.calls(to: Self.confirmPath).last?.data["code"] as? String, "123456")
        await waitUntil("claim form") { viewModel.winnerClaimStep == .form }
    }

    // MARK: The auto-open keeps a pending claim reachable

    /// However the drawer was opened — the auto-open or `Avafli.present()` —
    /// a pending claim lands on the winner splash, and the auto-open engine
    /// is told; a submitted claim tells it the opposite.
    func testPendingClaimLandsOnTheWinnerSplashAndIsReported() async {
        let network = ClaimStubNetwork()
        network.script(Self.submitPath, .success(#"{ "claimNumber": "9823457758", "submittedAt": "2026-09-29T12:00:00Z" }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": false }"#, network: network)

        XCTAssertNotNil(claim(of: viewModel))
        XCTAssertEqual(viewModel.winnerClaimStep, .splash)
        XCTAssertTrue(Avafli._isPrizeClaimPendingForTests())

        viewModel.winnerClaimContinue()
        viewModel.submitPrizeClaim(validForm)
        await waitUntil("share step") {
            viewModel.winnerClaimStep == .share(claimNumber: "9823457758", submittedAt: "2026-09-29T12:00:00Z")
        }
        XCTAssertFalse(Avafli._isPrizeClaimPendingForTests())
    }

    // MARK: The claim form

    func testSubmitDeclaresSupportForTheStep() async {
        let network = ClaimStubNetwork()
        network.script(Self.submitPath, .success(#"{ "claimNumber": "9823457758", "submittedAt": "2026-09-29T12:00:00Z" }"#))
        let (viewModel, _) = await openDrawer(verification: #"{ "required": false }"#, network: network)
        viewModel.winnerClaimContinue()

        viewModel.submitPrizeClaim(validForm)
        await waitUntil("share step") {
            viewModel.winnerClaimStep == .share(claimNumber: "9823457758", submittedAt: "2026-09-29T12:00:00Z")
        }

        let submit = network.calls(to: Self.submitPath).first
        XCTAssertEqual(submit?.data["supportsClaimVerification"] as? Bool, true)
        XCTAssertEqual(submit?.data["firstName"] as? String, "Catherine")
    }

    func testVerificationRequiredOnSubmitTakesTheCodeStepAndKeepsTheForm() async {
        let network = ClaimStubNetwork()
        network.script(
            Self.submitPath,
            .failure(AvafliCallableFailure(
                status: "FAILED_PRECONDITION",
                message: "Verify your email to claim your prize.",
                reason: "claim_verification_required"
            )),
            .success(#"{ "claimNumber": "9823457758", "submittedAt": "2026-09-29T12:00:00Z" }"#)
        )
        network.script(Self.sendPath, .success(#"{ "sent": true, "verification": \#(liveCode(sentAgo: 0)) }"#))
        network.script(Self.confirmPath, .success(#"{ "verified": true, "verification": { "required": false } }"#))
        // The block said nothing about a code — the server knows better.
        let (viewModel, _) = await openDrawer(verification: nil, network: network)
        viewModel.winnerClaimContinue()
        XCTAssertEqual(viewModel.winnerClaimStep, .form)
        let typed = validForm

        viewModel.submitPrizeClaim(typed)
        await waitUntil("code screen") { viewModel.winnerClaimStep == .verifyCode }

        XCTAssertNil(viewModel.claimSubmitError)
        XCTAssertFalse(viewModel.isSubmittingClaim)
        await waitUntil("code sent") { viewModel.claimCodeSendStatus == .sent }
        XCTAssertEqual(network.calls(to: Self.sendPath).count, 1)
        XCTAssertNil(network.calls(to: Self.sendPath).first?.data["resend"])

        viewModel.confirmClaimCode("123456")
        await waitUntil("back on the form") { viewModel.winnerClaimStep == .form }

        // Every field is still there for the form to restore.
        let kept = viewModel.preservedClaimForm
        XCTAssertEqual(kept?.firstName, typed.firstName)
        XCTAssertEqual(kept?.lastName, typed.lastName)
        XCTAssertEqual(kept?.phone, typed.phone)
        XCTAssertEqual(kept?.street, typed.street)
        XCTAssertEqual(kept?.apt, typed.apt)
        XCTAssertEqual(kept?.city, typed.city)
        XCTAssertEqual(kept?.state, typed.state)
        XCTAssertEqual(kept?.zip, typed.zip)
        XCTAssertEqual(kept?.authorizesLikeness, true)

        // The second submit goes through; the kept copy is dropped.
        if let kept { viewModel.submitPrizeClaim(kept) }
        await waitUntil("share step") {
            viewModel.winnerClaimStep == .share(claimNumber: "9823457758", submittedAt: "2026-09-29T12:00:00Z")
        }
        XCTAssertNil(viewModel.preservedClaimForm)
        XCTAssertEqual(network.calls(to: Self.submitPath).count, 2)
    }
}
