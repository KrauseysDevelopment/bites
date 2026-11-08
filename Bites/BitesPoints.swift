// BitesPoints.swift
import Foundation
import SwiftUI

// MARK: - Tracking mode

/// Bites Points is a WW-style budget; Bites Macros is the original calorie ring
/// plus protein/carbs/fat. Switchable at any time in Settings; the diary keeps
/// both numbers for every meal, so nothing is lost by switching.
enum TrackingMode: String, CaseIterable, Identifiable, Codable {
    case points
    case macros

    var id: String { rawValue }

    var title: String {
        switch self {
        case .points: return "Bites Points"
        case .macros: return "Bites Macros"
        }
    }

    var subtitle: String {
        switch self {
        case .points: return "A daily points budget, weekly extras, and zero-point foods"
        case .macros: return "Calories with protein, carb and fat targets"
        }
    }

    var icon: String {
        switch self {
        case .points: return "circle.hexagongrid.fill"
        case .macros: return "chart.pie.fill"
        }
    }
}

// MARK: - Points formula

/// Modelled on WW's SmartPoints formula as it has been publicly worked out:
///
///     points = kcal × 0.0305 + saturated fat × 0.275 + sugar × 0.12 − protein × 0.098
///
/// Calories set the baseline, saturated fat and sugar push it up, protein pulls
/// it down. WW's current formula also weighs fiber and unsaturated fat, but it
/// has never been published, so this is the closest open equivalent.
///
/// Meals logged by hand, or before this feature existed, have no sugar or
/// saturated fat on record. Those fall back to conservative estimates from
/// total fat and carbs rather than to zero, which would under-count.
enum BitesPoints {
    static let caloriesFactor = 0.0305
    static let saturatedFatFactor = 0.275
    static let sugarFactor = 0.12
    static let proteinFactor = 0.098

    /// Share of total fat assumed saturated when unknown (typical mixed diet).
    static let estimatedSaturatedShare = 0.35
    /// Share of carbs assumed sugar when unknown.
    static let estimatedSugarShare = 0.25

    static func points(for meal: Meal) -> Int {
        if let override = meal.pointsOverride { return max(0, override) }
        if meal.isZeroPoint && PlanStore.shared.zeroPointFoodsEnabled { return 0 }
        return points(
            calories: Double(meal.calories),
            protein: Double(meal.protein),
            saturatedFat: meal.saturatedFat ?? Double(meal.fat) * estimatedSaturatedShare,
            sugar: meal.sugar ?? Double(meal.carbs) * estimatedSugarShare
        )
    }

    static func points(calories: Double, protein: Double, saturatedFat: Double, sugar: Double) -> Int {
        let raw = calories * caloriesFactor
            + saturatedFat * saturatedFatFactor
            + sugar * sugarFactor
            - protein * proteinFactor
        return max(0, Int(raw.rounded()))
    }

    /// Points for a portion of a food, before it is logged.
    static func points(for food: FoodItem, grams: Double) -> Int {
        if PlanStore.shared.zeroPointFoodsEnabled && ZeroPointFoods.qualifies(food) { return 0 }
        let n = food.per100g.scaled(toGrams: grams)
        return points(
            calories: n.calories,
            protein: n.protein,
            saturatedFat: n.saturatedFat ?? n.fat * estimatedSaturatedShare,
            sugar: n.sugar ?? n.carbs * estimatedSugarShare
        )
    }

    /// True when the meal's points rest on estimated sugar or saturated fat.
    static func isEstimated(_ meal: Meal) -> Bool {
        guard meal.pointsOverride == nil, !meal.isZeroPoint else { return false }
        return meal.saturatedFat == nil || meal.sugar == nil
    }
}

// MARK: - Zero-point foods

/// WW's ZeroPoint list, applied to plain whole foods only: fruit, non-starchy
/// vegetables, corn and peas, eggs, skinless chicken and turkey breast, fish
/// and shellfish, tofu and tempeh, beans and lentils, and plain nonfat yogurt
/// and cottage cheese.
///
/// Only USDA whole-food entries qualify. Branded and scanned products never
/// do, because "apple" on a package is usually apple pie filling or juice.
/// Anything fried, sweetened, dried, sauced or with skin is excluded.
enum ZeroPointFoods {
    /// Each rule lists words that must all appear in the food's name.
    private static let rules: [[String]] = {
        let fruit = ["apple", "apricot", "banana", "blackberries", "blueberries", "cantaloupe",
                     "cherries", "clementine", "cranberries", "figs", "grapefruit", "grapes",
                     "guava", "honeydew", "kiwi", "kiwifruit", "lemon", "lime", "mango", "melon",
                     "nectarine", "orange", "oranges", "papaya", "peach", "peaches", "pear", "pears",
                     "pineapple", "plum", "plums", "pomegranate", "raspberries", "strawberries",
                     "tangerine", "tangerines", "watermelon"]
        let vegetables = ["artichoke", "artichokes", "arugula", "asparagus", "beets", "bok", "broccoli",
                          "brussels", "cabbage", "carrot", "carrots", "cauliflower", "celery", "chard",
                          "collards", "corn", "cucumber", "eggplant", "endive", "kale", "leeks", "lettuce",
                          "mushroom", "mushrooms", "okra", "onion", "onions", "peas", "peppers", "pepper",
                          "radish", "radishes", "spinach", "sprouts", "squash", "tomato", "tomatoes",
                          "turnip", "turnips", "zucchini", "beans, snap", "green beans"]
        let seafood = ["fish", "salmon", "tuna", "cod", "tilapia", "halibut", "trout", "haddock", "pollock",
                       "mahimahi", "catfish", "flounder", "sole", "snapper", "bass", "sardines", "mackerel",
                       "shrimp", "scallops", "crab", "lobster", "clams", "mussels", "oysters", "crustaceans",
                       "mollusks"]
        // USDA writes "Beans, black, mature seeds", so beans need two words.
        let beanKinds = ["black", "kidney", "pinto", "navy", "cannellini", "great northern", "white",
                         "adzuki", "cranberry", "pink", "small white", "french", "yellow", "mung"]
        let legumes = ["chickpeas", "garbanzo", "lentils", "edamame", "lima", "black-eyed", "cowpeas"]
        var all: [[String]] = []
        all += fruit.map { [$0] }
        all += vegetables.map { [$0] }
        all += seafood.map { [$0] }
        all += legumes.map { [$0] }
        all += beanKinds.map { ["beans", $0] }
        all += [
            ["egg"], ["eggs"], ["egg white"],
            ["chicken", "breast"],
            ["turkey", "breast"],
            ["tofu"], ["tempeh"],
            ["yogurt", "plain", "nonfat"], ["yogurt", "plain", "fat free"],
            ["yogurt", "greek", "plain", "nonfat"],
            ["cottage", "cheese", "nonfat"], ["cottage", "cheese", "fat free"]
        ]
        return all
    }()

    /// Any of these in the name disqualifies the food.
    private static let exclusions = [
        "fried", "breaded", "battered", "juice", "dried", "dehydrated", "syrup", "sweetened",
        "candied", "sugar", "jam", "jelly", "preserves", "pie", "cake", "muffin", "bread", "chips",
        "crisps", "sauce", "gravy", "dressing", "butter", "oil", "cream", "creamed", "cheese sauce",
        "smoothie", "nectar", "drink", "beverage", "soda", "meat and skin", "skin only",
        "thigh", "wing", "drumstick", "dark meat", "ground", "sausage", "bacon", "noodle", "noodles",
        "eggnog", "salad dressing", "refried", "baked beans", "pork and beans", "sweetened",
        "in heavy", "in light syrup", "canned in syrup", "sticks", "nuggets", "patty", "patties",
        "pastry", "tart", "cobbler", "sherbet", "sorbet", "ice cream", "frozen yogurt", "flavored",
        "vanilla", "fruit-on-the-bottom", "strawberry yogurt", "pickled", "pickle", "relish",
        "salted", "smoked salmon", "lox", "caviar", "roe", "tempura", "glazed", "honey", "candy",
        "potato", "potatoes", "fries", "pizza", "soup", "stew", "casserole", "sandwich", "wrap",
        "taco", "burrito", "salad, with", "mayonnaise", "imitation", "cereal", "cereals",
        "flakes", "flour", "meal", "starch", "tortilla", "tortillas", "grits", "chowder", "pudding"
    ]

    static func qualifies(_ food: FoodItem) -> Bool {
        guard food.source.isWholeFood else { return false }
        return qualifies(name: food.name)
    }

    static func qualifies(name: String) -> Bool {
        let text = " " + name.lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ") + " "
        for word in exclusions where contains(text, word) { return false }
        return rules.contains { rule in rule.allSatisfy { contains(text, $0) } }
    }

    /// Whole-word match, so "pear" does not match "pearl" and "egg" does not
    /// match "eggplant". Plurals count: "banana" matches "Bananas, raw".
    private static func contains(_ text: String, _ term: String) -> Bool {
        containsExactly(text, term) || containsExactly(text, term + "s") || containsExactly(text, term + "es")
    }

    private static func containsExactly(_ text: String, _ term: String) -> Bool {
        let separators = CharacterSet.alphanumerics.inverted
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, range: searchRange) {
            let beforeOK = range.lowerBound == text.startIndex
                || text[text.index(before: range.lowerBound)].unicodeScalars.allSatisfy { separators.contains($0) }
            let afterOK = range.upperBound == text.endIndex
                || text[range.upperBound].unicodeScalars.allSatisfy { separators.contains($0) }
            if beforeOK && afterOK { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }
}

// MARK: - Calorie deficit calculator

enum BiologicalSex: String, CaseIterable, Identifiable, Codable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? "Male" : "Female" }
}

enum ActivityLevel: String, CaseIterable, Identifiable, Codable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    /// Standard multipliers applied to BMR to estimate total daily burn.
    var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    var title: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Lightly active"
        case .moderate:   return "Moderately active"
        case .active:     return "Very active"
        case .veryActive: return "Extremely active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary:  return "Desk job, little or no exercise"
        case .light:      return "Light exercise 1–3 days a week"
        case .moderate:   return "Moderate exercise 3–5 days a week"
        case .active:     return "Hard exercise 6–7 days a week"
        case .veryActive: return "Physical job plus hard training"
        }
    }
}

enum WeightGoal: String, CaseIterable, Identifiable, Codable {
    case loseFast, lose, loseSlow, maintain, gainSlow, gain

    var id: String { rawValue }

    /// Pounds per week. 3,500 kcal ≈ 1 lb, so each pound a week is 500 kcal a day.
    var poundsPerWeek: Double {
        switch self {
        case .loseFast: return -2
        case .lose:     return -1.5
        case .loseSlow: return -1
        case .maintain: return 0
        case .gainSlow: return 0.5
        case .gain:     return 1
        }
    }

    var dailyCalorieAdjustment: Int { Int(poundsPerWeek * 500) }

    var title: String {
        switch self {
        case .loseFast: return "Lose 2 lb / week"
        case .lose:     return "Lose 1.5 lb / week"
        case .loseSlow: return "Lose 1 lb / week"
        case .maintain: return "Maintain weight"
        case .gainSlow: return "Gain 0.5 lb / week"
        case .gain:     return "Gain 1 lb / week"
        }
    }
}

struct BodyProfile: Codable, Equatable {
    var sex: BiologicalSex = .male
    var age: Int = 35
    var heightInches: Int = 70
    var weightPounds: Double = 185
    var activity: ActivityLevel = .light
    var goal: WeightGoal = .loseSlow
}

/// Mifflin-St Jeor, the equation most clinicians and calorie apps use today.
struct CalorieCalculation {
    let profile: BodyProfile

    var weightKg: Double { profile.weightPounds * 0.453592 }
    var heightCm: Double { Double(profile.heightInches) * 2.54 }

    /// Calories burned at complete rest.
    var bmr: Int {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(profile.age)
        return Int((base + (profile.sex == .male ? 5 : -161)).rounded())
    }

    /// Total daily energy expenditure: BMR scaled by activity.
    var tdee: Int { Int((Double(bmr) * profile.activity.multiplier).rounded()) }

    /// Commonly cited floors below which intake should be medically supervised.
    var minimumSafeCalories: Int { profile.sex == .male ? 1500 : 1200 }

    var unclampedTarget: Int { tdee + profile.goal.dailyCalorieAdjustment }

    var targetCalories: Int { max(minimumSafeCalories, unclampedTarget) }

    /// True when the chosen pace would have taken intake below the safe floor.
    var wasClamped: Bool { unclampedTarget < minimumSafeCalories }

    var dailyDeficit: Int { tdee - targetCalories }

    var projectedPoundsPerWeek: Double { Double(-dailyDeficit) * 7 / 3500 }

    // Macros: protein at 0.8 g per lb of body weight (capped at 220 g), fat at
    // 30% of calories, carbs fill what is left.
    var proteinGrams: Int { min(220, Int((profile.weightPounds * 0.8).rounded())) }
    var fatGrams: Int { Int((Double(targetCalories) * 0.30 / 9).rounded()) }
    var carbGrams: Int {
        let remaining = Double(targetCalories) - Double(proteinGrams * 4) - Double(fatGrams * 9)
        return max(50, Int((remaining / 4).rounded()))
    }

    /// Daily Bites Points. WW does not publish its budget formula; this lands
    /// in the same range WW members report (roughly 23 to 45 a day) by pricing
    /// the calorie target with the points formula and allowing for the share of
    /// a day's food that comes from zero-point foods and protein credit.
    var dailyPoints: Int {
        let priced = Double(targetCalories) * BitesPoints.caloriesFactor * 0.6
        return min(60, max(23, Int(priced.rounded())))
    }

    /// WW-style weekly extras on top of the daily budget.
    var weeklyPoints: Int { 28 }
}

// MARK: - Plan store

/// Profile, tracking mode and points budget. Calorie and macro goals still live
/// on DiaryStore; saving a plan writes them there.
final class PlanStore: ObservableObject {
    static let shared = PlanStore()

    @Published var trackingMode: TrackingMode { didSet { defaults.set(trackingMode.rawValue, forKey: Keys.mode) } }
    @Published var dailyPointsBudget: Int     { didSet { defaults.set(dailyPointsBudget, forKey: Keys.daily) } }
    @Published var weeklyPointsAllowance: Int { didSet { defaults.set(weeklyPointsAllowance, forKey: Keys.weekly) } }
    @Published var zeroPointFoodsEnabled: Bool { didSet { defaults.set(zeroPointFoodsEnabled, forKey: Keys.zeroPoint) } }
    /// Up to this many unused daily points carry into the weekly bank, as WW does.
    @Published var rolloverEnabled: Bool { didSet { defaults.set(rolloverEnabled, forKey: Keys.rollover) } }
    @Published var hasCompletedSetup: Bool { didSet { defaults.set(hasCompletedSetup, forKey: Keys.setupDone) } }
    @Published var profile: BodyProfile { didSet { saveProfile() } }

    static let maxRolloverPerDay = 4

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let mode      = "TrackingMode"
        static let daily     = "DailyPointsBudget"
        static let weekly    = "WeeklyPointsAllowance"
        static let zeroPoint = "ZeroPointFoodsEnabled"
        static let rollover  = "PointsRolloverEnabled"
        static let setupDone = "HasCompletedPlanSetup"
        static let profile   = "BodyProfileV1"
    }

    private init() {
        trackingMode = TrackingMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .macros
        dailyPointsBudget = defaults.int(forKey: Keys.daily, default: 30)
        weeklyPointsAllowance = defaults.int(forKey: Keys.weekly, default: 28)
        zeroPointFoodsEnabled = defaults.object(forKey: Keys.zeroPoint) as? Bool ?? true
        rolloverEnabled = defaults.object(forKey: Keys.rollover) as? Bool ?? true
        hasCompletedSetup = defaults.bool(forKey: Keys.setupDone)
        if let data = defaults.data(forKey: Keys.profile),
           let decoded = try? JSONDecoder().decode(BodyProfile.self, from: data) {
            profile = decoded
        } else {
            profile = BodyProfile()
        }
    }

    private func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Keys.profile)
        }
    }

    /// Writes a finished calculation into every goal it affects.
    func apply(_ calc: CalorieCalculation, mode: TrackingMode, to diary: DiaryStore) {
        profile = calc.profile
        trackingMode = mode
        dailyPointsBudget = calc.dailyPoints
        weeklyPointsAllowance = calc.weeklyPoints
        diary.calorieGoal = calc.targetCalories
        diary.proteinGoal = calc.proteinGrams
        diary.carbsGoal = calc.carbGrams
        diary.fatGoal = calc.fatGrams
        diary.logWeight(calc.profile.weightPounds)
        hasCompletedSetup = true
    }

    // MARK: Weekly points

    /// Start of the current points week. Matches the calendar's first weekday.
    func weekStart(for date: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    struct WeekSummary {
        let allowance: Int
        let rolledOver: Int
        let usedFromWeekly: Int
        var remaining: Int { allowance + rolledOver - usedFromWeekly }
        var total: Int { allowance + rolledOver }
    }

    /// Daily overruns this week draw down the weekly bank. Unused daily points
    /// on past days this week (up to 4 a day, and only on days something was
    /// tracked) roll into it.
    func weekSummary(days: [DayEntry], now: Date = Date()) -> WeekSummary {
        let calendar = Calendar.current
        let start = weekStart(for: now)
        let today = calendar.startOfDay(for: now)
        var used = 0
        var rolled = 0
        for day in days where day.date >= start && day.date <= today {
            let points = day.totalPoints
            if points > dailyPointsBudget {
                used += points - dailyPointsBudget
            } else if rolloverEnabled, day.date < today, !day.meals.isEmpty {
                rolled += min(Self.maxRolloverPerDay, dailyPointsBudget - points)
            }
        }
        return WeekSummary(allowance: weeklyPointsAllowance, rolledOver: rolled, usedFromWeekly: used)
    }
}
