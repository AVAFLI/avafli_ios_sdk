# ``AvafliSDK``

Drop-in daily-entry sweepstakes for iOS apps.

## Overview

Avafli adds a daily-entry sweepstakes to your app. A bottom drawer opens itself on the first app-open of each day, claims the user's entries automatically and celebrates the streak. You call ``Avafli/configure(_:)`` once; prizes, the entry ladder, branding and reminder schedules are managed from the Avafli dashboard and change without an app release.

```swift
import AvafliSDK

Avafli.configure(AvafliConfiguration(
    apiKey: "avafli_test_…",                 // sandbox key for debug builds; avafli_live_… in release
    bundleId: Bundle.main.bundleIdentifier!,
    user: AvafliUser(id: "user_123")         // or .guest
))
```

Requirements: iOS 15.0+, Xcode 15.0+, Swift 5.9+. Install with Swift Package Manager (`https://github.com/AVAFLI/avafli_ios_sdk.git`, from 3.3.0) or CocoaPods (`pod 'AvafliSDK', '~> 3.3'`).

## Topics

### Integration

- ``Avafli``
- ``AvafliConfiguration``
- ``AvafliUser``
- ``AvafliOptions``
- ``AvafliEnvironment``

### Controlling presentation

- ``AvafliAutoOpen``
- ``Avafli/present(completion:)``
- ``Avafli/holdAutoOpen()``
- ``Avafli/releaseAutoOpen()``

### Push reminders

- ``Avafli/registerForPushNotifications()``
- ``Avafli/didRegisterForRemoteNotifications(deviceToken:)``
- ``Avafli/didReceiveFCMToken(_:)``
- ``Avafli/didFailToRegisterForRemoteNotifications(error:)``
- ``PushNotificationManager``

### Account deletion

- ``Avafli/optOut()``

### Analytics

- ``AnalyticsAdapter``
- ``ConsoleAnalyticsAdapter``
- ``AvafliAnalyticsEvent``

### Results and errors

- ``DailyEntryGrant``
- ``AvafliError``
- ``AvafliConstants``

### Server-driven theme (not for host use)

- ``AvafliBranding``
- ``AvafliLogo``
