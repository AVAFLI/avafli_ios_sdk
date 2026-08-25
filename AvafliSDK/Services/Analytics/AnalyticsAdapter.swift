//
//  AnalyticsAdapter.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

// MARK: - Protocol

/// A protocol that publishers implement to route Avafli SDK analytics events
/// to their analytics backend (Firebase Analytics, Amplitude, Mixpanel, etc.).
///
/// The SDK ships with ``ConsoleAnalyticsAdapter`` as the default so it works
/// out of the box without any wiring.
public protocol AnalyticsAdapter {
    func track(event: String, properties: [String: Any]?)
}

// MARK: - Event Constants

public enum AvafliAnalyticsEvent {
    public static let registration              = "avafli_registration"
    public static let experienceOpened           = "avafli_experience_opened"
    public static let experienceClosed           = "avafli_experience_closed"
    public static let dailyEntryClaimed          = "avafli_daily_entry_claimed"
    public static let bonusEntryClaimed          = "avafli_bonus_entry_claimed"
    public static let streakMilestone            = "avafli_streak_milestone"
    public static let prizeWon                   = "avafli_prize_won"

    // Legacy aliases kept for backwards compatibility
    public static let experiencePresented        = experienceOpened
    public static let dailyEntriesClaimed        = dailyEntryClaimed
}

// MARK: - Convenience helpers

public extension AnalyticsAdapter {

    func trackRegistration(userId: String) {
        track(event: AvafliAnalyticsEvent.registration, properties: ["user_id": userId])
    }

    func trackExperienceOpened(giveawayId: String? = nil) {
        var props: [String: Any] = [:]
        if let id = giveawayId { props["giveaway_id"] = id }
        track(event: AvafliAnalyticsEvent.experienceOpened, properties: props)
    }

    func trackExperienceClosed(giveawayId: String? = nil) {
        var props: [String: Any] = [:]
        if let id = giveawayId { props["giveaway_id"] = id }
        track(event: AvafliAnalyticsEvent.experienceClosed, properties: props)
    }

    func trackDailyEntryClaimed(day: Int, entries: Int) {
        track(event: AvafliAnalyticsEvent.dailyEntryClaimed, properties: [
            "day": day,
            "entries": entries
        ])
    }

    func trackBonusEntryClaimed(source: String, entries: Int) {
        track(event: AvafliAnalyticsEvent.bonusEntryClaimed, properties: [
            "source": source,
            "entries": entries
        ])
    }

    func trackStreakMilestone(day: Int, bonusEntries: Int) {
        track(event: AvafliAnalyticsEvent.streakMilestone, properties: [
            "streak_day": day,
            "bonus_entries": bonusEntries
        ])
    }

    func trackPrizeWon(prizeName: String, prizeValue: String? = nil) {
        var props: [String: Any] = ["prize_name": prizeName]
        if let value = prizeValue { props["prize_value"] = value }
        track(event: AvafliAnalyticsEvent.prizeWon, properties: props)
    }
}
