# Avafli SDK — Getting Started Guide

## Overview

Avafli SDK enables app publishers to instantly add sweepstakes and prizing functionality to their iOS apps. Users earn daily entries on a simple +10-per-day streak ladder, claimed automatically when the drawer opens. The SDK handles device registration, token management, email capture (with explicit marketing consent and a publisher-configurable age gate), streak tracking, and entry submission behind a fully managed UI.

The V2 experience is a bottom drawer that opens itself on the first app-open of each day, claims the user's daily entries automatically, and celebrates the result. You integrate once; prize configuration and branding are managed server-side from the Avafli dashboard.

> This guide is a condensed walkthrough. The [README](../README.md) is the canonical reference for the current API surface.

---

## Requirements

| Requirement | Minimum Version |
|-------------|----------------|
| iOS | 15.0+ |
| Xcode | 15.0+ |
| Swift | 5.9+ |
| Publisher API Key | Contact info@avafli.com |

The SDK uses SwiftUI for its presentation layer and requires a UIKit host app (UIViewController-based presentation).

---

## Installation

### Swift Package Manager (Recommended)

1. In Xcode, go to **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/AVAFLI/avafli_ios_sdk.git
   ```
3. Set the dependency rule to **Up to Next Major Version** from `3.1.1`
4. Add the `AvafliSDK` library to your app target

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AVAFLI/avafli_ios_sdk.git", from: "3.1.1")
]
```

### CocoaPods


Add the pod to your `Podfile` and install:

```ruby
pod 'AvafliSDK', '~> 3.0'
```

```bash
pod install
```

---

## Configure the SDK

Call `Avafli.configure(_:)` once at app launch:

```swift
import AvafliSDK

let config = AvafliConfiguration(
    apiKey: "YOUR_API_KEY",
    bundleId: "com.example.myapp",
    user: AvafliUser(
        id: "user_123",
        firstName: "Jane",
        lastName: "Doe"
    )
)
Avafli.configure(config)
```

That's it. Configuration registers the device in the background and fetches the active giveaway. The experience then **auto-opens once per calendar day** — on launch and whenever the app returns to the foreground on a new day. Entries are claimed automatically when the drawer opens.

Auto-open behavior:

- It can be disabled remotely from the dashboard (`experience.autoOpenEnabled`).
- Unregistered users (no confirmed email) see at most 3 auto-opens, then the SDK goes quiet until they register.
- Users who opted out (Right-to-Delete) never see the experience again.

The auto-open is the only way the experience appears — there is no manual launch API. One call, and the experience opens itself once per day.

> **Email:** If your app has an authenticated session, pass the user's email via `AvafliUser(email:)`. The capture screen then shows that address pre-filled and **locked** (read-only) — Avafli links accounts across devices by email, so a partner-authenticated address is the most reliable identity. Consent remains an explicit act inside the Avafli flow: the user still sees the address, ticks the age (and optionally marketing) boxes, and submits. A malformed email is ignored and the field stays editable. If your app has no signed-in user, pass `AvafliUser.guest` — the SDK mints a stable per-install guest id and captures email through its own consent UI.
>
> Two email safeguards run inside that flow, no integration needed: typing an
> address that already belongs to an existing Avafli account requires a 6-digit
> code before the streak merges to this device (fresh signups and pre-filled
> partner emails skip it), and a brand-new typed address gets a soft "verify
> your email" chip on the dashboard — it never blocks daily play, only
> prize-draw eligibility.

---

## Test with Your Sandbox Key

Your dashboard shows a `avafli_test_…` key alongside your live key. Use it in
debug builds: same production backend, identical behavior, but users and
entries land in an isolated sandbox tenant — testers can never enter your real
giveaway, and sandbox usage never counts toward MAU. Your registered bundle
IDs work with both keys.

## Push Reminders

The SDK can nudge users to keep their streak alive. After configuring:

```swift
Avafli.registerForPushNotifications()  // no-op if AvafliOptions.enablePushReminders is false
```

Forward the APNs callbacks from your `AppDelegate`:

```swift
func application(_ application: UIApplication,
                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Avafli.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}

func application(_ application: UIApplication,
                 didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Avafli.didFailToRegisterForRemoteNotifications(error: error)
}
```

If your app uses Firebase Messaging, also forward the FCM registration token so Avafli's backend can send server-driven reminders through your Firebase project:

```swift
// MessagingDelegate
func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let fcmToken { Avafli.didReceiveFCMToken(fcmToken) }
}
```

Without an FCM token (or if notification permission is denied), the SDK falls back to a daily **local** reminder.

---

## Branding

The V2 experience is server-driven: logo, prize image, and primary accent color are configured in the [Avafli Dashboard](https://sdk.avafli.com/dashboard) and update without an app release. There is nothing to configure in code.

---

## Analytics

Route SDK events to your analytics stack by passing an `AnalyticsAdapter` in `AvafliOptions` — see [CODE_EXAMPLES.md](CODE_EXAMPLES.md) and the [README's Analytics section](../README.md#analytics) for the event list.

---

## Privacy & Account Deletion

- The SDK collects no advertising identifiers and never shows the App Tracking Transparency prompt.
- **Account deletion in your app:** if your app has its own delete-account flow, call `try await Avafli.optOut()` from it so the user's Avafli data is erased along with their account (identity-wide, PII scrubbed, survives reinstall — the experience is permanently silenced on this device).
- Users can also delete their data themselves at any time — no integration required: every legal link opens the Privacy Policy in an in-app webview, and its **Delete my data & stop participating** section confirms and performs the same erasure.
- `optOut()` is the only erasure API — de-identified entry records are retained as the legally required evidence that drawings were fair.

---

## Next Steps

- [API Reference](API_REFERENCE.md) — every public type and method
- [Code Examples](CODE_EXAMPLES.md) — copy-paste integration recipes
- [README](../README.md) — canonical overview and API tables
