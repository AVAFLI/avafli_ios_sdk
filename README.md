# Avafli iOS SDK

**Drop-in daily-entry sweepstakes for your iOS app — one call to integrate.**

[![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![CocoaPods](https://img.shields.io/badge/CocoaPods-3.3.2-red.svg)](https://cocoapods.org/pods/AvafliSDK)

Avafli adds a daily-entry sweepstakes to your app. A bottom drawer opens itself
on the first app-open of each day, claims the user's entries automatically and
celebrates the streak. You call `Avafli.configure(_:)` once; prizes, the entry
ladder, branding and reminder schedules are managed from the
[Avafli dashboard](https://sdk.avafli.com/dashboard) and change without an app
release.

Current version: **3.3.2** (`AvafliConstants.sdkVersion`). Full history in
[CHANGELOG.md](CHANGELOG.md).

## Contents

1. [Requirements](#1-requirements)
2. [Install](#2-install)
3. [Configure](#3-configure)
4. [What the user sees](#4-what-the-user-sees)
5. [Controlling presentation](#5-controlling-presentation)
6. [Push reminders](#6-push-reminders)
7. [Testing checklist](#7-testing-checklist)
8. [API reference](#8-api-reference)
10. [Links](#10-links)

---

## 1. Requirements

| | Minimum |
| --- | --- |
| iOS | 15.0 |
| Xcode | 15.0 |
| Swift | 5.9 (the package manifest is `swift-tools-version: 5.9`) |
| Frameworks | UIKit, SwiftUI, Security (linked automatically) |
| Host app | A UIKit `AppDelegate`/`SceneDelegate` app **or** a SwiftUI `App` — the SDK presents over the key window's root view controller of the foreground-active scene |
| Account | A publisher account and API key from the [dashboard](https://sdk.avafli.com/dashboard) ([pricing](https://sdk.avafli.com/pricing)) |

The SDK collects no advertising identifiers and never shows the App Tracking
Transparency prompt. It talks to the Avafli backend over certificate-pinned
HTTPS; no other network permissions or entitlements are required.

## 2. Install

The Swift module, SPM product and CocoaPods pod are all named **`AvafliSDK`**.

### Swift Package Manager

Xcode: **File → Add Package Dependencies…**, enter
`https://github.com/AVAFLI/avafli_ios_sdk.git`, choose **Up to Next Major
Version** from `3.3.2`, and add the `AvafliSDK` library to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AVAFLI/avafli_ios_sdk.git", from: "3.3.2")
],
targets: [
    .target(name: "MyApp", dependencies: ["AvafliSDK"])
]
```

### CocoaPods

```ruby
pod 'AvafliSDK', '~> 3.3'
```

```bash
pod install
```

## 3. Configure

Call `Avafli.configure(_:)` once, as early as possible at launch. This is the
whole integration: it registers the device, fetches the active giveaway and,
from then on, opens the drawer once per calendar day.

```swift
import AvafliSDK

// AppDelegate.application(_:didFinishLaunchingWithOptions:)  — or  App.init()
#if DEBUG
let apiKey = "avafli_test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"   // sandbox key: your dashboard shows it next to the live key
#else
let apiKey = "avafli_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"   // live key: load from a non-committed source
#endif

Avafli.configure(AvafliConfiguration(
    apiKey: apiKey,
    bundleId: Bundle.main.bundleIdentifier!,       // must be registered to your key in the dashboard
    user: AvafliUser(
        id: "user_123",                            // your app's stable user id — the only required field
        firstName: "Jane",                         // optional; collected at prize claim if missing
        lastName: "Doe",                           // optional
        email: "jane@example.com"                  // optional; pre-fills AND locks the capture field
    ),
    options: AvafliOptions(
        logging: .debug,                           // .error (default) for release builds
        enablePushReminders: true                  // default; see §6
    ),
    autoOpen: .always                              // default; .returningUsersOnly / .never — see §5
))
```

Nobody signed in? Pass `user: .guest`. The SDK mints a stable per-install guest
id (`avafli_guest_…`), captures its own email, and when the person later signs
in you simply call `configure` again with the real user — the streak carries
over.

**Keys.** `avafli_live_…` is your real giveaway; `avafli_test_…` is an isolated
sandbox that hits the same production backend (§7). Keys issued before the
Avafli rename (`winr_live_…` / `winr_test_…`) remain valid. Every key is
server-side restricted to the bundle IDs you register in the dashboard — a
mismatch surfaces as `AvafliError.unauthorizedBundleId` in the debug log.

**Email.** Omit `email` and the SDK captures an address through its own
consent screen (this is the common case and the main value of the integration).
Pass it and the address is pre-filled and read-only — Avafli links accounts
across devices by email, so a free-typed address could attach a user to someone
else's record. Passing an email never records consent: the user still ticks the
age box (and, optionally, marketing) and submits. A malformed value is ignored
and the field stays editable.

## 4. What the user sees

**Day 1.** The drawer opens on the email-capture screen: prize card, email
field, an age checkbox (minimum age is set per publisher, default 18) and an
unchecked marketing-consent box. Submitting claims Day 1 and shows a one-time
"You're in!" welcome. If the address already belongs to an Avafli account on
another device, a 6-digit code emailed to that address is required before the
streak moves to this device (partner-passed emails skip this). When Avafli has
enabled soft email verification, a brand-new typed address also shows a small
"Verify your email" chip on the dashboard; it never blocks play.

**Every later day.** The drawer opens once (first app-open of the day), the
day's entries are claimed automatically and the dashboard animates the result:
the day tile checks off, the total counts up and a "YOU'RE ON A ROLL!" toast
settles into a come-back message. There is no claim button — the pill reads
**GOT IT** and closes the drawer.

**Streak and entries.** Each giveaway has its own entry ladder set in the
dashboard (default +10 entries per consecutive day for 30 days). In the default
`daily` mode a missed day resets the streak; in `visit` mode (for low-frequency
apps) the streak counts visits and never resets. Milestone days can award bonus
entries and a badge.

**Winner.** When one of your users is drawn, the drawer opens on a winner
splash instead of the dashboard and walks them through a stepped claim form
(name, shipping address, optional photo and story, review-and-agree), ending
with their claim number and a share step. When enabled on the platform, a
6-digit code emailed to the winning address is required first; the winning
email itself is never re-typed. A winner has a claim window of **3 days by
default** (configurable per giveaway by Avafli, 1–60 days); an expired claim
simply returns the drawer to the dashboard. The claim state lives on the
server, so a winner who closes the drawer, switches device or reinstalls
resumes where they left off. A "WE HAVE A WINNER!" banner and winner dialog
appear on the dashboard only when Avafli has enabled it for your account and
the giveaway carries a drawn winner.

**Shared giveaway.** If you opt into the shared giveaway (one prize pool across
many Avafli apps, Avafli LLC as Sponsor of Record), a small "Sponsored by
Avafli LLC" line renders under the prize wherever it is shown. It is legally
required and cannot be turned off. Exclusive giveaways show nothing extra.

**Legal pages.** The Official Rules (per giveaway) and the Privacy Policy
(`https://sdk.avafli.com/sdk/privacy`) open in an in-app web view. No
URL-scheme registration or integration work is needed.

**Account deletion.** Users delete their Avafli data themselves from the
Privacy Policy screen inside the experience (**Delete my data & stop
participating**): an identity-wide erasure, after which the experience stays
silent on that device for 24 hours and the person may then join again as a new
participant. There is nothing for the host app to do, and no API for it — a
host app cannot erase a person's Avafli data.

**Branding.** Logo, prize image and primary color come from the dashboard and
update instantly on every install. There is nothing to set in code.

Nothing in this section requires host-app code.

## 5. Controlling presentation

The auto-open is the default and needs no code. It fires after registration
completes on launch and again on every return to the foreground, at most once
per local calendar day, only while a giveaway is active, and only if the person
is not opted out and your account is not suspended. Unregistered users (no
confirmed email) see at most 3 auto-opens (server-configurable) until they
submit an email. The dashboard's `experience.autoOpenEnabled` kill switch stops
it remotely.

### Modes — `AvafliConfiguration.autoOpen`

| Mode | Behaviour |
| --- | --- |
| `.always` (default) | Auto-open once per day whenever eligible |
| `.returningUsersOnly` | Skip the auto-open for the one session in which this device registers for the first time (so first-run onboarding is never covered); every later launch auto-opens |
| `.never` | The SDK never opens on its own; you call `Avafli.present()` |

The dashboard can also set a server-side mode; the **most restrictive** of
server and client wins (`never` > `returningUsersOnly` > `always`), and the kill
switch beats everything. Device registration and analytics run on
`configure(_:)` in every mode.

### `Avafli.present(completion:)`

Opens the drawer yourself — from a button, a screen, the end of onboarding.
Call it on the main thread.

```swift
let accepted = Avafli.present { result in
    switch result {
    case .success(let grant):
        print("Avafli: +\(grant.total) entries today")   // base \(grant.baseEntries) + bonus \(grant.bonusEntries)
    case .failure(let error):
        print("Avafli could not open: \(error.localizedDescription)")
    }
}
```

- Applies the same guards as the auto-open (configured, not opted out, not
  suspended, an active giveaway exists **or** a prize claim is pending, not
  already on screen) but **bypasses** the once-per-day mark and the impression
  cap and never counts an impression.
- If registration is still in flight it returns `true` immediately and presents
  once registration settles — it never races the handshake.
- Returns `false` when refused right away; the completion then receives
  `.failure` with `.notConfigured`, `.optedOut`, `.serviceUnavailable`,
  `.giveawayNotActive` or `.noPresentingViewController`.
- `.success(DailyEntryGrant)` arrives **once, on the main thread, the moment
  that presentation records today's entries** — the drawer claims them
  automatically on open (a winner's silent claim behind the prize flow counts
  too). It is not called when nothing is claimed in that presentation: the day
  was already claimed, the person is still on email capture, or the claim
  failed and was queued for retry. The same moment is also reported as
  `avafli_daily_entry_claimed` through your `AnalyticsAdapter` (§8), which
  also covers the auto-open.
- When the drawer closes it writes the same once-per-day mark the auto-open
  writes, so the auto-open will not pop a second time that day.
- With a prize claim pending it opens on the winner splash.

### `Avafli.holdAutoOpen()` / `Avafli.releaseAutoOpen()`

For boot flows (splash, auth gate, onboarding) the drawer must not appear over:

```swift
Avafli.holdAutoOpen()          // before configure — nothing is burned while held
Avafli.configure(config)
// … later, once your main screen is up:
Avafli.releaseAutoOpen()       // re-runs the eligibility check immediately
```

Both are safe before `configure(_:)` and safe to call repeatedly. `present()`
still works while held.

### A pending prize claim is the one exception to "once per day"

While a winner's claim is waiting to be submitted the drawer reopens on every
cold launch, and on a return to the foreground once 30 minutes have passed since
the claim was last on screen — so a winner who closed it can always get back
inside the claim window. This ignores the daily mark, the impression cap and
`.returningUsersOnly`, and works when no giveaway is running. It still respects
`holdAutoOpen()`, opt-out, suspension, the kill switch and `.never` (on `.never`
you open the winner flow with `present()`). Once the claim is submitted the
normal once-per-day rule applies again.

## 6. Push reminders

Streak reminders are **off** until two things happen: you upload a Firebase
service-account key from your own Firebase project in the dashboard (Avafli
sends through *your* project), and your app forwards its FCM registration
token. Reminder schedule and copy are configured in the dashboard.

```swift
// 1. After Avafli.configure(_:) — asks for notification permission and
//    registers for APNs. No-op if AvafliOptions.enablePushReminders is false.
Avafli.registerForPushNotifications()

// 2. AppDelegate — forward the APNs callbacks
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Avafli.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}

func application(_ application: UIApplication,
                 didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Avafli.didFailToRegisterForRemoteNotifications(error: error)
}

// 3. MessagingDelegate — required for server-sent reminders
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let fcmToken { Avafli.didReceiveFCMToken(fcmToken) }
}
```

Without an FCM token (apps that do not use Firebase Messaging, or permission
denied) the SDK schedules a **local** daily reminder at 6 PM device time
("Don't lose your streak!"). The moment the backend accepts an FCM token the
SDK **cancels that local reminder and never re-arms it** on that install — a
person with server reminders never also gets the local nudge. The fallback
comes back only if APNs registration later fails or permission is revoked. You
can remove the local reminder yourself at any time with
`PushNotificationManager.shared.cancelStreakReminders()`. Set
`enablePushReminders: false` to opt out of reminders entirely.

## 7. Testing checklist

**Sandbox key.** Your dashboard shows an `avafli_test_…` key next to your live
key. Use it in debug builds and CI: same production backend, identical
behaviour, but every user, entry and streak lands in an isolated sandbox tenant
with its own always-active test giveaway. Testers can never enter or win your
real giveaway, sandbox usage never counts toward MAU or your bill, and your
registered bundle IDs work with both keys.

**Walk-through.**

1. Debug build with the sandbox key and `logging: .debug`. The console shows
   `AvafliSDK configured for production` then `Device registered: <id> (new user)`.
2. First launch → email-capture screen → submit → "You're in!" → dashboard shows
   Day 1 checked. Console: `avafli_daily_entry_claimed`.
3. Relaunch the same day → no auto-open (once per day). `Avafli.present()` still
   opens the drawer.
4. Advance the device/simulator clock to tomorrow (or wait) and relaunch →
   auto-open, Day 2 claimed automatically. Claims are de-duplicated server-side
   per local day, so a retried claim can never double-grant.
5. New-user path again: the SDK's session lives in the Keychain and survives a
   reinstall, so use a fresh simulator (**Device → Erase All Content and
   Settings**) or another device.
6. Boot-flow apps: confirm the drawer never covers your splash/onboarding
   (`holdAutoOpen()`/`releaseAutoOpen()` or `.returningUsersOnly`).
7. Push: with the service-account key uploaded and the FCM token forwarded, the
   console shows `Push token registered with backend`.
8. Deletion: Privacy Policy → **Delete my data & stop participating** →
   `present()` now returns `false` with `.optedOut`; after 24 hours the device
   registers as a new participant.
9. Winner flow: draws against a sandbox giveaway are allowed — ask Avafli
   support to draw your sandbox giveaway for a tester's email, then relaunch.
10. Release build: live key, `logging: .error`, bundle ID registered to the key.

The sample app in [`AvafliExample/`](AvafliExample/) is this integration
end-to-end (it uses Avafli's own demo publisher key, restricted to the sample's
bundle ID, so its demo buttons can reset state server-side).

## 8. API reference

Everything a host app calls. Full signatures, every type and every error case
are in [docs/API_REFERENCE.md](docs/API_REFERENCE.md); copy-paste recipes in
[docs/CODE_EXAMPLES.md](docs/CODE_EXAMPLES.md).

| Call | Purpose |
| --- | --- |
| `Avafli.configure(_ configuration: AvafliConfiguration)` | The integration. Registers the device, fetches the giveaway, arms the daily auto-open |
| `Avafli.present(completion:) -> Bool` | Open the drawer yourself; bypasses the daily mark; `.success(grant)` when that presentation claims today's entries |
| `Avafli.holdAutoOpen()` / `Avafli.releaseAutoOpen()` | Defer the auto-open around a boot flow |
| `Avafli.registerForPushNotifications()` | Permission + APNs registration (no-op when reminders are disabled) |
| `Avafli.didRegisterForRemoteNotifications(deviceToken:)` | Forward from `AppDelegate` |
| `Avafli.didFailToRegisterForRemoteNotifications(error:)` | Forward from `AppDelegate` |
| `Avafli.didReceiveFCMToken(_:)` | Forward from `MessagingDelegate` — required for server-sent reminders; cancels the local fallback once the backend accepts the token |
| `PushNotificationManager.shared.cancelStreakReminders()` | Remove the local fallback reminder yourself |

**Types:** `AvafliConfiguration`, `AvafliUser` (+ `.guest`), `AvafliOptions`,
`AvafliAutoOpen`, `AvafliEnvironment` (`.production` only), `AvafliError`,
`DailyEntryGrant`, `AnalyticsAdapter`, `ConsoleAnalyticsAdapter`,
`AvafliAnalyticsEvent`, `AvafliConstants`.

**Analytics.** Pass your own `AnalyticsAdapter` in `AvafliOptions` to forward
events to Mixpanel, Amplitude, Firebase, Segment, etc.:

```swift
final class MyAnalyticsAdapter: AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?) {
        Analytics.shared.track(event, properties: properties)
    }
}
```

Events the 3.3.2 experience emits: `avafli_experience_opened`,
`avafli_daily_entry_claimed`, `avafli_streak_milestone`, `avafli_badge_earned`,
`avafli_winner_claim_shown`, `avafli_prize_claim_submitted`. The default
adapter logs them to the Xcode console.

## 9. Links

- Dashboard: <https://sdk.avafli.com/dashboard>
- iOS docs: <https://sdk.avafli.com/ios>
- Pricing: <https://sdk.avafli.com/pricing>
- Platform status: <https://sdk.avafli.com/status>
- Privacy Policy shown in-app: <https://sdk.avafli.com/sdk/privacy>
- Free online entry (AMOE) form, per giveaway:
  `https://sdk.avafli.com/enter/<your-publisher-segment>/amoe?g=<giveawayId>`
  (exact link and copy button in the dashboard's Giveaway Management section)
- Source: <https://github.com/AVAFLI/avafli_ios_sdk>
- Support: <info@avafli.com>

---

© 2026 AVAFLI, LLC. Released under the [MIT License](LICENSE).
