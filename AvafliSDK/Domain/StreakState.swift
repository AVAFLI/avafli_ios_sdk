//
//  StreakState.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

struct StreakState: Codable {
    var currentDay: Int           // daily streak (1-7, resets Monday + on missed day)
    var lastClaimedDate: Date?
    var totalEntriesEarned: Int
    var weeklyCurrent: Int        // days claimed this week (only if daily streak alive, resets Monday)
    var weeklyStart: String?      // YYYY-MM-DD of current week's Monday
    var monthlyCurrent: Int       // unique days entered this month (independent of streak, resets 1st)
    var monthlyStart: String?     // YYYY-MM-01 of current month
    var lifetimeCount: Int        // total daily claims, never resets
    
    init(currentDay: Int = 1, lastClaimedDate: Date? = nil, totalEntriesEarned: Int = 0, weeklyCurrent: Int = 0, weeklyStart: String? = nil, monthlyCurrent: Int = 0, monthlyStart: String? = nil, lifetimeCount: Int = 0) {
        self.currentDay = currentDay
        self.lastClaimedDate = lastClaimedDate
        self.totalEntriesEarned = totalEntriesEarned
        self.weeklyCurrent = weeklyCurrent
        self.weeklyStart = weeklyStart
        self.monthlyCurrent = monthlyCurrent
        self.monthlyStart = monthlyStart
        self.lifetimeCount = lifetimeCount
    }
    
    // Custom decoder: gracefully handle missing fields from old stored data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentDay = try container.decode(Int.self, forKey: .currentDay)
        lastClaimedDate = try container.decodeIfPresent(Date.self, forKey: .lastClaimedDate)
        totalEntriesEarned = try container.decode(Int.self, forKey: .totalEntriesEarned)
        weeklyCurrent = try container.decodeIfPresent(Int.self, forKey: .weeklyCurrent) ?? 0
        weeklyStart = try container.decodeIfPresent(String.self, forKey: .weeklyStart)
        monthlyCurrent = try container.decodeIfPresent(Int.self, forKey: .monthlyCurrent) ?? 0
        monthlyStart = try container.decodeIfPresent(String.self, forKey: .monthlyStart)
        lifetimeCount = try container.decodeIfPresent(Int.self, forKey: .lifetimeCount) ?? 0
    }
}
