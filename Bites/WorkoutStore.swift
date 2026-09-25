// WorkoutStore.swift
import Foundation
import SwiftUI

final class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()

    /// All workouts, manual and imported, newest first.
    @Published var workouts: [Workout] = [] { didSet { save() } }

    /// Whole-day active energy from Apple Health, keyed by start of day.
    /// Populated by HealthManager; not persisted, since Health is the source.
    @Published var healthActiveCalories: [Date: Int] = [:]

    /// Whole-day Apple "Exercise" minutes, shown as context next to the log.
    @Published var healthExerciseMinutes: [Date: Int] = [:]

    // MARK: Goals

    @Published var exerciseMinutesGoal: Int { didSet { defaults.set(exerciseMinutesGoal, forKey: Keys.minutesGoal) } }
    @Published var activeCalorieGoal: Int   { didSet { defaults.set(activeCalorieGoal, forKey: Keys.calorieGoal) } }
    /// When off, Health workouts are not pulled in and the log is manual only.
    @Published var importFromHealth: Bool   { didSet { defaults.set(importFromHealth, forKey: Keys.importHealth) } }

    private let defaults = UserDefaults.standard
    private var isLoading = true

    private enum Keys {
        static let workouts     = "BitesWorkoutsV1"
        static let minutesGoal  = "ExerciseMinutesGoal"
        static let calorieGoal  = "ActiveCalorieGoal"
        static let importHealth = "ImportWorkoutsFromHealth"
    }

    private init() {
        exerciseMinutesGoal = defaults.int(forKey: Keys.minutesGoal, default: 30)
        activeCalorieGoal   = defaults.int(forKey: Keys.calorieGoal, default: 500)
        importFromHealth    = defaults.object(forKey: Keys.importHealth) as? Bool ?? true

        if let data = defaults.data(forKey: Keys.workouts),
           let decoded = try? JSONDecoder().decode([Workout].self, from: data) {
            workouts = decoded.sorted { $0.start > $1.start }
        }
        isLoading = false
    }

    // MARK: - Mutations

    func add(_ workout: Workout) {
        workouts.append(workout)
        workouts.sort { $0.start > $1.start }
    }

    func update(_ workout: Workout) {
        guard let index = workouts.firstIndex(where: { $0.id == workout.id }) else { return }
        workouts[index] = workout
        workouts.sort { $0.start > $1.start }
    }

    func delete(id: UUID) {
        workouts.removeAll { $0.id == id }
    }

    /// Merge workouts read from Apple Health. Existing records matched by
    /// healthKitID are refreshed in place rather than duplicated, and anything
    /// previously imported that has since been deleted in Health is dropped.
    func mergeHealthWorkouts(_ imported: [Workout]) {
        let importedIDs = Set(imported.compactMap(\.healthKitID))
        var merged = workouts.filter { existing in
            guard existing.source == .appleHealth, let hkID = existing.healthKitID else { return true }
            return importedIDs.contains(hkID)
        }

        for workout in imported {
            guard let hkID = workout.healthKitID else { continue }
            if let index = merged.firstIndex(where: { $0.healthKitID == hkID }) {
                // Keep any note the user typed on the imported record.
                var updated = workout
                updated.id = merged[index].id
                updated.notes = merged[index].notes
                updated.title = merged[index].title
            merged[index] = updated
            } else if !looksLikeDuplicateOfManual(workout, in: merged) {
                merged.append(workout)
            }
        }

        merged.sort { $0.start > $1.start }
        if merged != workouts { workouts = merged }
    }

    /// Guards against logging a session by hand that the watch also recorded.
    /// Same type, starting within 20 minutes of each other, counts as one.
    private func looksLikeDuplicateOfManual(_ candidate: Workout, in list: [Workout]) -> Bool {
        list.contains { existing in
            existing.source == .manual
                && existing.type == candidate.type
                && abs(existing.start.timeIntervalSince(candidate.start)) < 20 * 60
        }
    }

    // MARK: - Queries

    func workouts(on date: Date) -> [Workout] {
        let day = Calendar.current.startOfDay(for: date)
        return workouts.filter { $0.day == day }.sorted { $0.start > $1.start }
    }

    func activity(on date: Date) -> DayActivity {
        let day = Calendar.current.startOfDay(for: date)
        let dayWorkouts = workouts.filter { $0.day == day }
        return DayActivity(
            date: day,
            workoutMinutes: dayWorkouts.reduce(0) { $0 + $1.minutes },
            workoutCalories: dayWorkouts.reduce(0) { $0 + $1.calories },
            healthActiveCalories: healthActiveCalories[day] ?? 0,
            workoutCount: dayWorkouts.count
        )
    }

    func metGoal(on date: Date) -> Bool {
        activity(on: date).metGoal(minutesGoal: exerciseMinutesGoal, calorieGoal: activeCalorieGoal)
    }

    /// Consecutive days meeting the goal, counting back from today.
    /// Today not being finished yet does not break the streak: if today has not
    /// hit the goal, counting starts at yesterday.
    var currentStreak: Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: Date())

        if !metGoal(on: cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while metGoal(on: cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// True when today itself is already in the bag.
    var todayMetGoal: Bool { metGoal(on: Date()) }

    var longestStreak: Int {
        let calendar = Calendar.current
        let days = Set(workouts.map(\.day)).union(healthActiveCalories.keys)
        guard let earliest = days.min() else { return 0 }

        var best = 0
        var running = 0
        var cursor = earliest
        let today = calendar.startOfDay(for: Date())

        while cursor <= today {
            if metGoal(on: cursor) {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return best
    }

    /// The last `count` days, oldest first, for the streak strip and charts.
    func recentActivity(days count: Int) -> [DayActivity] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return activity(on: date)
        }
    }

    var thisWeekMinutes: Int {
        recentActivity(days: 7).reduce(0) { $0 + $1.workoutMinutes }
    }

    var thisWeekWorkouts: Int {
        recentActivity(days: 7).reduce(0) { $0 + $1.workoutCount }
    }

    // MARK: - Persistence

    private func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(workouts) {
            defaults.set(data, forKey: Keys.workouts)
        }
    }
}
