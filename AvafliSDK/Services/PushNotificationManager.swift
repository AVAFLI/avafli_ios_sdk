//
//  PushNotificationManager.swift
//  AvafliSDK
//
//  Push notification support for streak reminders.
//  Uses APNs token directly — does NOT require Firebase Messaging.
//

import Foundation
import UserNotifications
import UIKit

/// Manages push notification registration and local notification fallback for streak reminders.
public final class PushNotificationManager: NSObject {

    public static let shared = PushNotificationManager()

    private var apnsToken: Data?
    /// The backend accepted an FCM token in THIS process.
    private var isRegistered = false

    /// Identifier of the local fallback reminder.
    static let localReminderIdentifier = "winr-streak-reminder"
    /// Persisted "the backend holds a push token for this install" flag
    /// (3.3.2). While set, the local fallback is never (re)armed — not even
    /// on the next launch, before the FCM token is forwarded again — so a
    /// person with working server reminders never also gets the local nudge.
    /// Cleared when APNs registration fails or permission is denied (the
    /// server could not reach the device either way), re-arming the fallback.
    static let tokenRegisteredKey = "winr_push_token_registered"

    private let defaults: UserDefaults

    private override init() {
        self.defaults = .standard
        super.init()
    }

    /// Test seam.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        super.init()
    }

    /// Whether a push token is known to the backend (this process, or
    /// persisted from an earlier launch).
    var hasServerPushToken: Bool {
        isRegistered || defaults.bool(forKey: Self.tokenRegisteredKey)
    }

    // MARK: - Public API

    /// Requests notification permission, registers for remote notifications,
    /// and sends the APNs token to the Avafli backend.
    public func register() {
        requestPermission { [weak self] granted in
            guard granted else {
                Logger.shared.log("Push notification permission denied, scheduling local fallback", level: .info)
                self?.forgetServerPushToken()
                self?.scheduleLocalStreakReminder()
                return
            }

            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }

            Logger.shared.log("Push notification permission granted", level: .info)
        }
    }

    /// Call this from your AppDelegate's `didRegisterForRemoteNotificationsWithDeviceToken`.
    ///
    /// NOTE: the Avafli backend delivers reminders through Firebase Cloud Messaging,
    /// which cannot address a raw APNs token — apps using Firebase Messaging should
    /// forward the FCM registration token via `didReceiveFCMToken(_:)` instead.
    /// Without an FCM token the SDK still nudges users via the local-notification
    /// fallback, so calling only this method is safe but server pushes won't send.
    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        self.apnsToken = deviceToken
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Logger.shared.log("APNs token received: \(tokenString.prefix(16))... (forward your FCM token for server pushes)", level: .debug)
        // Ensure the local fallback is armed until an FCM token arrives —
        // unless the backend already holds a token for this install.
        scheduleLocalStreakReminder()
    }

    /// Forward the Firebase Messaging registration token (from your
    /// `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)`) so the Avafli
    /// backend can send streak reminders through your Firebase project. Once the
    /// backend accepts it the local fallback reminder is cancelled.
    public func didReceiveFCMToken(_ token: String) {
        guard !token.isEmpty else { return }
        Task {
            await sendTokenToBackend(token: token)
        }
    }

    /// Call this from your AppDelegate's `didFailToRegisterForRemoteNotificationsWithError`.
    /// Falls back to local notifications.
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        Logger.shared.log("Remote notification registration failed: \(error.localizedDescription)", level: .error)
        forgetServerPushToken()
        scheduleLocalStreakReminder()
    }

    // MARK: - Permission

    private func requestPermission(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                Logger.shared.log("Notification permission error: \(error.localizedDescription)", level: .error)
            }
            completion(granted)
        }
    }

    // MARK: - Backend Token Registration

    private func sendTokenToBackend(token: String) async {
        guard !isRegistered else { return }

        let keychain = KeychainStorage()
        guard keychain.loadToken() != nil,
              let configuration = Avafli._configurationForTests() else {
            Logger.shared.log("Cannot register push token: SDK not configured or not authenticated", level: .debug)
            return
        }

        let baseURL = URL(string: "https://us-central1-winr-9c11f.cloudfunctions.net")!
        let network = URLSessionNetworkClient(
            baseURL: baseURL,
            apiKey: configuration.apiKey,
            tokenProvider: { keychain.loadToken() },
            enablePinning: false
        )

        do {
            let request = RegisterPushTokenRequest(token: token, platform: "ios")
            let _ = try await network.send(request)
            noteServerPushTokenRegistered()
            Logger.shared.log("Push token registered with backend", level: .info)
        } catch {
            Logger.shared.log("Failed to register push token: \(error)", level: .error)
        }
    }

    /// The backend accepted a token: remember it and drop the local fallback
    /// so server reminders are the only reminders.
    func noteServerPushTokenRegistered() {
        isRegistered = true
        defaults.set(true, forKey: Self.tokenRegisteredKey)
        cancelStreakReminders()
        Logger.shared.log("Local streak reminder cancelled — server reminders take over", level: .debug)
    }

    /// The server can no longer reach this device (APNs failed / permission
    /// denied): forget the token so the local fallback may be armed again.
    func forgetServerPushToken() {
        isRegistered = false
        defaults.removeObject(forKey: Self.tokenRegisteredKey)
    }

    // MARK: - Local Notification Fallback

    /// Schedules a daily local notification as fallback when push isn't available.
    /// A no-op while the backend holds a push token for this install (3.3.2) —
    /// server reminders and the local nudge are never both armed.
    public func scheduleLocalStreakReminder() {
        guard !hasServerPushToken else {
            Logger.shared.log("Local streak reminder not scheduled: server push token registered", level: .debug)
            return
        }
        let center = UNUserNotificationCenter.current()

        // Remove any existing streak reminders
        center.removePendingNotificationRequests(withIdentifiers: [Self.localReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "Don't lose your streak!"
        content.body = "Come back to claim your daily entries 🔥"
        content.sound = .default

        // Schedule for tomorrow at 6 PM local time
        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.localReminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                Logger.shared.log("Failed to schedule local streak reminder: \(error)", level: .error)
            } else {
                Logger.shared.log("Local streak reminder scheduled", level: .debug)
            }
        }
    }

    /// Cancels all scheduled streak reminders.
    public func cancelStreakReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.localReminderIdentifier])
    }
}
