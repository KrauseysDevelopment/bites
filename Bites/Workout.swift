// Workout.swift
import Foundation
import SwiftUI

// MARK: - Workout Type

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case walking, running, cycling, hiking, swimming
    case strength, hiit, rowing, elliptical, stairs
    case yoga, pilates, sports, dance, martialArts
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .walking:     return "Walk"
        case .running:     return "Run"
        case .cycling:     return "Cycle"
        case .hiking:      return "Hike"
        case .swimming:    return "Swim"
        case .strength:    return "Strength"
        case .hiit:        return "HIIT"
        case .rowing:      return "Rowing"
        case .elliptical:  return "Elliptical"
        case .stairs:      return "Stairs"
        case .yoga:        return "Yoga"
        case .pilates:     return "Pilates"
        case .sports:      return "Sports"
        case .dance:       return "Dance"
        case .martialArts: return "Martial Arts"
        case .other:       return "Other"
        }
    }

    var icon: String {
        switch self {
        case .walking:     return "figure.walk"
        case .running:     return "figure.run"
        case .cycling:     return "figure.outdoor.cycle"
        case .hiking:      return "figure.hiking"
        case .swimming:    return "figure.pool.swim"
        case .strength:    return "dumbbell.fill"
        case .hiit:        return "figure.highintensity.intervaltraining"
        case .rowing:      return "figure.indoor.rowing"
        case .elliptical:  return "figure.elliptical"
        case .stairs:      return "figure.stair.stepper"
        case .yoga:        return "figure.yoga"
        case .pilates:     return "figure.pilates"
        case .sports:      return "sportscourt.fill"
        case .dance:       return "figure.dance"
        case .martialArts: return "figure.martial.arts"
        case .other:       return "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .walking, .hiking:       return .teal
        case .running, .hiit:         return .orange
        case .cycling, .elliptical:   return .blue
        case .swimming, .rowing:      return .cyan
        case .strength, .martialArts: return .red
        case .yoga, .pilates:         return .purple
        case .stairs, .sports:        return .green
        case .dance:                  return .pink
        case .other:                  return .gray
        }
    }

    /// Metabolic equivalent, used to estimate burn when Health has no number.
    var met: Double {
        switch self {
        case .walking:     return 3.5
        case .running:     return 9.8
        case .cycling:     return 7.5
        case .hiking:      return 6.0
        case .swimming:    return 7.0
        case .strength:    return 5.0
        case .hiit:        return 8.0
        case .rowing:      return 7.0
        case .elliptical:  return 5.0
        case .stairs:      return 8.8
        case .yoga:        return 2.5
        case .pilates:     return 3.0
        case .sports:      return 7.0
        case .dance:       return 5.0
        case .martialArts: return 10.0
        case .other:       return 4.0
        }
    }

    /// Rough kcal estimate. `bodyWeightPounds` of 0 falls back to a 170 lb adult.
    func estimatedCalories(minutes: Int, bodyWeightPounds: Double) -> Int {
        let pounds = bodyWeightPounds > 0 ? bodyWeightPounds : 170
        let kg = pounds / 2.2046226
        let perMinute = met * 3.5 * kg / 200.0
        return max(0, Int((perMinute * Double(minutes)).rounded()))
    }
}

// MARK: - Source

enum WorkoutSource: String, Codable {
    case manual
    case appleHealth

    var label: String {
        switch self {
        case .manual:      return "Logged"
        case .appleHealth: return "Apple Health"
        }
    }

    var icon: String {
        switch self {
        case .manual:      return "square.and.pencil"
        case .appleHealth: return "heart.fill"
        }
    }
}

// MARK: - Workout

struct Workout: Identifiable, Codable, Hashable {
    var id: UUID
    var type: WorkoutType
    /// Optional custom label. Falls back to the type name in the UI.
    var title: String
    var start: Date
    var minutes: Int
    var calories: Int
    var notes: String
    var source: WorkoutSource
    /// Set for workouts imported from Apple Health, so re-importing does not duplicate.
    var healthKitID: UUID?

    var day: Date { Calendar.current.startOfDay(for: start) }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? type.label : title
    }

    init(
        id: UUID = UUID(),
        type: WorkoutType,
        title: String = "",
        start: Date = Date(),
        minutes: Int,
        calories: Int,
        notes: String = "",
        source: WorkoutSource = .manual,
        healthKitID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.start = start
        self.minutes = minutes
        self.calories = calories
        self.notes = notes
        self.source = source
        self.healthKitID = healthKitID
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, title, start, minutes, calories, notes, source, healthKitID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type        = (try? c.decode(WorkoutType.self, forKey: .type)) ?? .other
        title       = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        start       = try c.decodeIfPresent(Date.self, forKey: .start) ?? Date()
        minutes     = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        calories    = try c.decodeIfPresent(Int.self, forKey: .calories) ?? 0
        notes       = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        source      = (try? c.decode(WorkoutSource.self, forKey: .source)) ?? .manual
        healthKitID = try c.decodeIfPresent(UUID.self, forKey: .healthKitID)
    }
}

// MARK: - Daily summary

struct DayActivity: Hashable {
    var date: Date
    var workoutMinutes: Int
    var workoutCalories: Int
    /// Whole-day active energy from Apple Health, independent of the workout log.
    var healthActiveCalories: Int
    var workoutCount: Int

    func metGoal(minutesGoal: Int, calorieGoal: Int) -> Bool {
        guard minutesGoal > 0 || calorieGoal > 0 else { return false }
        let hitMinutes = minutesGoal > 0 && workoutMinutes >= minutesGoal
        let hitCalories = calorieGoal > 0 && max(healthActiveCalories, workoutCalories) >= calorieGoal
        return hitMinutes || hitCalories
    }
}
