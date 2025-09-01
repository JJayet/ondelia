import Foundation
import SwiftData

@MainActor
class ReadingStatistics: ReadingStatisticsProtocol {
    private let swiftDataController = SwiftDataController.shared
    
    @Published var totalListeningTime: TimeInterval = 0
    @Published var booksCompleted: Int = 0
    @Published var currentStreak: Int = 0
    @Published var longestStreak: Int = 0
    @Published var averageSpeed: Float = 1.0
    @Published var monthlyGoal: TimeInterval = 3600 * 10 // 10 hours default
    @Published var monthlyProgress: TimeInterval = 0
    
    init() {
        loadStatistics()
        calculateCurrentMonthProgress()
    }
    
    private func loadStatistics() {
        totalListeningTime = UserDefaults.standard.double(forKey: "totalListeningTime")
        booksCompleted = UserDefaults.standard.integer(forKey: "booksCompleted")
        currentStreak = UserDefaults.standard.integer(forKey: "currentStreak")
        longestStreak = UserDefaults.standard.integer(forKey: "longestStreak")
        averageSpeed = UserDefaults.standard.float(forKey: "averageSpeed")
        monthlyGoal = UserDefaults.standard.double(forKey: "monthlyGoal")
        
        if monthlyGoal == 0 {
            monthlyGoal = 3600 * 10 // Default 10 hours
        }
        if averageSpeed == 0 {
            averageSpeed = 1.0
        }
    }
    
    private func saveStatistics() {
        UserDefaults.standard.set(totalListeningTime, forKey: "totalListeningTime")
        UserDefaults.standard.set(booksCompleted, forKey: "booksCompleted")
        UserDefaults.standard.set(currentStreak, forKey: "currentStreak")
        UserDefaults.standard.set(longestStreak, forKey: "longestStreak")
        UserDefaults.standard.set(averageSpeed, forKey: "averageSpeed")
        UserDefaults.standard.set(monthlyGoal, forKey: "monthlyGoal")
    }
    
    @MainActor
    func addListeningTime(_ time: TimeInterval, playbackRate: Float = 1.0) {
        totalListeningTime += time
        
        // Update average speed (weighted average)
        let totalSessions = UserDefaults.standard.integer(forKey: "totalSessions")
        let newTotalSessions = totalSessions + 1
        averageSpeed = (averageSpeed * Float(totalSessions) + playbackRate) / Float(newTotalSessions)
        
        UserDefaults.standard.set(newTotalSessions, forKey: "totalSessions")
        updateStreak()
        saveStatistics()
        calculateCurrentMonthProgress()
    }
    
    func markBookCompleted() {
        booksCompleted += 1
        updateStreak()
        saveStatistics()
    }
    
    func getAverageSpeed() -> Float {
        return averageSpeed
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
        // If SwiftData isn't ready yet (e.g., early view creation or previews), skip gracefully
        guard SwiftDataController.shared.isLoaded else {
            monthlyProgress = 0
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now

        // Calculate listening time for current month
        let context = swiftDataController.context
        let descriptor = FetchDescriptor<AudiobookModel>(
            predicate: #Predicate<AudiobookModel> { $0.lastPlayed >= startOfMonth }
        )

        do {
            let audiobooks = try context.fetch(descriptor)
            monthlyProgress = audiobooks.reduce(0) { total, book in
                total + book.currentPosition
            }
        } catch {
            print("Failed to calculate monthly progress: \(error)")
        }
    }
    
    @MainActor
    func updateMonthlyGoal(_ newGoal: TimeInterval) {
        monthlyGoal = newGoal
        saveStatistics()
        
        // Recalculate monthly progress to update UI immediately
        calculateCurrentMonthProgress()
        
        // Force UI update by sending change (already on @MainActor)
        self.objectWillChange.send()
    }
    
    // MARK: - Computed Properties
    var monthlyGoalProgress: Double {
        guard monthlyGoal > 0 else { return 0 }
        return min(monthlyProgress / monthlyGoal, 1.0)
    }
    
    var formattedTotalTime: String {
        return formatTime(totalListeningTime)
    }
    
    var formattedMonthlyProgress: String {
        return formatTime(monthlyProgress)
    }
    
    var formattedMonthlyGoal: String {
        return formatTime(monthlyGoal)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        else {
            return "\(minutes)m"
        }
    }
}
