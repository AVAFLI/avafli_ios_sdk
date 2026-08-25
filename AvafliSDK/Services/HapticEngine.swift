//
//  HapticEngine.swift
//  AvafliSDK
//
//  Centralized haptic feedback for the SDK experience.
//

import UIKit

enum HapticEngine {

    // MARK: - Impact

    /// Light tap — tile selections, minor interactions
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap — button presses
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy thud — important actions (claim, confirm)
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Notification

    /// Success — entry claimed, bonus confirmed
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning — streak about to break, already claimed
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error — failed action
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: - Celebration sequence

    /// Double-tap celebration pattern for big moments (daily claim, bonus confirm)
    static func celebrate() {
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        heavy.prepare()
        medium.prepare()

        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            medium.impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
