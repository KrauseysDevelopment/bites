// FoodItem.swift
import Foundation
import SwiftUI

// MARK: - Source

enum FoodSource: String, Codable, Hashable {
    case usdaFoundation
    case usdaSRLegacy
    case usdaSurvey
    case usdaBranded
    case openFoodFacts

    /// Whole ingredients rank above packaged products in search.
    var isWholeFood: Bool {
        switch self {
        case .usdaFoundation, .usdaSRLegacy, .usdaSurvey: return true
        case .usdaBranded, .openFoodFacts:                return false
        }
    }

    var label: String {
        switch self {
        case .usdaFoundation: return "USDA Lab"
        case .usdaSRLegacy:   return "USDA Standard"
        case .usdaSurvey:     return "USDA Survey"
        case .usdaBranded:    return "Branded"
        case .openFoodFacts:  return "Open Food Facts"
        }
    }

    var color: Color {
        switch self {
        case .usdaFoundation: return .green
        case .usdaSRLegacy:   return .teal
        case .usdaSurvey:     return .blue
        case .usdaBranded:    return .orange
        case .openFoodFacts:  return .purple
        }
    }

    /// Quality ordering within the whole-food group. Foundation entries are
    /// freshly lab-analyzed, SR Legacy is the older reference set, Survey is
    /// modelled from dietary recall data.
    var rank: Int {
        switch self {
        case .usdaFoundation: return 0
        case .usdaSRLegacy:   return 1
        case .usdaSurvey:     return 2
        case .usdaBranded:    return 3
        case .openFoodFacts:  return 4
        }
    }

    init?(usdaDataType: String) {
        switch usdaDataType.lowercased() {
        case "foundation":      self = .usdaFoundation
        case "sr legacy":       self = .usdaSRLegacy
        case "survey (fndds)":  self = .usdaSurvey
        case "branded":         self = .usdaBranded
        default:                return nil
        }
    }
}

// MARK: - Nutrition (always per 100 g)

struct Nutrition: Codable, Hashable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?   // milligrams

    var isUsable: Bool { calories > 0 || protein > 0 || carbs > 0 || fat > 0 }

    func scaled(toGrams grams: Double) -> Nutrition {
        let factor = grams / 100.0
        return Nutrition(
            calories: calories * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber.map { $0 * factor },
            sugar: sugar.map { $0 * factor },
            sodium: sodium.map { $0 * factor }
        )
    }
}

// MARK: - Food Item
//
// One normalized shape for results out of USDA FoodData Central and Open Food
// Facts. Both report per 100 g, so scaling happens in exactly one place.

struct FoodItem: Identifiable, Codable, Hashable {
    /// Stable across launches: "usda:1750340" or "off:0041303020937".
    var id: String
    var name: String
    var brand: String?
    var source: FoodSource
    var per100g: Nutrition
    /// Grams in one declared serving, when the source provides it.
    var servingGrams: Double?
    /// Human label for that serving, e.g. "1 cup, chopped" or "1 PIECE".
    var servingLabel: String?
    var barcode: String?
    /// USDA id, kept so we can pull full detail later if needed.
    var fdcId: Int?

    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(name) – \(brand)"
    }

    var hasServing: Bool { (servingGrams ?? 0) > 0 }

    /// "1 PIECE (40 g)" when both are known, otherwise whichever exists.
    var servingDescription: String? {
        switch (servingLabel, servingGrams) {
        case let (label?, grams?):
            return "\(label) (\(Int(grams.rounded())) g)"
        case let (label?, nil):
            return label
        case let (nil, grams?):
            return "\(Int(grams.rounded())) g"
        default:
            return nil
        }
    }

    func meal(grams: Double, category: MealCategory, portionName: String) -> Meal {
        let scaled = per100g.scaled(toGrams: grams)
        return Meal(
            name: portionName,
            calories: Int(scaled.calories.rounded()),
            protein: Int(scaled.protein.rounded()),
            carbs: Int(scaled.carbs.rounded()),
            fat: Int(scaled.fat.rounded()),
            category: category,
            servingGrams: servingGrams
        )
    }
}

// MARK: - Barcode helpers

enum Barcode {
    /// UPC-A (12 digits) is EAN-13 with a leading zero, and sources disagree on
    /// whether to keep it. Compare on the stripped form.
    static func normalized(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let stripped = String(digits.drop(while: { $0 == "0" }))
        return stripped.isEmpty ? digits : stripped
    }

    static func matches(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return normalized(a) == normalized(b)
    }

    static func isPlausible(_ raw: String) -> Bool {
        let digits = raw.filter(\.isNumber)
        return (8...14).contains(digits.count)
    }
}

// MARK: - Lenient decoding
//
// Both food APIs are loose about types: USDA returns servingSize as a number
// but gtinUpc sometimes as a number and sometimes a quoted string, and Open
// Food Facts is crowd-sourced and inconsistent throughout. A single mistyped
// field would otherwise throw and take the whole response down with it.

struct LooseDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = Double(string.replacingOccurrences(of: ",", with: "."))
        } else {
            value = nil
        }
    }
}

struct LooseString: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int64.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(Int64(double))
        } else {
            value = nil
        }
    }
}
