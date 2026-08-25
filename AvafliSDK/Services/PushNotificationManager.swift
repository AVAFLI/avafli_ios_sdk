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
    private var isRegistered = false
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Requests notification permission, registers for remote notifications,
    /// and sends the APNs token to the Avafli backend.
    public func register() {
        requestPermission { [weak self] granted in
            guard granted else {
                Logger.shared.log("Push notification permission denied, scheduling local fallback", level: .info)
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
        // Ensure the local fallback is armed until an FCM token arrives.
        if !isRegistered { scheduleLocalStreakReminder() }
    }

    /// Forward the Firebase Messaging registration token (from your
    /// `MessagingDelegate.messaging(_:didReceiveRegistrationToken:)`) so the Avafli
    /// backend can send streak reminders through your Firebase project.
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
            isRegistered = true
            Logger.shared.log("Push token registered with backend", level: .info)
        } catch {
            Logger.shared.log("Failed to register push token: \(error)", level: .error)
        }
    }
    
    // MARK: - Local Notification Fallback
    
    /// Schedules a daily local notification as fallback when push isn't available.
    public func scheduleLocalStreakReminder() {
        let center = UNUserNotificationCenter.current()
        
        // Remove any existing streak reminders
        center.removePendingNotificationRequests(withIdentifiers: ["winr-streak-reminder"])
        
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
            identifier: "winr-streak-reminder",
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
            .removePendingNotificationRequests(withIdentifiers: ["winr-streak-reminder"])
    }
}
