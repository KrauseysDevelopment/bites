// Achievements.swift
import Foundation
import SwiftUI

// MARK: - Streak math

/// Day-streak helpers shared by the Today chip, the achievements screen and
/// the reminders. Same rule as the workout streak: today not being done yet
/// does not break a streak, counting starts at yesterday in that case.
enum Streaks {
    static func current(qualifyingDays: Set<Date>, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: now)
        if !qualifyingDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while qualifyingDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func longest(qualifyingDays: Set<Date>) -> Int {
        let calendar = Calendar.current
        var best = 0
        for day in qualifyingDays {
            // Only start counting at the first day of a run.
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day),
                  !qualifyingDays.contains(previous) else { continue }
            var length = 0
            var cursor = day
            while qualifyingDays.contains(cursor) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, length)
        }
        return best
    }

    /// Days with at least one meal in the diary.
    static func loggedDays(_ days: [DayEntry]) -> Set<Date> {
        Set(days.filter { !$0.meals.isEmpty }.map(\.date))
    }

    /// Logged days that stayed within budget: points budget in Points mode,
    /// calorie goal in Macros mode.
    static func onBudgetDays(_ days: [DayEntry], plan: PlanStore, calorieGoal: Int) -> Set<Date> {
        Set(days.filter { day in
            guard !day.meals.isEmpty else { return false }
            switch plan.trackingMode {
            case .points: return day.totalPoints <= plan.dailyPointsBudget
            case .macros: return day.totalCalories <= calorieGoal
            }
        }.map(\.date))
    }

    static func weighInDays(_ entries: [WeightEntry]) -> Set<Date> {
        Set(entries.map(\.date))
    }

    static func waterGoalDays(_ days: [DayEntry], goal: Int) -> Set<Date> {
        Set(days.filter { goal > 0 && $0.waterGlasses >= goal }.map(\.date))
    }
}

// MARK: - Achievement definitions

enum AchievementKind: String, Codable {
    case loggingStreak, workoutStreak, weighInStreak, onBudgetStreak, waterStreak
    case mealsLogged, workoutsLogged, poundsLost, foodsScanned

    var category: String {
        switch self {
        case .loggingStreak, .onBudgetStreak, .mealsLogged, .foodsScanned: return "Food"
        case .workoutStreak, .workoutsLogged: return "Fitness"
        case .weighInStreak, .poundsLost: return "Weight"
        case .waterStreak: return "Water"
        }
    }

    var unit: String {
        switch self {
        case .loggingStreak, .workoutStreak, .weighInStreak, .onBudgetStreak, .waterStreak: return "days"
        case .mealsLogged: return "meals"
        case .workoutsLogged: return "workouts"
        case .poundsLost: return "lb"
        case .foodsScanned: return "scans"
        }
    }
}

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let kind: AchievementKind
    let threshold: Int

    static let all: [Achievement] = {
        var list: [Achievement] = []

        func streak(_ kind: AchievementKind, _ prefix: String, _ icon: String, _ color: Color,
                    _ verb: String, _ steps: [(Int, String)]) {
            for (days, title) in steps {
                list.append(Achievement(
                    id: "\(prefix).\(days)", title: title,
                    detail: "\(verb) \(days) days in a row", icon: icon, color: color,
                    kind: kind, threshold: days))
            }
        }

        list.append(Achievement(id: "meals.1", title: "First Bite", detail: "Log your first meal",
                                icon: "fork.knife", color: .orange, kind: .mealsLogged, threshold: 1))

        streak(.loggingStreak, "log", "flame.fill", .orange, "Log food",
               [(3, "Warming Up"), (7, "Full Week"), (14, "Two Weeks Strong"), (30, "Monthly Habit"),
                (60, "Locked In"), (100, "Century"), (200, "Unstoppable"), (365, "Year of Bites")])

        streak(.onBudgetStreak, "budget", "target", .green, "Stay within budget",
               [(3, "On Target"), (7, "Week on Budget"), (14, "Steady Hand"), (30, "Budget Master")])

        streak(.workoutStreak, "move", "figure.run", .green, "Hit your exercise goal",
               [(3, "Moving"), (7, "Week in Motion"), (14, "Momentum"), (30, "Iron Month"), (100, "Relentless")])

        streak(.weighInStreak, "weigh", "scalemass.fill", .indigo, "Weigh in",
               [(7, "Scale Regular"), (30, "Data Driven")])

        streak(.waterStreak, "water", "drop.fill", .blue, "Hit your water goal",
               [(3, "Hydrated"), (7, "Water Week"), (30, "Well Watered")])

        for (count, title) in [(50, "Fifty Logged"), (250, "Food Journalist"), (1000, "Thousand Bites")] {
            list.append(Achievement(id: "meals.\(count)", title: title, detail: "Log \(count) meals",
                                    icon: "book.closed.fill", color: .orange, kind: .mealsLogged, threshold: count))
        }
        for (count, title) in [(1, "First Workout"), (25, "Regular"), (100, "Gym Rat"), (250, "Athlete")] {
            list.append(Achievement(id: "workouts.\(count)", title: title,
                                    detail: count == 1 ? "Log your first workout" : "Log \(count) workouts",
                                    icon: "dumbbell.fill", color: .green, kind: .workoutsLogged, threshold: count))
        }
        for (pounds, title) in [(5, "First Five"), (10, "Double Digits"), (25, "Quarter Century"), (50, "Fifty Down")] {
            list.append(Achievement(id: "lost.\(pounds)", title: title, detail: "Lose \(pounds) lb from your starting weight",
                                    icon: "arrow.down.right.circle.fill", color: .indigo, kind: .poundsLost, threshold: pounds))
        }
        for (count, title) in [(1, "Scanner"), (25, "Barcode Pro")] {
            list.append(Achievement(id: "scans.\(count)", title: title,
                                    detail: count == 1 ? "Scan your first barcode" : "Scan \(count) different products",
                                    icon: "barcode.viewfinder", color: .purple, kind: .foodsScanned, threshold: count))
        }
        return list
    }()
}

// MARK: - Store

/// Works out streaks and badges from the diary, workouts and weight log.
/// Badges are earned on best-ever values, so they are never taken away.
final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()

    struct StreakInfo: Hashable {
        let current: Int
        let best: Int
    }

    @Published private(set) var unlocked: [String: Date] = [:]
    @Published private(set) var metrics: [AchievementKind: Int] = [:]
    @Published private(set) var logging = StreakInfo(current: 0, best: 0)
    @Published private(set) var onBudget = StreakInfo(current: 0, best: 0)
    @Published private(set) var weighIn = StreakInfo(current: 0, best: 0)
    @Published private(set) var water = StreakInfo(current: 0, best: 0)
    @Published private(set) var workout = StreakInfo(current: 0, best: 0)
    /// Drives the in-app "Achievement unlocked" banner.
    @Published var banner: Achievement?

    private let defaults = UserDefaults.standard
    private let unlockedKey = "AchievementsUnlockedV1"
    /// First evaluation unlocks history silently, so an existing user is not
    /// hit with a dozen notifications at once.
    private let baselineKey = "AchievementsBaselineDone"

    private init() {
        if let data = defaults.data(forKey: unlockedKey),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            unlocked = decoded
        }
    }

    func isUnlocked(_ achievement: Achievement) -> Bool { unlocked[achievement.id] != nil }

    func progress(_ achievement: Achievement) -> Int {
        min(metrics[achievement.kind] ?? 0, achievement.threshold)
    }

    var unlockedCount: Int { Achievement.all.filter(isUnlocked).count }

    /// Call whenever logged data changes and when the app comes to the front.
    @MainActor
    func evaluate(diary: DiaryStore, workouts: WorkoutStore, plan: PlanStore = .shared,
                  recents: RecentFoodsStore = .shared) {
        let logged = Streaks.loggedDays(diary.days)
        let budget = Streaks.onBudgetDays(diary.days, plan: plan, calorieGoal: diary.calorieGoal)
        let weighs = Streaks.weighInDays(diary.weightEntries)
        let waterDays = Streaks.waterGoalDays(diary.days, goal: diary.waterGoal)

        logging  = StreakInfo(current: Streaks.current(qualifyingDays: logged), best: Streaks.longest(qualifyingDays: logged))
        onBudget = StreakInfo(current: Streaks.current(qualifyingDays: budget), best: Streaks.longest(qualifyingDays: budget))
        weighIn  = StreakInfo(current: Streaks.current(qualifyingDays: weighs), best: Streaks.longest(qualifyingDays: weighs))
        water    = StreakInfo(current: Streaks.current(qualifyingDays: waterDays), best: Streaks.longest(qualifyingDays: waterDays))
        workout  = StreakInfo(current: workouts.currentStreak, best: workouts.longestStreak)

        let sortedWeights = diary.weightEntries.sorted { $0.date < $1.date }
        var lost = 0
        if let start = sortedWeights.first?.pounds, let lowest = sortedWeights.map(\.pounds).min() {
            lost = max(0, Int((start - lowest).rounded(.down)))
        }

        metrics = [
            .loggingStreak: logging.best,
            .onBudgetStreak: onBudget.best,
            .weighInStreak: weighIn.best,
            .waterStreak: water.best,
            .workoutStreak: workout.best,
            .mealsLogged: diary.days.reduce(0) { $0 + $1.meals.count },
            .workoutsLogged: workouts.workouts.count,
            .poundsLost: lost,
            .foodsScanned: recents.scanned.count
        ]

        let isBaseline = !defaults.bool(forKey: baselineKey)
        var newlyUnlocked: [Achievement] = []
        for achievement in Achievement.all where !isUnlocked(achievement) {
            if (metrics[achievement.kind] ?? 0) >= achievement.threshold {
                unlocked[achievement.id] = Date()
                newlyUnlocked.append(achievement)
            }
        }

        if !newlyUnlocked.isEmpty {
            if let data = try? JSONEncoder().encode(unlocked) {
                defaults.set(data, forKey: unlockedKey)
            }
            if !isBaseline {
                // Biggest milestone first if several land at once.
                let headline = newlyUnlocked.max { $0.threshold < $1.threshold }
                banner = headline
                for achievement in newlyUnlocked {
                    ReminderCenter.shared.notifyAchievement(achievement)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                    withAnimation { self?.banner = nil }
                }
            }
        }
        if isBaseline { defaults.set(true, forKey: baselineKey) }
    }
}
