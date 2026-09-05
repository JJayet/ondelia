import Foundation
import SwiftData

@MainActor
@Observable
final class ReadingStatistics {
    static let shared = ReadingStatistics()
    private let swiftDataController = SwiftDataController.shared
    
    var totalListeningTime: TimeInterval = 0
    var booksCompleted: Int = 0
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var monthlyGoal: TimeInterval = 3600 * 10 // 10 hours default
    var monthlyProgress: TimeInterval = 0
    private var monthlyAnchor: Date = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    
    init() {
        loadStatistics()
        calculateCurrentMonthProgress()
    }
    
    private func loadStatistics() {
        totalListeningTime = UserDefaults.standard.double(forKey: "totalListeningTime")
        booksCompleted = UserDefaults.standard.integer(forKey: "booksCompleted")
        currentStreak = UserDefaults.standard.integer(forKey: "currentStreak")
        longestStreak = UserDefaults.standard.integer(forKey: "longestStreak")
        monthlyGoal = UserDefaults.standard.double(forKey: "monthlyGoal")
        monthlyProgress = UserDefaults.standard.double(forKey: "monthlyProgress")
        if let anchor = UserDefaults.standard.object(forKey: "monthlyAnchor") as? Date {
            monthlyAnchor = anchor
        }
        
        if monthlyGoal == 0 {
            monthlyGoal = 3600 * 10 // Default 10 hours
        }
    }
    
    private func saveStatistics() {
        UserDefaults.standard.set(totalListeningTime, forKey: "totalListeningTime")
        UserDefaults.standard.set(booksCompleted, forKey: "booksCompleted")
        UserDefaults.standard.set(currentStreak, forKey: "currentStreak")
        UserDefaults.standard.set(longestStreak, forKey: "longestStreak")
        UserDefaults.standard.set(monthlyGoal, forKey: "monthlyGoal")
        UserDefaults.standard.set(monthlyProgress, forKey: "monthlyProgress")
        UserDefaults.standard.set(monthlyAnchor, forKey: "monthlyAnchor")
    }
    
    @MainActor
    func addListeningTime(_ time: TimeInterval) {
        // Ensure current month anchor and reset if the month rolled over
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        if startOfMonth != monthlyAnchor {
            monthlyAnchor = startOfMonth
            monthlyProgress = 0
        }
        totalListeningTime += time
        // Count real time spent listening, not content position deltas
        monthlyProgress += time

        updateStreak()
        saveStatistics()
    }
    
    func markBookCompleted() {
        booksCompleted += 1
        updateStreak()
        saveStatistics()
    }

    // MARK: - Reset
    func resetAll() {
        totalListeningTime = 0
        currentStreak = 0
        longestStreak = 0
        // Preserve user's monthly goal, but reset progress
        monthlyProgress = 0
        monthlyAnchor = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        UserDefaults.standard.removeObject(forKey: "lastListenDate")
        saveStatistics()
    }
    
    
    internal func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastListenDate = UserDefaults.standard.object(forKey: "lastListenDate") as? Date ?? Date.distantPast
        let lastListenDay = Calendar.current.startOfDay(for: lastListenDate)
        
        let daysBetween = Calendar.current.dateComponents([.day], from: lastListenDay, to: today).day ?? 0
        
        if daysBetween == 0 {
            // Same day, don't change streak
        } else if daysBetween == 1 {
            // Consecutive day
            currentStreak += 1
            if currentStreak > longestStreak {
                longestStreak = currentStreak
            }
        } else {
            // Streak broken
            currentStreak = 1
        }
        
        UserDefaults.standard.set(Date(), forKey: "lastListenDate")
    }
    
    @MainActor
    private func calculateCurrentMonthProgress() {
        // Maintain progress as accumulated listening time only; reset when the month changes
        let startOfMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
        if startOfMonth != monthlyAnchor {
            monthlyAnchor = startOfMonth
            monthlyProgress = 0
            saveStatistics()
        }
    }
    
    @MainActor
    func updateMonthlyGoal(_ newGoal: TimeInterval) {
        monthlyGoal = newGoal
        saveStatistics()
        
        // Recalculate monthly progress to update UI immediately
        calculateCurrentMonthProgress()

    }
    
    // MARK: - Computed Properties
    var monthlyGoalProgress: Double {
        guard monthlyGoal > 0 else { return 0 }
        return min(monthlyProgress / monthlyGoal, 1.0)
    }
    
    var formattedTotalTime: String {
        return totalListeningTime.hoursMinutesFormatted
    }
    
    var formattedMonthlyProgress: String {
        return monthlyProgress.hoursMinutesFormatted
    }
    
    var formattedMonthlyGoal: String {
        return monthlyGoal.hoursMinutesFormatted
    }
    
}
