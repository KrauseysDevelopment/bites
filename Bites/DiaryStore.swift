// DiaryStore.swift
import Foundation
import SwiftUI

// MARK: - Distance Unit

enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers = "km"
    case miles = "mi"

    var id: String { rawValue }

    var toMeters: Double {
        switch self {
        case .kilometers: return 1000.0
        case .miles:      return 1609.344
        }
    }
}

// MARK: - Weight Entry

struct WeightEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var pounds: Double

    init(id: UUID = UUID(), pounds: Double, date: Date = Date()) {
        self.id = id
        self.pounds = pounds
        self.date = Calendar.current.startOfDay(for: date)
    }

    private enum CodingKeys: String, CodingKey { case id, date, pounds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id      = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let raw = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        date    = Calendar.current.startOfDay(for: raw)
        pounds  = try c.decodeIfPresent(Double.self, forKey: .pounds) ?? 0
    }
}

// MARK: - Diary Store

final class DiaryStore: ObservableObject {
    static let shared = DiaryStore()

    @Published var days: [DayEntry] = [] { didSet { save() } }
    @Published var savedMeals: [SavedMeal] = [] { didSet { saveSavedMeals() } }
    @Published var weightEntries: [WeightEntry] = [] { didSet { saveWeightEntries() } }
    @Published var showMealAddedToast = false

    // MARK: Goals
    //
    // These were @AppStorage. @AppStorage is a DynamicProperty built for Views:
    // inside an ObservableObject it reads and writes UserDefaults but never fires
    // objectWillChange, so editing a goal in Settings left the Today tab stale.
    // Backing them with @Published + a UserDefaults write in didSet fixes that.

    @Published var calorieGoal: Int      { didSet { defaults.set(calorieGoal, forKey: Keys.calorieGoal) } }
    @Published var proteinGoal: Int      { didSet { defaults.set(proteinGoal, forKey: Keys.proteinGoal) } }
    @Published var carbsGoal: Int        { didSet { defaults.set(carbsGoal, forKey: Keys.carbsGoal) } }
    @Published var fatGoal: Int          { didSet { defaults.set(fatGoal, forKey: Keys.fatGoal) } }
    @Published var waterGoal: Int        { didSet { defaults.set(waterGoal, forKey: Keys.waterGoal) } }
    @Published var distanceUnit: DistanceUnit { didSet { defaults.set(distanceUnit.rawValue, forKey: Keys.distanceUnit) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let days          = "BitesSavedDataV4"
        static let savedMeals    = "BitesSavedMeals"
        static let weightEntries = "BitesWeightEntries"
        static let calorieGoal   = "CalorieGoal"
        static let proteinGoal   = "ProteinGoal"
        static let carbsGoal     = "CarbsGoal"
        static let fatGoal       = "FatGoal"
        static let waterGoal     = "WaterGoal"
        static let distanceUnit  = "distanceUnit"
    }

    private var isLoading = true

    private init() {
        calorieGoal  = defaults.int(forKey: Keys.calorieGoal,  default: 2500)
        proteinGoal  = defaults.int(forKey: Keys.proteinGoal,  default: 150)
        carbsGoal    = defaults.int(forKey: Keys.carbsGoal,    default: 250)
        fatGoal      = defaults.int(forKey: Keys.fatGoal,      default: 80)
        waterGoal    = defaults.int(forKey: Keys.waterGoal,    default: 8)
        distanceUnit = DistanceUnit(rawValue: defaults.string(forKey: Keys.distanceUnit) ?? "") ?? .miles

        load()
        loadSavedMeals()
        loadWeightEntries()
        isLoading = false
        ensureTodayExists()
    }

    // MARK: - Today
    //
    // `today` used to be a stored copy of a DayEntry, which drifted out of sync
    // with `days` whenever one was mutated without the other. It is now derived.

    var today: DayEntry {
        days.first(where: { $0.date.isSameDay(as: Date()) }) ?? DayEntry()
    }

    private func ensureTodayExists() {
        guard !days.contains(where: { $0.date.isSameDay(as: Date()) }) else { return }
        days.insert(DayEntry(), at: 0)
    }

    /// Kept so existing call sites keep compiling. Makes sure today's row exists
    /// and that the array is sorted newest first.
    func refreshToday() {
        ensureTodayExists()
        days.sort { $0.date > $1.date }
    }

    // MARK: - Mutations

    func addMeal(_ meal: Meal) {
        if let index = days.firstIndex(where: { $0.date.isSameDay(as: Date()) }) {
            days[index].meals.append(meal)
        } else {
            days.insert(DayEntry(meals: [meal]), at: 0)
        }

        showMealAddedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation { self?.showMealAddedToast = false }
        }
    }

    /// Which day a logged meal currently sits on.
    func date(ofMeal id: UUID) -> Date? {
        days.first(where: { $0.meals.contains(where: { $0.id == id }) })?.date
    }

    /// Replaces a logged meal in place, and moves it to another day when the
    /// date changed, so a meal logged against the wrong day can be corrected.
    func updateMeal(_ updated: Meal, movingTo newDate: Date? = nil) {
        guard let dayIndex = days.firstIndex(where: { $0.meals.contains(where: { $0.id == updated.id }) })
        else { return }

        let currentDay = days[dayIndex].date
        let targetDay = Calendar.current.startOfDay(for: newDate ?? currentDay)

        if targetDay == currentDay {
            if let mealIndex = days[dayIndex].meals.firstIndex(where: { $0.id == updated.id }) {
                days[dayIndex].meals[mealIndex] = updated
            }
            return
        }

        days[dayIndex].meals.removeAll { $0.id == updated.id }
        if let targetIndex = days.firstIndex(where: { $0.date == targetDay }) {
            days[targetIndex].meals.append(updated)
        } else {
            days.append(DayEntry(date: targetDay, meals: [updated]))
            days.sort { $0.date > $1.date }
        }
    }

    func deleteMeal(id: UUID) {
        guard let dayIndex = days.firstIndex(where: { $0.meals.contains(where: { $0.id == id }) }) else { return }
        days[dayIndex].meals.removeAll { $0.id == id }
    }

    func setWaterGlasses(to count: Int) {
        let clamped = min(waterGoal, max(0, count))
        if let index = days.firstIndex(where: { $0.date.isSameDay(as: Date()) }) {
            days[index].waterGlasses = clamped
        } else {
            days.insert(DayEntry(waterGlasses: clamped), at: 0)
        }
    }

    func calories(on date: Date) -> Int {
        let start = Calendar.current.startOfDay(for: date)
        return days.first(where: { $0.date == start })?.totalCalories ?? 0
    }

    // MARK: - Weight

    func logWeight(_ pounds: Double, on date: Date = Date()) {
        let day = Calendar.current.startOfDay(for: date)
        if let index = weightEntries.firstIndex(where: { $0.date == day }) {
            weightEntries[index].pounds = pounds
        } else {
            weightEntries.append(WeightEntry(pounds: pounds, date: day))
        }
        weightEntries.sort { $0.date > $1.date }
    }

    func deleteWeight(on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        weightEntries.removeAll { $0.date == day }
    }

    /// Most recent weigh-in date, used to work out whether one is due.
    var lastWeighInDate: Date? {
        weightEntries.map(\.date).max()
    }

    var todaysWeight: Double {
        let day = Calendar.current.startOfDay(for: Date())
        return weightEntries.first(where: { $0.date == day })?.pounds ?? 0
    }

    /// Most recent recorded weight, whatever day it came from. Used for
    /// calorie-burn estimates so a stale log is better than a hard-coded guess.
    var latestWeight: Double {
        weightEntries.max(by: { $0.date < $1.date })?.pounds ?? 0
    }

    var weeklyAverageWeight: Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        let recent = weightEntries.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.pounds).reduce(0, +) / Double(recent.count)
    }

    /// Change against the oldest weight in the last 30 days. Negative means down.
    var monthlyWeightChange: Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: Date()))!
        let window = weightEntries.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard let first = window.first, let last = window.last, first.id != last.id else { return nil }
        return last.pounds - first.pounds
    }

    // MARK: - Persistence

    func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(days) {
            defaults.set(data, forKey: Keys.days)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Keys.days),
              let decoded = try? JSONDecoder().decode([DayEntry].self, from: data)
        else { return }
        days = Self.mergingDuplicateDays(decoded)
    }

    /// Older builds could insert more than one row for the same calendar day,
    /// which showed up as repeated sections in the diary. Fold them on load.
    private static func mergingDuplicateDays(_ entries: [DayEntry]) -> [DayEntry] {
        var byDay: [Date: DayEntry] = [:]
        for entry in entries {
            if var existing = byDay[entry.date] {
                existing.meals.append(contentsOf: entry.meals)
                existing.waterGlasses = max(existing.waterGlasses, entry.waterGlasses)
                byDay[entry.date] = existing
            } else {
                byDay[entry.date] = entry
            }
        }
        return byDay.values.sorted { $0.date > $1.date }
    }

    private func saveSavedMeals() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(savedMeals) {
            defaults.set(data, forKey: Keys.savedMeals)
        }
    }

    private func loadSavedMeals() {
        if let data = defaults.data(forKey: Keys.savedMeals),
           let decoded = try? JSONDecoder().decode([SavedMeal].self, from: data) {
            savedMeals = decoded
        }
    }

    private func saveWeightEntries() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(weightEntries) {
            defaults.set(data, forKey: Keys.weightEntries)
        }
    }

    private func loadWeightEntries() {
        if let data = defaults.data(forKey: Keys.weightEntries),
           let decoded = try? JSONDecoder().decode([WeightEntry].self, from: data) {
            weightEntries = decoded.sorted { $0.date > $1.date }
        }
    }
}

// MARK: - UserDefaults helper

extension UserDefaults {
    /// `integer(forKey:)` returns 0 for a missing key, which would silently turn
    /// every goal into zero on first launch. This preserves the intended default.
    func int(forKey key: String, default fallback: Int) -> Int {
        object(forKey: key) as? Int ?? fallback
    }
}

// MARK: - Saved Meals

struct SavedMeal: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var items: [SavedMealItem]

    var totalCalories: Int { items.reduce(0) { $0 + $1.meal.calories } }
    var totalProtein: Int  { items.reduce(0) { $0 + $1.meal.protein } }
    var totalCarbs: Int    { items.reduce(0) { $0 + $1.meal.carbs } }
    var totalFat: Int      { items.reduce(0) { $0 + $1.meal.fat } }
    var totalPoints: Int   { items.reduce(0) { $0 + $1.meal.points } }

    init(id: UUID = UUID(), name: String, items: [SavedMealItem]) {
        self.id = id
        self.name = name
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case id, name, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id    = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name  = try c.decodeIfPresent(String.self, forKey: .name) ?? "Saved Meal"
        items = try c.decodeIfPresent([SavedMealItem].self, forKey: .items) ?? []
    }
}

struct SavedMealItem: Codable, Hashable, Identifiable {
    var id: UUID
    var meal: Meal
    var multiplier: Double

    init(id: UUID = UUID(), meal: Meal, multiplier: Double = 1.0) {
        self.id = id
        self.meal = meal
        self.multiplier = multiplier
    }

    private enum CodingKeys: String, CodingKey { case id, meal, multiplier }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        meal       = try c.decode(Meal.self, forKey: .meal)
        multiplier = try c.decodeIfPresent(Double.self, forKey: .multiplier) ?? 1.0
    }
}

extension Meal {
    func scaled(by multiplier: Double) -> Meal {
        Meal(
            name: name,
            calories: Int((Double(calories) * multiplier).rounded()),
            protein: Int((Double(protein) * multiplier).rounded()),
            carbs: Int((Double(carbs) * multiplier).rounded()),
            fat: Int((Double(fat) * multiplier).rounded()),
            category: category,
            servingGrams: servingGrams,
            sugar: sugar.map { $0 * multiplier },
            saturatedFat: saturatedFat.map { $0 * multiplier },
            fiber: fiber.map { $0 * multiplier },
            isZeroPoint: isZeroPoint,
            pointsOverride: pointsOverride.map { Int((Double($0) * multiplier).rounded()) }
        )
    }
}
