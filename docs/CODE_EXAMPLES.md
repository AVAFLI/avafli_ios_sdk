# Avafli SDK — Code Examples

Real-world integration examples for common use cases. See the [README](../README.md) for the canonical API overview.

---

## 1. Minimal Integration

Configure once at launch — the experience auto-opens on the first app-open of each day and claims entries automatically:

```swift
import AvafliSDK

// AppDelegate.swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    let config = AvafliConfiguration(
        apiKey: "YOUR_API_KEY",
        environment: .production,
        bundleId: Bundle.main.bundleIdentifier ?? "",
        user: AvafliUser(
            id: "user_123",
            firstName: "Jane",
            lastName: "Doe"
        )
    )
    Avafli.configure(config)
    return true
}
```

Uses `ConsoleAnalyticsAdapter` (logs to Xcode console) by default. Branding is server-driven — nothing to configure in code. The experience is exclusively auto-opened by the SDK; there is no manual launch API.

---

## 2. SwiftUI App Integration

```swift
import SwiftUI
import AvafliSDK

@main
struct MyApp: App {
    init() {
        Avafli.configure(AvafliConfiguration(
            apiKey: "YOUR_API_KEY",
            environment: .production,
            bundleId: Bundle.main.bundleIdentifier ?? "",
            user: AvafliUser(id: "user_123", firstName: "Jane", lastName: "Doe")
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

The auto-open flow needs no further wiring — the experience opens itself once per day.

---

## 3. Push Notification Wiring

```swift
import AvafliSDK
import FirebaseMessaging

// After Avafli.configure(...)
Avafli.registerForPushNotifications()

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

Apps without Firebase Messaging still get a daily **local** streak reminder as a fallback.

---

## 4. Custom Analytics Adapter

```swift
import AvafliSDK

final class SegmentAnalyticsAdapter: AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?) {
        Analytics.shared().track(event, properties: properties)
    }
}

let config = AvafliConfiguration(
    apiKey: "YOUR_API_KEY",
    environment: .production,
    bundleId: Bundle.main.bundleIdentifier ?? "",
    user: AvafliUser(id: "user_123", firstName: "Jane", lastName: "Doe"),
    options: AvafliOptions(
        logging: .info,
        analyticsAdapter: SegmentAnalyticsAdapter(),
        enablePushReminders: true
    )
)
Avafli.configure(config)
```

See the [event list](API_REFERENCE.md#avaflianalyticsevent) for everything the SDK emits.

---

## 5. Account Deletion in Your App

If your app has its own delete-account flow, call `optOut()` from it so the
user's Avafli data is erased along with their account. It scrubs the person's
PII everywhere (including prize-claim records), links their devices so one call
covers all of them, tombstones so it survives a reinstall, and permanently
silences the experience:

```swift
// From your delete-account flow
Task {
    do {
        try await Avafli.optOut()
        print("Avafli data erased; experience permanently silenced.")
    } catch {
        print("Opt-out failed: \(error)")
    }
}
```

Users can also delete their data themselves at any time — no integration
required: the Privacy Policy opens in an in-app webview from any legal link,
and its **Delete my data & stop participating** section confirms and runs the
same erasure.

---

## 6. Environments

```swift
let environment: AvafliEnvironment = .production  // production-only
```
