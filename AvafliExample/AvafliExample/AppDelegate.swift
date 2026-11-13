//
//  AppDelegate.swift
//  AvafliExample
//
//  The Avafli integration, end to end. Copy this pattern into your own
//  AppDelegate (or your SwiftUI App's init()).
//

import UIKit
import AvafliSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ┌──────────────────────────────────────────────────────────────┐
        // │  Avafli.configure(_:) is the whole integration.              │
        // │                                                              │
        // │  apiKey   — from https://sdk.avafli.com/dashboard. Use your  │
        // │             avafli_test_ sandbox key in debug builds and     │
        // │             your avafli_live_ key in release builds.         │
        // │  bundleId — must be registered to that key in the dashboard. │
        // │  user     — your app's stable user id; name and email are    │
        // │             optional (the SDK captures the email through its │
        // │             own consent screen; a winner is asked for their  │
        // │             name at prize claim). Nobody signed in? .guest   │
        // │                                                              │
        // │  Branding (logo, prize image, primary color), the entry      │
        // │  ladder and reminder schedules are set in the dashboard —    │
        // │  nothing to configure in code.                               │
        // └──────────────────────────────────────────────────────────────┘

        // In a real app, use YOUR authenticated user's id here. This sample
        // keeps a stable id per install so relaunches are the same user.
        let userId = UserDefaults.standard.string(forKey: "avafli_example_user_id") ?? {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "avafli_example_user_id")
            return id
        }()

        // This sample deliberately uses Avafli's own DEMO publisher key instead
        // of a sandbox key: it is server-side restricted to the sample's bundle
        // id, and the demo buttons on the main screen (reset claim, make me the
        // winner, …) only work against that publisher. In YOUR app, load your
        // key from a non-committed source (an .xcconfig build setting surfaced
        // via Info.plist, or your secrets manager) — never commit a live key.
        let config = AvafliConfiguration(
            apiKey: "winr_live_50b1b3b801a843d5e1f99593fcad4d14",
            bundleId: Bundle.main.bundleIdentifier ?? "com.avafli.winr.example",
            user: AvafliUser(
                id: userId,
                firstName: "Demo",
                lastName: "User"
            ),
            options: AvafliOptions(
                logging: .debug          // use .error in release builds
            ),
            autoOpen: .always            // default; .returningUsersOnly / .never to control timing yourself
        )

        Avafli.configure(config)

        // Streak reminders: also call Avafli.registerForPushNotifications()
        // after configure (it asks for notification permission, so this sample
        // leaves it out) and upload a Firebase service-account key in the
        // dashboard. Forward your FCM token from MessagingDelegate:
        //   Avafli.didReceiveFCMToken(fcmToken)

        return true
    }

    // MARK: - Push notifications — forward the APNs callbacks

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Avafli.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Avafli.didFailToRegisterForRemoteNotifications(error: error)
    }

    // MARK: - Scene Configuration

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}
}
