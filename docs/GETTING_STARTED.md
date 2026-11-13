# Avafli iOS SDK — Getting Started

A 15-minute path from an empty project to a working daily-entry sweepstakes.
The [README](../README.md) covers the same ground in more depth;
[API_REFERENCE.md](API_REFERENCE.md) lists every public symbol.

## 1. Requirements

- iOS 15.0+, Xcode 15.0+, Swift 5.9+
- A UIKit app (`AppDelegate`/`SceneDelegate`) or a SwiftUI `App` — the drawer
  is presented over the key window's root view controller
- A publisher API key from the [Avafli dashboard](https://sdk.avafli.com/dashboard)
  ([pricing](https://sdk.avafli.com/pricing)), with your app's bundle ID
  registered to it

## 2. Install

Module, SPM product and pod are all named `AvafliSDK`.

**Swift Package Manager** — Xcode: *File → Add Package Dependencies…* →
`https://github.com/AVAFLI/avafli_ios_sdk.git` → *Up to Next Major Version*
from `3.3.2` → add `AvafliSDK` to your app target. Or:

```swift
.package(url: "https://github.com/AVAFLI/avafli_ios_sdk.git", from: "3.3.2")
```

**CocoaPods**

```ruby
pod 'AvafliSDK', '~> 3.3'
```

## 3. Configure

One call at launch. Use the `avafli_test_…` sandbox key from your dashboard in
debug builds and the `avafli_live_…` key in release builds.

```swift
import AvafliSDK

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    #if DEBUG
    let apiKey = "avafli_test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    #else
    let apiKey = "avafli_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    #endif

    Avafli.configure(AvafliConfiguration(
        apiKey: apiKey,
        bundleId: Bundle.main.bundleIdentifier!,
        user: AvafliUser(id: "user_123"),          // or .guest when nobody is signed in
        options: AvafliOptions(logging: .debug)    // .error for release
    ))
    return true
}
```

SwiftUI lifecycle: put the same `Avafli.configure(...)` call in your `App`'s
`init()`.

That is the integration. The SDK registers the device in the background,
fetches the active giveaway and opens the drawer once per calendar day — on
launch and whenever the app returns to the foreground on a new day. Entries are
claimed automatically when it opens.

**Identity.** Only `id` is required. Add `firstName`/`lastName` if you have
them (otherwise the SDK asks a winner at prize claim) and `email` if your
session is authenticated — a passed email is pre-filled and locked on the
capture screen, but consent is still an explicit tick inside the flow. With
`.guest` the SDK mints a stable per-install id; when the person signs in, call
`configure` again with the real user and the streak carries over.

## 4. What the user sees

- **Day 1:** email-capture screen (prize card, email, age checkbox, unchecked
  marketing consent) → "You're in!" → dashboard with Day 1 claimed. An email
  that already belongs to another device's account needs a 6-digit code first.
- **Later days:** the drawer opens once a day, claims automatically and
  celebrates; the user taps **GOT IT**. The entry ladder, streak mode (`daily`
  resets on a miss; `visit` never resets) and milestones are set per giveaway
  in the dashboard.
- **Winner:** the drawer opens on a winner splash and a stepped claim form
  (3-day claim window by default). The claim is keyed to the account
  server-side; nothing for you to do.
- **Shared giveaway:** if you opt in, a required "Sponsored by Avafli LLC" line
  appears under the prize.
- **Legal:** Official Rules and the Privacy Policy open in an in-app web view;
  the policy includes **Delete my data & stop participating**.
- **Branding:** logo, prize image and primary color come from the dashboard.

## 5. Controlling presentation

Default: auto-open once per day. Three controls when you need them —
registration and analytics still run on `configure(_:)` in every mode.

| Control | Use it when |
| --- | --- |
| `autoOpen: .returningUsersOnly` | You have first-run onboarding. Skips the auto-open only in the session where the device first registers |
| `autoOpen: .never` + `Avafli.present()` | You decide the moment (a button, a screen, onboarding complete) |
| `Avafli.holdAutoOpen()` before `configure`, `Avafli.releaseAutoOpen()` when your main screen is up | Your boot flow (splash, auth gate) must not be covered. Nothing is burned while held; `present()` still works |

```swift
Avafli.configure(AvafliConfiguration(
    apiKey: apiKey,
    bundleId: Bundle.main.bundleIdentifier!,
    user: AvafliUser(id: "user_123"),
    autoOpen: .never
))

// Later — e.g. from your onboarding-complete handler (main thread)
let accepted = Avafli.present { result in
    switch result {
    case .success(let grant): print("Avafli: +\(grant.total) entries today")
    case .failure(let error): print("Avafli: \(error.localizedDescription)")
    }
}
```

`present()` bypasses the once-per-day mark and the impression cap, waits for
registration if it is still in flight, and returns `false` (with a `.failure`
completion) when there is nothing to show: not configured, opted out,
suspended, no active giveaway and no pending claim, or no presenting view
controller. `.success(grant)` arrives once, on the main thread, the moment that
presentation records today's entries (the drawer claims automatically); it is
not called when nothing is claimed in that presentation. The auto-open has no
completion — `avafli_daily_entry_claimed` through your analytics adapter
covers both.

The dashboard can set a server-side mode too; the most restrictive wins, and
its `autoOpenEnabled` kill switch beats everything. A winner with a pending
claim reopens the drawer on every cold launch (and on foreground after 30
minutes) regardless of the daily mark, so they can always finish the claim.

## 6. Push reminders

Reminders are sent through **your** Firebase project. Upload a service-account
key in the dashboard, then forward the tokens:

```swift
Avafli.registerForPushNotifications()   // after configure; no-op if enablePushReminders is false

// AppDelegate
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Avafli.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}
func application(_ application: UIApplication,
                 didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Avafli.didFailToRegisterForRemoteNotifications(error: error)
}

// MessagingDelegate — required for server-sent reminders
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let fcmToken { Avafli.didReceiveFCMToken(fcmToken) }
}
```

Without an FCM token (or with permission denied) the SDK schedules a local
daily reminder at 6 PM device time instead; once the backend accepts the FCM
token that local reminder is cancelled and not re-armed on that install.
`enablePushReminders: false` turns reminders off entirely.

## 7. Account deletion

Users delete their data themselves from the Privacy Policy screen inside the
experience (**Delete my data & stop participating**). The erasure is
identity-wide; for 24 hours `present()` is refused with `.optedOut`, then the
person may join again as a brand-new participant and the SDK handles that on
its own. There is nothing for your app to do and no API for it — a host app
cannot erase a person's Avafli data.

## 8. Testing checklist

1. Debug build, `avafli_test_…` key, `logging: .debug`. Look for
   `Device registered: … (new user)` in the console.
2. First launch: email capture → "You're in!" → Day 1 claimed.
3. Relaunch the same day: no auto-open; `Avafli.present()` still opens it.
4. Set the simulator clock to tomorrow and relaunch: auto-open, Day 2 claimed.
5. Fresh user: erase the simulator (the session lives in the Keychain and
   survives a reinstall) or use another device.
6. Boot flow: the drawer never covers your splash/onboarding.
7. Push: `Push token registered with backend` appears after the FCM token is
   forwarded.
8. Deletion: Privacy Policy → Delete my data → `present()` refused with
   `.optedOut`.
9. Winner flow: ask Avafli support to draw your sandbox giveaway for a tester.
10. Release build: live key, `logging: .error`.

Sandbox facts: same backend, isolated tenant, always-active test giveaway,
never billed, your registered bundle IDs accepted. Testers can never enter
your real giveaway.

## 9. Free online entry (AMOE)

Every giveaway has a public free-entry form at
`https://sdk.avafli.com/enter/<your-publisher-segment>/amoe?g=<giveawayId>` —
the dashboard's Giveaway Management section shows the exact URL with a copy
button and lets you customise the part after your publisher segment (the
segment itself is assigned by Avafli; old links keep working). List it as the
Online AMOE Web URL in your Client Addendum (Official Rules §11(E)). Entries
made there join the same drawing pool and never earn streak bonuses. Nothing to
integrate.

## Next

- [API_REFERENCE.md](API_REFERENCE.md) — every public type and method
- [CODE_EXAMPLES.md](CODE_EXAMPLES.md) — copy-paste recipes
- [CHANGELOG.md](../CHANGELOG.md) — what changed in each release
