//
//  Giveaway.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

struct Giveaway: Codable {
    let id: String
    let title: String
    let period: GiveawayPeriod
    let maxDailyBaseEntries: Int
    let doublingEnabled: Bool
    let streakConfig: StreakConfig
}

struct StreakConfig: Codable {
    let weeklyResetDay: Int
    let monthlyResetDay: Int
    // Legacy fields (kept for backward compat)
    let weeklyBonusThreshold: Int?
    let weeklyBonusEntries: Int?
    let monthlyBonusThreshold: Int?
    let monthlyBonusEntries: Int?
    // New monthly milestone tiers
    let monthlyMilestones: [MonthlyMilestoneConfig]?
}

struct MonthlyMilestoneConfig: Codable {
    let day: Int
    let bonusEntries: Int
    let badge: String?
}

enum GiveawayPeriod: String, Codable {
    case monthly
}
