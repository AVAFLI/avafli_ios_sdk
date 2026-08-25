//
//  StreakEngine.swift
//  AvafliSDK
//
//  Created by Ryan Napolitano on 11/25/25.
//

import Foundation

protocol StreakEngineProtocol {
    func nextState(from state: StreakState?, on date: Date) -> Result<StreakState, AvafliError>
    func baseEntries(forDay day: Int) -> Int
}

struct StreakEngine: StreakEngineProtocol {

    func nextState(from state: StreakState?, on date: Date) -> Result<StreakState, AvafliError> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        let currentWeekStart = getMondayOfWeek(date: date, calendar: calendar)
        let currentMonthFirst = getFirstOfMonth(date: date, calendar: calendar)
        
        guard let state = state else {
            // First time — initialize everything at 1
            return .success(StreakState(
                currentDay: 1, 
                lastClaimedDate: date, 
                totalEntriesEarned: 0,
                weeklyCurrent: 1,
                weeklyStart: currentWeekStart,
                monthlyCurrent: 1,
                monthlyStart: currentMonthFirst,
                lifetimeCount: 1
            ))
        }

        guard let last = state.lastClaimedDate else {
            return .success(StreakState(
                currentDay: 1, 
                lastClaimedDate: date, 
                totalEntriesEarned: state.totalEntriesEarned,
                weeklyCurrent: 1,
                weeklyStart: currentWeekStart,
                monthlyCurrent: 1,
                monthlyStart: currentMonthFirst,
                lifetimeCount: state.lifetimeCount + 1
            ))
        }

        if calendar.isDate(last, inSameDayAs: date) {
            return .failure(.ineligibleToday)
        }

        let days = calendar.dateComponents([.day], from: last, to: date).day ?? 0
        
        // Daily streak: max 7, resets on missed day
        let newDailyStreak: Int
        if days == 1 {
            newDailyStreak = min(state.currentDay + 1, 7)
        } else {
            newDailyStreak = 1 // Streak broken
        }
        
        // Weekly: only increments if daily streak is alive (consecutive), resets Monday
        let lastWeekStart = getMondayOfWeek(date: last, calendar: calendar)
        let newWeeklyCurrent: Int
        if currentWeekStart != lastWeekStart || days != 1 {
            // New week OR streak broken → reset weekly
            newWeeklyCurrent = 1
        } else {
            newWeeklyCurrent = state.weeklyCurrent + 1
        }
        
        // Monthly: independent — counts every unique day entered, resets 1st of month
        let newMonthlyCurrent: Int
        if state.monthlyStart == currentMonthFirst {
            newMonthlyCurrent = state.monthlyCurrent + 1
        } else {
            newMonthlyCurrent = 1 // New month
        }
        
        // Lifetime: never resets
        let newLifetimeCount = state.lifetimeCount + 1

        return .success(StreakState(
            currentDay: newDailyStreak,
            lastClaimedDate: date,
            totalEntriesEarned: state.totalEntriesEarned,
            weeklyCurrent: newWeeklyCurrent,
            weeklyStart: currentWeekStart,
            monthlyCurrent: newMonthlyCurrent,
            monthlyStart: currentMonthFirst,
            lifetimeCount: newLifetimeCount
        ))
    }

    func baseEntries(forDay day: Int) -> Int {
        // Default 7-day ladder; backend-driven via giveaway.streakLadder
        switch day {
        case 1: return 10
        case 2: return 30
        case 3: return 60
        case 4: return 130
        case 5: return 240
        case 6: return 300
        case 7: return 500
        default: return 60
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func getMondayOfWeek(date: Date, calendar: Calendar) -> String {
        let dayOfWeek = calendar.component(.weekday, from: date) // 1=Sun, 2=Mon, ..., 7=Sat
        let diff: Int
        if dayOfWeek == 1 {
            diff = -6 // Sunday → previous Monday
        } else {
            diff = 2 - dayOfWeek // e.g. Tue(3) → 2-3 = -1
        }
        let monday = calendar.date(byAdding: .day, value: diff, to: date)!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: monday)
    }
    
    private func getFirstOfMonth(date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: firstOfMonth)
    }
}
