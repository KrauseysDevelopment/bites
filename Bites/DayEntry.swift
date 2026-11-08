// DayEntry.swift
import Foundation
import SwiftUI

// MARK: - Meal

struct Meal: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var calories: Int
    var protein: Int
    var carbs: Int
    var fat: Int
    var category: MealCategory
    /// Grams in one serving, when the source database told us. nil means unknown.
    var servingGrams: Double?
    /// When this meal was logged. Used to order the diary within a day.
    var loggedAt: Date

    // Extra nutrients for Bites Points. nil means the source did not say, in
    // which case the points formula estimates from fat and carbs.
    var sugar: Double?
    var saturatedFat: Double?
    var fiber: Double?
    /// Whole fruit, vegetables, lean protein etc. Costs 0 points.
    var isZeroPoint: Bool
    /// Set by hand in Edit Meal, or by a saved meal that knows its own total.
    var pointsOverride: Int?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        protein: Int = 0,
        carbs: Int = 0,
        fat: Int = 0,
        category: MealCategory = .breakfast,
        servingGrams: Double? = nil,
        loggedAt: Date = Date(),
        sugar: Double? = nil,
        saturatedFat: Double? = nil,
        fiber: Double? = nil,
        isZeroPoint: Bool = false,
        pointsOverride: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.category = category
        self.servingGrams = servingGrams
        self.loggedAt = loggedAt
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.fiber = fiber
        self.isZeroPoint = isZeroPoint
        self.pointsOverride = pointsOverride
    }

    /// Bites Points for this meal. See BitesPoints.swift for the formula.
    var points: Int { BitesPoints.points(for: self) }

    // Tolerant decoding so data saved by older builds still loads.
    // NOTE: the previous model declared `let id = UUID()`, which Swift encodes
    // but never decodes, so every relaunch minted fresh IDs and broke deletes.
    private enum CodingKeys: String, CodingKey {
        case id, name, calories, protein, carbs, fat, category, servingGrams, loggedAt
        case sugar, saturatedFat, fiber, isZeroPoint, pointsOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self,   forKey: .id)       ?? UUID()
        name         = try c.decodeIfPresent(String.self, forKey: .name)     ?? "Meal"
        calories     = try c.decodeIfPresent(Int.self,    forKey: .calories) ?? 0
        protein      = try c.decodeIfPresent(Int.self,    forKey: .protein)  ?? 0
        carbs        = try c.decodeIfPresent(Int.self,    forKey: .carbs)    ?? 0
        fat          = try c.decodeIfPresent(Int.self,    forKey: .fat)      ?? 0
        category     = (try? c.decode(MealCategory.self,  forKey: .category)) ?? .breakfast
        servingGrams = try c.decodeIfPresent(Double.self, forKey: .servingGrams)
        loggedAt     = try c.decodeIfPresent(Date.self,   forKey: .loggedAt) ?? Date()
        sugar          = try c.decodeIfPresent(Double.self, forKey: .sugar)
        saturatedFat   = try c.decodeIfPresent(Double.self, forKey: .saturatedFat)
        fiber          = try c.decodeIfPresent(Double.self, forKey: .fiber)
        isZeroPoint    = try c.decodeIfPresent(Bool.self,   forKey: .isZeroPoint) ?? false
        pointsOverride = try c.decodeIfPresent(Int.self,    forKey: .pointsOverride)
    }
}

// MARK: - Meal Category

enum MealCategory: String, Codable, CaseIterable, Identifiable {
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
    case snack     = "Snacks"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .breakfast: return "sun.max"
        case .lunch:     return "fork.knife"
        case .dinner:    return "moon.stars"
        case .snack:     return "carrot"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch:     return .blue
        case .dinner:    return .purple
        case .snack:     return .green
        }
    }

    /// Best guess at the category based on the time of day, used to prefill the picker.
    static func suggested(for date: Date = Date()) -> MealCategory {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        case 17..<22: return .dinner
        default:      return .snack
        }
    }
}

// MARK: - Day Entry

struct DayEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var meals: [Meal]
    var waterGlasses: Int

    var totalCalories: Int { meals.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int  { meals.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int    { meals.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int      { meals.reduce(0) { $0 + $1.fat } }
    var totalPoints: Int   { meals.reduce(0) { $0 + $1.points } }

    var isEmpty: Bool { meals.isEmpty && waterGlasses == 0 }

    init(id: UUID = UUID(), date: Date = Date(), meals: [Meal] = [], waterGlasses: Int = 0) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.meals = meals
        self.waterGlasses = waterGlasses
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, meals, waterGlasses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawDate  = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        date         = Calendar.current.startOfDay(for: rawDate)
        meals        = try c.decodeIfPresent([Meal].self, forKey: .meals) ?? []
        waterGlasses = try c.decodeIfPresent(Int.self, forKey: .waterGlasses) ?? 0
    }
}
