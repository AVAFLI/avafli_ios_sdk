# Avafli iOS SDK — API Reference (3.3.2)

Every `public` symbol exported by the `AvafliSDK` module, taken from the source.
Symbols are grouped by whether a host app is expected to call them.

- [Avafli](#avafli) — the static entry point
- [AvafliConfiguration](#avafliconfiguration)
- [AvafliAutoOpen](#avafliautoopen)
- [AvafliUser](#avafliuser)
- [AvafliOptions](#avaflioptions)
- [AvafliEnvironment](#avaflienvironment)
- [AvafliError](#avaflierror)
- [DailyEntryGrant](#dailyentrygrant)
- [AnalyticsAdapter](#analyticsadapter), [ConsoleAnalyticsAdapter](#consoleanalyticsadapter), [AvafliAnalyticsEvent](#avaflianalyticsevent)
- [PushNotificationManager](#pushnotificationmanager)
- [AvafliConstants](#avafliconstants)
- [Public but not for host use](#public-but-not-for-host-use) — `AvafliBranding`, `AvafliLogo`, `Color(hex:)`, demo hooks

---

## Avafli

```swift
public enum Avafli
```

All members are static. Call UI-affecting members on the main thread.

### `configure(_:)`

```swift
public static func configure(_ configuration: AvafliConfiguration)
```

The single entry point — call once at launch. Stores the configuration, sets
the log level, registers the device in the background (or refreshes the
session and the active giveaway for a returning device), submits the user
profile, and from then on runs the once-per-day auto-open check after
registration and on every return to the foreground. Calling it again (for
example after sign-in, with a real `AvafliUser` instead of `.guest`) is
supported: the streak and session are kept and attribution is updated.

A network failure at boot is retried automatically on the next foreground and
on connectivity regain. Nothing is thrown.

### `present(completion:)`

```swift
@discardableResult
public static func present(
    completion: ((Result<DailyEntryGrant, AvafliError>) -> Void)? = nil
) -> Bool
```

Publisher-initiated open from the top-most view controller of the
foreground-active scene.

Guards (same as the auto-open): configured; user not opted out; publisher not
suspended; an active giveaway exists **or** a prize claim is pending; the
experience is not already on screen (then a no-op that returns `true`). Unlike
the auto-open it bypasses the once-per-day mark and the unregistered impression
cap and never counts an impression. When the drawer closes it writes the
once-per-day mark so the auto-open does not open again that day. With a pending
prize claim it opens on the winner splash.

If registration is still in flight the call returns `true` and the experience
is presented once registration settles; if registration failed the completion
receives `.failure(.giveawayNotActive)`.

**Returns** `false` when refused immediately. The completion then receives
`.failure` with one of `.notConfigured`, `.serviceUnavailable`, `.optedOut`,
`.giveawayNotActive`, `.noPresentingViewController`.

**`.success(DailyEntryGrant)`** (3.3.2) is delivered **once per presentation,
on the main thread, the moment that presentation records today's entries**:
the automatic claim on open, the Day-1 claim right after email submit, or the
silent claim behind a winner's prize flow. The grant is the backend's answer
(`baseEntries` from the ladder, `bonusEntries` from weekly / monthly /
milestone bonuses). The completion is **not** called when the presentation
claims nothing — the day was already claimed, the person is still on email
capture, or the claim failed and was queued for an offline retry (that later
recovery is reported only as `avafli_daily_entry_claimed` with
`recovered_offline: true`). `.success` and `.failure` are mutually exclusive
for one call. The same moment is also sent to your `AnalyticsAdapter` as
`avafli_daily_entry_claimed`, which additionally covers the auto-open.

### `holdAutoOpen()` / `releaseAutoOpen()`

```swift
public static func holdAutoOpen()
public static func releaseAutoOpen()
```

`holdAutoOpen()` pauses the once-a-day auto-open; call it before
`configure(_:)` when a boot flow must not be covered. While held nothing is
burned (no daily mark, no impression) and `present()` still works. A hold is
deliberately not cleared by `configure(_:)`. `releaseAutoOpen()` clears the
hold and immediately re-runs the eligibility check (applying the effective
auto-open mode). Both are safe before `configure(_:)` and idempotent.

### Account deletion — no API

There is no host-callable erasure. `Avafli.optOut()` was removed from the
public surface in 3.3.2 (a host app must not be able to erase a person's
Avafli data). Users delete their own data from the Privacy Policy screen inside
the experience (**Delete my data & stop participating**): identity-wide
erasure, after which `present()` is refused with `.optedOut` and the auto-open
is suppressed on that device for 24 hours, then the person may join again as a
brand-new participant (the SDK clears the old session and registers afresh on
the next `configure(_:)` or foreground). Nothing for the host app to do.

### Push notifications

```swift
public static func registerForPushNotifications()
```

Requests notification permission (`.alert, .sound, .badge`) and registers for
remote notifications. No-op when `AvafliOptions.enablePushReminders` is
`false`. If permission is denied, a local daily reminder is scheduled instead.

```swift
public static func didRegisterForRemoteNotifications(deviceToken: Data)
```

Forward from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
The APNs token is kept locally only; server-sent reminders need the FCM token
below. Until one has been accepted by the backend the local reminder stays
armed; once one has (even on an earlier launch) this call no longer arms it.

```swift
public static func didReceiveFCMToken(_ token: String)
```

Forward from `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)`.
Sends the token to the Avafli backend (once per process, after the device is
registered) so reminders can be delivered through your Firebase project. Empty
tokens are ignored. **When the backend accepts the token the local 6 PM
fallback reminder is cancelled** and a per-install flag is persisted so it is
not re-armed on later launches (3.3.2) — server reminders are then the only
reminders.

```swift
public static func didFailToRegisterForRemoteNotifications(error: Error)
```

Forward from `application(_:didFailToRegisterForRemoteNotificationsWithError:)`.
Logs the error, clears the persisted "server token" flag and schedules the
local reminder.

---

## AvafliConfiguration

```swift
public struct AvafliConfiguration {
    public let apiKey: String
    public let environment: AvafliEnvironment
    public let bundleId: String
    public let user: AvafliUser
    public let options: AvafliOptions
    public let autoOpen: AvafliAutoOpen

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

| Parameter | Required | Description |
| --- | --- | --- |
| `apiKey` | yes | `avafli_live_…` (release) or `avafli_test_…` (sandbox, for debug builds). Keys issued before the rename (`winr_…`) remain valid |
| `environment` | — | `.production` is the only value |
| `bundleId` | yes | Must be one of the bundle IDs registered to the key in the dashboard |
| `user` | yes | See `AvafliUser`; `.guest` when nobody is signed in |
| `options` | — | Logging, analytics adapter, push reminders |
| `autoOpen` | — | When the SDK may open the drawer by itself; default `.always` |

---

## AvafliAutoOpen

```swift
public enum AvafliAutoOpen {
    case always
    case returningUsersOnly
    case never
}
```

| Case | Behaviour |
| --- | --- |
| `.always` | Default. Auto-open once per local calendar day when eligible |
| `.returningUsersOnly` | Skip the auto-open for the one session in which the backend reports this device as a brand-new user (`isNewUser`). Every later launch auto-opens. A backend that does not report `isNewUser` is treated as returning |
| `.never` | Never auto-open; the host calls `present()` |

The effective mode is the most restrictive of the dashboard's server-side mode
(`experience.autoOpenMode`), the server kill switch
(`experience.autoOpenEnabled == false` → `never`) and this value
(`never` > `returningUsersOnly` > `always`). Registration and analytics run in
every mode. A pending prize claim reopens the drawer in every mode except
`never` (see README §5).

---

## AvafliUser

```swift
public struct AvafliUser {
    public let id: String
    public let firstName: String
    public let lastName: String
    public var phone: String?
    public var email: String?

    public init(
        id: String,
        firstName: String = "",
        lastName: String = "",
        phone: String? = nil,
        email: String? = nil
    )

    public static let guest: AvafliUser
}
```

| Field | Description |
| --- | --- |
| `id` | Your app's stable user id (Firebase UID, database id, …). The only required field |
| `firstName`, `lastName` | Optional; a winner is asked for them at prize claim if missing |
| `phone` | Optional, E.164. Stored on the profile; the SDK never sends SMS on its own |
| `email` | Optional. When passed, the capture screen shows it pre-filled and read-only (Avafli links accounts across devices by email). Never records consent — the user still ticks the age/marketing boxes and submits. A malformed value is ignored and the field stays editable |
| `.guest` | Nobody is signed in. The SDK mints a stable per-install `avafli_guest_…` id for attribution; the experience is fully functional and the streak survives a later `configure` with a real user |

---

## AvafliOptions

```swift
public struct AvafliOptions {
    public enum LoggingLevel { case none, error, info, debug }

    public let logging: LoggingLevel
    public let analyticsAdapter: AnalyticsAdapter?
    public let enablePushReminders: Bool

    public init(
        logging: LoggingLevel = .error,
        analyticsAdapter: AnalyticsAdapter? = ConsoleAnalyticsAdapter(),
        enablePushReminders: Bool = true
    )
}
```

| Parameter | Default | Description |
| --- | --- | --- |
| `logging` | `.error` | SDK log verbosity (`print`-based; use `.debug` while integrating) |
| `analyticsAdapter` | `ConsoleAnalyticsAdapter()` | Receives SDK events; pass `nil` to receive none |
| `enablePushReminders` | `true` | `false` makes `registerForPushNotifications()` a no-op |

---

## AvafliEnvironment

```swift
public enum AvafliEnvironment {
    case production
}
```

The only environment. Sandbox testing is done with an `avafli_test_…` key, not
a separate environment.

---

## AvafliError

```swift
public enum AvafliError: Error {
    case notConfigured                // configure(_:) not called yet
    case noPresentingViewController   // no key window / root view controller in a foreground-active scene
    case network(Error)
    case invalidState
    case ineligibleToday
    case alreadyClaimed
    case invalidAPIKey
    case unauthorizedBundleId         // bundleId not registered to this key
    case giveawayNotActive            // nothing running and no pending claim (or registration failed)
    case authenticationRequired       // device not registered yet
    case serviceUnavailable           // publisher suspended / key revoked — the SDK presents nothing
    case optedOut                     // user deleted their data; rejoin possible after 24 hours
    case geoBlocked                   // backend geo-fence rejected the request (non-US / unverifiable)
    case internalError(String)
}
```

Conforms to `LocalizedError`; every case has an `errorDescription`. The cases a
host app can receive from `present(completion:)` are `.notConfigured`,
`.serviceUnavailable`, `.optedOut`, `.giveawayNotActive` and
`.noPresentingViewController`. The rest are used inside the experience, which
renders its own messaging (for example a "Not available in your location" state
for `.geoBlocked`).

---

## DailyEntryGrant

```swift
public struct DailyEntryGrant {
    public let baseEntries: Int
    public let bonusEntries: Int
    public var total: Int { baseEntries + bonusEntries }
    public init(baseEntries: Int, bonusEntries: Int = 0)
}
```

The entries granted by one day's claim: `baseEntries` from the giveaway's
ladder for the streak day, `bonusEntries` from weekly/monthly/milestone
bonuses. It is the payload of `present(completion:)`'s `.success` case,
delivered once when that presentation records today's entries (see above).

---

## AnalyticsAdapter

```swift
public protocol AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?)
}
```

Implement to forward SDK events to your analytics stack. Convenience helpers
are provided as a public protocol extension (each calls `track` with the
matching `AvafliAnalyticsEvent` name): `trackRegistration(userId:)`,
`trackExperienceOpened(giveawayId:)`, `trackExperienceClosed(giveawayId:)`,
`trackDailyEntryClaimed(day:entries:)`, `trackBonusEntryClaimed(source:entries:)`,
`trackStreakMilestone(day:bonusEntries:)`, `trackPrizeWon(prizeName:prizeValue:)`.

Events are buffered while offline and flushed on the next launch or
foreground, so `track` may be called later than the user action.

## ConsoleAnalyticsAdapter

```swift
public final class ConsoleAnalyticsAdapter: AnalyticsAdapter {
    public init()
    public func track(event: String, properties: [String: Any]?)
}
```

The default adapter. Logs `[Avafli] <event> | key=value, …` through `os_log`
(subsystem `com.winr.sdk`, category `Analytics`) so events show in Xcode and
Console.app with no setup.

## AvafliAnalyticsEvent

```swift
public enum AvafliAnalyticsEvent {
    public static let registration       = "avafli_registration"
    public static let experienceOpened   = "avafli_experience_opened"
    public static let experienceClosed   = "avafli_experience_closed"
    public static let dailyEntryClaimed  = "avafli_daily_entry_claimed"
    public static let bonusEntryClaimed  = "avafli_bonus_entry_claimed"
    public static let streakMilestone    = "avafli_streak_milestone"
    public static let prizeWon           = "avafli_prize_won"
    // Legacy aliases
    public static let experiencePresented = experienceOpened
    public static let dailyEntriesClaimed = dailyEntryClaimed
}
```

What the 3.3.2 experience actually sends to your adapter:

| Event | When | Properties |
| --- | --- | --- |
| `avafli_experience_opened` | Every time the drawer opens (auto-open or `present()`) | `giveaway_id` |
| `avafli_daily_entry_claimed` | The day's entries were recorded (also for a claim recovered after an offline retry, with `recovered_offline: true`) | `day`, `entries`, milestone details when one was hit |
| `avafli_streak_milestone` | A milestone day awarded bonus entries | `streak_day`, `bonus_entries` |
| `avafli_badge_earned` | That milestone also carried a badge | `badge`, `milestone_day`, `bonus_entries` |
| `avafli_winner_claim_shown` | The winner splash was shown | `giveaway_id` |
| `avafli_prize_claim_submitted` | The winner submitted the claim form | `giveaway_id`, `claim_number` |

`avafli_registration`, `avafli_experience_closed`, `avafli_bonus_entry_claimed`
and `avafli_prize_won` are defined as constants but are **not emitted** by the
3.3.2 experience.

---

## PushNotificationManager

```swift
public final class PushNotificationManager: NSObject {
    public static let shared: PushNotificationManager
    public func register()
    public func didRegisterForRemoteNotifications(deviceToken: Data)
    public func didReceiveFCMToken(_ token: String)
    public func didFailToRegisterForRemoteNotifications(error: Error)
    public func scheduleLocalStreakReminder()
    public func cancelStreakReminders()
}
```

The object behind `Avafli.registerForPushNotifications()` and the three
`Avafli.did…` forwarders (prefer those — they honour `enablePushReminders`).
Two members are only reachable here:

- `scheduleLocalStreakReminder()` — (re)schedules the local fallback: a
  repeating daily notification at 6 PM device time, "Don't lose your streak!".
  The SDK calls it itself when permission is denied, when APNs registration
  fails, and when an APNs token arrives. **A logged no-op while the backend
  holds a push token for this install** (3.3.2): server reminders and the local
  nudge are never both armed.
- `cancelStreakReminders()` — removes that local reminder. The SDK calls it
  itself the moment the backend accepts an FCM token (3.3.2); call it yourself
  if your app sends its own reminders and you want no Avafli nudge at all.

---

## AvafliConstants

```swift
public enum AvafliConstants {
    public static let sdkVersion = "3.3.2"
    public static let platformOS = "iOS"
}
```

`sdkVersion` is reported to the backend at registration and matches the
podspec and the latest CHANGELOG entry.

---

## Public but not for host use

These symbols are `public` because the SDK's own SwiftUI layer needs them
across files. A host app has no reason to call them.

- **`AvafliBranding`** — the resolved theme (colors, corner radius, logo,
  logo sizes). Branding is server-driven: the SDK builds it from the
  dashboard's logo / primary color / prize image and falls back to its built-in
  dark theme when no server config has loaded yet. Constructing one in your
  app has no effect on the drawer.
- **`AvafliLogo`** — `.asset(name:)`, `.remote(url:)`, `.system(_:)`,
  `.bundled(name:)`; the logo source inside `AvafliBranding`.
- **`Color.init(hex:)`** — a public `SwiftUI.Color` extension used by the
  theme. If your app defines its own `Color(hex:)`, yours takes precedence
  inside your module.
- **Demo hooks** on `Avafli` — `demoPerform(_:completion:)`,
  `demoWipeIdentity()`, `demoClearDailyMarks()`. They exist for the bundled
  sample app and are hard-gated to its bundle ID (and to a server-side demo
  publisher): in any other app they return `false` / do nothing.
