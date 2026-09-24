# Avafli SDK — API Reference

The [README](../README.md) is the canonical overview of the SDK; this page documents every public symbol as of 3.1.4.

## Table of Contents

- [Avafli (Static API)](#avafli-static-api)
- [AvafliConfiguration](#avafliconfiguration)
- [AvafliAutoOpen](#avafliautoopen)
- [AvafliOptions](#avaflioptions)
- [AvafliEnvironment](#avaflienvironment)
- [AvafliUser](#avafliuser)
- [AvafliError](#avaflierror)
- [DailyEntryGrant](#dailyentrygrant)
- [AnalyticsAdapter](#analyticsadapter)
- [AvafliAnalyticsEvent](#avaflianalyticsevent)
- [AvafliConstants](#avafliconstants)

---

## Avafli (Static API)

```swift
public enum Avafli
```

The primary entry point for the SDK. All methods are static.

### `configure(_:)`

```swift
public static func configure(_ configuration: AvafliConfiguration)
```

The single entry point — call once at app launch. Stores the configuration, sets the logging level, registers the device in the background, and fetches the active giveaway. After registration completes (and on each app foreground), the SDK presents the experience automatically at most once per calendar day, subject to `AvafliConfiguration.autoOpen` (default `.always`). Auto-open can be disabled remotely via the dashboard; unregistered users see at most 3 auto-opens; opted-out users never see it. Device registration and analytics (DAU/MAU) run on configure regardless of the auto-open mode.

---

### `present(completion:)`

```swift
@discardableResult
public static func present(
    completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)? = nil
) -> Bool
```

Publisher-initiated open: presents the experience modally from the top-most view controller — from a button, a screen, or an onboarding-complete handler. Explicit invocation bypasses the once-per-day mark and the unregistered impression cap, and does not count as an impression; on close it writes the same once-per-day mark auto-open writes, so a later auto-open that day does not double-pop.

Guards match auto-open: the SDK must be configured, the user must not have opted out, the publisher must not be suspended, an active giveaway must exist, and the experience must not already be on screen (no-op). If device registration is still in flight, `present()` waits for it; if registration failed, it returns without presenting and logs.

**Returns:** `false` if the SDK is not configured or no presenting view controller could be found; `true` once presentation begins. The completion receives the `DailyEntryGrant` when today's entry is claimed, or an `AvafliError` otherwise.

---

### `holdAutoOpen()` / `releaseAutoOpen()`

```swift
public static func holdAutoOpen()
public static func releaseAutoOpen()
```

Defer the once-per-day auto-open around a boot flow. `holdAutoOpen()` may be called before `configure(_:)`; while held, the auto-open is deferred and nothing is burned (no once-per-day mark, no impression). `present(completion:)` still works while held. `releaseAutoOpen()` clears the hold and immediately re-runs the auto-open eligibility check (which applies the effective `autoOpen` mode). Both are safe before configure and idempotent.

---

### `optOut()`

```swift
public static func optOut() async throws
```

Right-to-Delete opt-out: tombstones the person on the backend (identity-wide, PII anonymized, email suppressed) and permanently silences the experience on this device. If your app has its own delete-account flow, call this from it so the user's Avafli data is erased along with their account. Users can also delete their data themselves at any time from the Privacy Policy screen inside the experience — no integration required.

**Throws:** `AvafliError.notConfigured`, `AvafliError.authenticationRequired`.

`optOut()` is the only erasure API — there is no hard-delete method. Users can
also invoke it themselves in-app: the Privacy Policy (every legal link opens it
in an in-app webview) contains a **Delete my data & stop participating** section
that confirms and runs the same opt-out.

---

### Push Notifications

```swift
public static func registerForPushNotifications()
```

Requests notification permission and registers for APNs. No-op if `AvafliOptions.enablePushReminders` is `false`.

```swift
public static func didRegisterForRemoteNotifications(deviceToken: Data)
```

Forward the APNs token from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.

```swift
public static func didReceiveFCMToken(_ token: String)
```

Forward the Firebase Messaging registration token from `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)` so Avafli's backend can send streak reminders through your Firebase project. Without it the SDK falls back to local reminders.

```swift
public static func didFailToRegisterForRemoteNotifications(error: Error)
```

Forward the APNs failure from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.

---

## AvafliConfiguration

```swift
public struct AvafliConfiguration {
    public init(
        apiKey: String,
        environment: AvafliEnvironment = .production,
        bundleId: String,
        user: AvafliUser,
        options: AvafliOptions = .init(),
        autoOpen: AvafliAutoOpen = .always
    )
}
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `apiKey` | `String` | ✅ | Your Avafli API key from the dashboard |
| `environment` | `AvafliEnvironment` | — | `.production` (default; the only environment) |
| `bundleId` | `String` | ✅ | App bundle ID (e.g. `com.example.myapp`) |
| `user` | `AvafliUser` | ✅ | The authenticated user |
| `options` | `AvafliOptions` | — | Optional behavior toggles |
| `autoOpen` | `AvafliAutoOpen` | — | When the SDK auto-opens the experience (default `.always`) |

Existing initializers stay source-compatible — `autoOpen` is optional and defaults to today's behavior.

---

## AvafliAutoOpen

```swift
public enum AvafliAutoOpen {
    case always
    case returningUsersOnly
    case never
}
```

| Case | Behavior |
|------|----------|
| `.always` | Default. Auto-opens once per calendar day when eligible — unchanged from previous releases. |
| `.returningUsersOnly` | Skips the auto-open for the session in which the device is registered for the first time (`isNewUser`), so a first-time user's onboarding is not interrupted. Every later launch auto-opens as normal. An older backend that does not report `isNewUser` is treated as returning. |
| `.never` | The SDK never auto-opens; the host calls `Avafli.present(completion:)`. |

The dashboard can also set a server-side mode (`experience.autoOpenMode`), and `experience.autoOpenEnabled == false` remains the hard kill switch. The effective mode is the most restrictive of the server settings and this value (`never` > `returningUsersOnly` > `always`). Registration and analytics run on `configure(_:)` in every mode.

---

## AvafliOptions

```swift
public struct AvafliOptions {
    public init(
        logging: LoggingLevel = .error,
        analyticsAdapter: AnalyticsAdapter? = ConsoleAnalyticsAdapter(),
        enablePushReminders: Bool = true
    )
}
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `logging` | `LoggingLevel` | `.error` | `.none`, `.error`, `.info`, or `.debug` |
| `analyticsAdapter` | `AnalyticsAdapter?` | `ConsoleAnalyticsAdapter()` | Routes SDK events to your analytics stack |
| `enablePushReminders` | `Bool` | `true` | Enables streak reminder push notifications |

---

## AvafliEnvironment

```swift
public enum AvafliEnvironment {
    case production
}
```

Production-only — there is no staging or QA backend.

---

## AvafliUser

```swift
public struct AvafliUser {
    public init(
        id: String,
        firstName: String = "",
        lastName: String = "",
        phone: String? = nil,
        email: String? = nil
    )

    /// A guest session — the person is not signed in to your app (or your app
    /// has no accounts). The SDK mints a stable per-install `avafli_guest_…` id.
    public static let guest: AvafliUser
}
```

Only `id` is required; everything else is optional and the SDK captures what's
missing (email via its capture screen, name at prize-claim if the user wins).
Pass whatever identity you already hold — even just an id.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | `String` | ✅ | Your app's unique, stable user identifier (the only required field) |
| `firstName` | `String` | — | User's first name; captured at prize-claim if omitted |
| `lastName` | `String` | — | User's last name; captured at prize-claim if omitted |
| `phone` | `String?` | — | Phone number in E.164 format |
| `email` | `String?` | — | From your authenticated session. If passed, it pre-fills and **locks** the capture field; if omitted, the SDK captures it. A plain `String`. |

> **Email:** A supplied `email` never records consent — the user still ticks
> the age (and optionally marketing) boxes and submits inside the Avafli flow. A
> malformed value is ignored and the field stays editable. For apps with no
> signed-in user, use `AvafliUser.guest`.

---

## AvafliError

```swift
public enum AvafliError: Error {
    case notConfigured
    case noPresentingViewController
    case network(Error)
    case invalidState
    case ineligibleToday
    case alreadyClaimed
    case invalidAPIKey
    case unauthorizedBundleId
    case giveawayNotActive
    case authenticationRequired
    case serviceUnavailable   // publisher suspended / API key revoked
    case optedOut             // user exercised Right-to-Delete
    case internalError(String)
}
```

Conforms to `LocalizedError`; every case provides an `errorDescription`.

---

## DailyEntryGrant

```swift
public struct DailyEntryGrant {
    public let baseEntries: Int
    public let bonusEntries: Int
    public var total: Int { baseEntries + bonusEntries }
}
```

The entries granted during a session (auto-opened or via `present(completion:)`). `baseEntries` is the daily streak-ladder amount (a simple +10 per day); `bonusEntries` defaults to `0` and holds any additional entries granted alongside the daily amount.

---

## AnalyticsAdapter

```swift
public protocol AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?)
}
```

Implement to route Avafli events to your analytics backend (Firebase Analytics, Amplitude, Mixpanel, …). The SDK ships with `ConsoleAnalyticsAdapter` (logs to the Xcode console) as the default.

Convenience helpers are provided as protocol extensions: `trackRegistration(userId:)`, `trackExperienceOpened(giveawayId:)`, `trackExperienceClosed(giveawayId:)`, `trackDailyEntryClaimed(day:entries:)`, `trackPrizeWon(prizeName:prizeValue:)`.

---

## AvafliAnalyticsEvent

Event-name constants emitted by the SDK:

| Constant | Event name | When |
|----------|------------|------|
| `registration` | `avafli_registration` | Device/user registered with Avafli |
| `experienceOpened` | `avafli_experience_opened` | The experience opened (once-per-day auto-open) |
| `experienceClosed` | `avafli_experience_closed` | The experience was dismissed |
| `dailyEntryClaimed` | `avafli_daily_entry_claimed` | Daily entries awarded (auto-claimed on open) |
| `prizeWon` | `avafli_prize_won` | The user was selected as a winner |

---

## AvafliConstants

```swift
public enum AvafliConstants {
    public static let sdkVersion = "3.1.1"
    public static let platformOS = "iOS"
}
```
