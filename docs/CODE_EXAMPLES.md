# Avafli iOS SDK — Code Examples

Copy-paste recipes that compile against 3.3.2. See the [README](../README.md)
for the walkthrough and [API_REFERENCE.md](API_REFERENCE.md) for signatures.

## 1. Minimal integration (UIKit lifecycle)

```swift
import UIKit
import AvafliSDK

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
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
            user: AvafliUser(id: "user_123", firstName: "Jane", lastName: "Doe"),
            options: AvafliOptions(logging: .debug)
        ))
        return true
    }
}
```

The drawer opens itself once per day and claims entries automatically. Events
go to the Xcode console through the default `ConsoleAnalyticsAdapter`.

## 2. SwiftUI `App` lifecycle

```swift
import SwiftUI
import AvafliSDK

@main
struct MyApp: App {
    init() {
        Avafli.configure(AvafliConfiguration(
            apiKey: "avafli_test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
            bundleId: Bundle.main.bundleIdentifier!,
            user: .guest                     // nobody signed in — the SDK mints a stable guest id
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

No `AppDelegate` is needed; the SDK presents over the key window's root view
controller once the scene is active.

## 3. Upgrade a guest to a signed-in user

```swift
// At launch, before sign-in
Avafli.configure(AvafliConfiguration(apiKey: apiKey, bundleId: bundleId, user: .guest))

// After sign-in — same call, real identity. Streak and session carry over.
Avafli.configure(AvafliConfiguration(
    apiKey: apiKey,
    bundleId: bundleId,
    user: AvafliUser(id: account.id, firstName: account.firstName, lastName: account.lastName, email: account.email)
))
```

## 4. Show the drawer after onboarding

```swift
// Launch — registers the device now, never auto-opens
Avafli.configure(AvafliConfiguration(
    apiKey: apiKey,
    bundleId: Bundle.main.bundleIdentifier!,
    user: AvafliUser(id: "user_123"),
    autoOpen: .never                // or .returningUsersOnly to skip only the first-ever session
))

// Onboarding-complete handler (main thread)
func onboardingDidComplete() {
    let accepted = Avafli.present { result in
        switch result {
        case .success(let grant):
            // Delivered once, on the main thread, the moment this presentation
            // recorded today's entries (the drawer claims automatically on open).
            print("Avafli: +\(grant.total) entries (base \(grant.baseEntries), bonus \(grant.bonusEntries))")
        case .failure(let error):
            print("Avafli could not open: \(error.localizedDescription)")
        }
    }
    if !accepted { print("Nothing to show right now") }
}
```

`present()` bypasses the once-per-day mark and the impression cap, waits for
registration if it is still in flight, and is a no-op if the drawer is already
open. `.success` is not called when that presentation claims nothing (already
claimed today, still on email capture, claim queued for retry); the auto-open
has no completion — example 6 shows the analytics event that covers both.

## 5. Hold the auto-open through a boot flow

```swift
// AppDelegate — before configure
Avafli.holdAutoOpen()
Avafli.configure(config)

// Main screen — once your root UI is on screen (e.g. viewDidAppear of your home controller)
Avafli.releaseAutoOpen()
```

Nothing is burned while held (no daily mark, no impression); `present()` still
works.

## 6. Forward events to your analytics stack

```swift
import AvafliSDK

final class SegmentAnalyticsAdapter: AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?) {
        Analytics.shared().track(event, properties: properties)

        if event == AvafliAnalyticsEvent.dailyEntryClaimed,
           let day = properties?["day"] as? Int,
           let entries = properties?["entries"] as? Int {
            print("Day \(day): +\(entries) entries")      // the moment today's entries were recorded
        }
    }
}

Avafli.configure(AvafliConfiguration(
    apiKey: apiKey,
    bundleId: Bundle.main.bundleIdentifier!,
    user: AvafliUser(id: "user_123"),
    options: AvafliOptions(logging: .info, analyticsAdapter: SegmentAnalyticsAdapter())
))
```

Events emitted in 3.3.2: `avafli_experience_opened`, `avafli_daily_entry_claimed`,
`avafli_streak_milestone`, `avafli_badge_earned`, `avafli_winner_claim_shown`,
`avafli_prize_claim_submitted` ([details](API_REFERENCE.md#avaflianalyticsevent)).
Pass `analyticsAdapter: nil` to receive nothing.

## 7. Push reminders (Firebase Messaging)

```swift
import UIKit
import FirebaseCore
import FirebaseMessaging
import AvafliSDK

final class AppDelegate: UIResponder, UIApplicationDelegate, MessagingDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

        Avafli.configure(config)
        Avafli.registerForPushNotifications()        // permission prompt + APNs registration
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Avafli.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Avafli.didFailToRegisterForRemoteNotifications(error: error)
    }

    // Required for server-sent reminders
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        if let fcmToken { Avafli.didReceiveFCMToken(fcmToken) }
    }
}
```

Upload a service-account key from the same Firebase project in the dashboard;
reminders are sent through your project. Without an FCM token the SDK falls
back to a local 6 PM reminder; once the backend accepts the FCM token that
local reminder is cancelled automatically and not re-armed on that install.
You can also remove it yourself with
`PushNotificationManager.shared.cancelStreakReminders()`.

## 8. Turn reminders off

```swift
AvafliOptions(enablePushReminders: false)   // registerForPushNotifications() becomes a no-op
```

## 9. Account deletion

There is nothing to integrate and no API: users delete their own Avafli data
from the Privacy Policy screen inside the experience (**Delete my data & stop
participating**). A host app cannot erase a person's Avafli data (`optOut()`
left the public surface in 3.3.2).

## 10. Handle `present()` refusals

```swift
Avafli.present { result in
    guard case .failure(let error) = result else { return }
    switch error {
    case .optedOut:            break   // user deleted their data; rejoin possible after 24 h
    case .giveawayNotActive:   break   // nothing running (or registration failed) — hide your entry point
    case .serviceUnavailable:  break   // account suspended — hide your entry point
    case .notConfigured:       break   // configure(_:) was not called
    case .noPresentingViewController: break
    default:                   break
    }
}
```
