// USDAFoodService.swift
import Foundation

// MARK: - Errors

enum FoodServiceError: LocalizedError {
    case missingAPIKey
    case rateLimited
    case http(Int)
    case network
    case notFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your free USDA API key in Settings to search foods."
        case .rateLimited:
            return "USDA rate limit reached. It resets within the hour."
        case .http(let code):
            return "Food database returned \(code). Try again shortly."
        case .network:
            return "Could not reach the food database. Check your connection."
        case .notFound:
            return "No match found."
        }
    }
}

// MARK: - Wire types
//
// IMPORTANT: /foods/search and /food/{fdcId} return DIFFERENT shapes for
// foodNutrients. Search is flat (nutrientId / value, uppercase unitName);
// detail is nested (nutrient.id / amount, lowercase unitName). The published
// OpenAPI spec documents only the detail shape and is wrong about search,
// so these two types must stay separate.

private struct USDASearchResponse: Decodable {
    let totalHits: Int?
    let foods: [USDASearchFood]?
}

private struct USDASearchFood: Decodable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let gtinUpc: LooseString?
    let servingSize: LooseDouble?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodCategory: String?
    let score: Double?
    let foodNutrients: [USDASearchNutrient]?
}

private struct USDASearchNutrient: Decodable {
    let nutrientId: Int?
    let nutrientName: String?
    let nutrientNumber: String?   // string, and not always integer-parseable ("321.1")
    let unitName: String?
    let value: Double?
}

private struct USDADetailResponse: Decodable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let brandName: String?
    let gtinUpc: LooseString?
    let servingSize: LooseDouble?
    let servingSizeUnit: String?
    let householdServingFullText: String?
    let foodNutrients: [USDADetailNutrient]?
}

private struct USDADetailNutrient: Decodable {
    struct Inner: Decodable {
        let id: Int?
        let number: String?
        let name: String?
        let unitName: String?
    }
    // Some branded records return an entry with no nutrient object at all.
    let nutrient: Inner?
    let amount: Double?
}

// MARK: - Nutrient identifiers

private enum NutrientID {
    static let energyKcal = 1008
    static let energyKJ = 1062
    static let energyAtwaterGeneral = 2047
    static let energyAtwaterSpecific = 2048
    static let protein = 1003
    static let fat = 1004
    static let carbs = 1005
    static let fiber = 1079
    static let sugarsTotal = 2000
    static let sugarsNLEA = 1063   // what most Branded records actually carry
    static let sodium = 1093
    static let saturatedFat = 1258
}

// MARK: - Service

actor USDAFoodService {
    static let shared = USDAFoodService()

    private let base = "https://api.nal.usda.gov/fdc/v1"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    // MARK: Search

    /// Whole ingredients: Foundation, SR Legacy and Survey. Queried separately
    /// from branded so a term like "chicken breast" cannot be buried under
    /// thousands of packaged products that happen to score higher.
    ///
    /// "Survey (FNDDS)" is the awkward one: its parentheses make the API
    /// return 400 over GET, and the POST form is documented but not something
    /// we can lean on. If it is rejected, fall back to the two datasets that
    /// carry the quality anyway rather than losing whole-food search entirely.
    func searchWholeFoods(_ query: String, limit: Int = 25) async throws -> [FoodItem] {
        do {
            return try await search(
                query,
                dataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"],
                limit: limit
            )
        } catch FoodServiceError.http(400) {
            return try await search(query, dataTypes: ["Foundation", "SR Legacy"], limit: limit)
        }
    }

    func searchBranded(_ query: String, limit: Int = 25) async throws -> [FoodItem] {
        try await search(query, dataTypes: ["Branded"], limit: limit)
    }

    private func search(_ query: String, dataTypes: [String], limit: Int) async throws -> [FoodItem] {
        guard let key = Secrets.usdaAPIKey else { throw FoodServiceError.missingAPIKey }
        guard let url = URL(string: "\(base)/foods/search?api_key=\(key)") else {
            throw FoodServiceError.network
        }

        // POST, because multiple dataType values are only reliably accepted as
        // a JSON array. The GET comma-separated form is undocumented.
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": query,
            "dataType": dataTypes,
            "pageSize": limit,
            "pageNumber": 1
        ])

        let decoded: USDASearchResponse = try await perform(request)
        let foods = decoded.foods ?? []
        return foods.compactMap(Self.foodItem(from:))
    }

    // MARK: Barcode

    /// USDA has no barcode endpoint. The barcode goes into the full-text query
    /// and every hit must be checked against gtinUpc, because the search is
    /// fuzzy and will happily return unrelated products.
    func lookupBarcode(_ barcode: String) async throws -> FoodItem? {
        guard let key = Secrets.usdaAPIKey else { throw FoodServiceError.missingAPIKey }
        guard let url = URL(string: "\(base)/foods/search?api_key=\(key)") else {
            throw FoodServiceError.network
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "query": barcode,
            "dataType": ["Branded"],
            "pageSize": 25,
            "pageNumber": 1
        ])

        let decoded: USDASearchResponse = try await perform(request)
        let match = (decoded.foods ?? []).first { Barcode.matches($0.gtinUpc?.value, barcode) }
        return match.flatMap(Self.foodItem(from:))
    }

    // MARK: Detail

    func detail(fdcId: Int) async throws -> FoodItem? {
        guard let key = Secrets.usdaAPIKey else { throw FoodServiceError.missingAPIKey }
        guard let url = URL(string: "\(base)/food/\(fdcId)?api_key=\(key)") else {
            throw FoodServiceError.network
        }
        let decoded: USDADetailResponse = try await perform(URLRequest(url: url))
        return Self.foodItem(from: decoded)
    }

    // MARK: Transport

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw FoodServiceError.network
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 429:       throw FoodServiceError.rateLimited
            case 403:       throw FoodServiceError.missingAPIKey
            case 404:       throw FoodServiceError.notFound
            default:        throw FoodServiceError.http(http.statusCode)
            }
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FoodServiceError.network
        }
    }

    // MARK: Mapping

    private static func foodItem(from food: USDASearchFood) -> FoodItem? {
        guard let source = FoodSource(usdaDataType: food.dataType ?? "") else { return nil }

        var values: [Int: Double] = [:]
        for nutrient in food.foodNutrients ?? [] {
            guard let id = nutrient.nutrientId, let value = nutrient.value else { continue }
            values[id] = value
        }

        let nutrition = nutrition(from: values)
        guard nutrition.isUsable else { return nil }

        return FoodItem(
            id: "usda:\(food.fdcId)",
            name: cleanedName(food.description),
            brand: brandLabel(owner: food.brandOwner, name: food.brandName),
            source: source,
            per100g: nutrition,
            servingGrams: servingGrams(size: food.servingSize?.value, unit: food.servingSizeUnit),
            servingLabel: cleanedServingLabel(food.householdServingFullText),
            barcode: food.gtinUpc?.value,
            fdcId: food.fdcId
        )
    }

    private static func foodItem(from food: USDADetailResponse) -> FoodItem? {
        guard let source = FoodSource(usdaDataType: food.dataType ?? "") else { return nil }

        var values: [Int: Double] = [:]
        for entry in food.foodNutrients ?? [] {
            guard let id = entry.nutrient?.id, let amount = entry.amount else { continue }
            values[id] = amount
        }

        let nutrition = nutrition(from: values)
        guard nutrition.isUsable else { return nil }

        return FoodItem(
            id: "usda:\(food.fdcId)",
            name: cleanedName(food.description),
            brand: brandLabel(owner: food.brandOwner, name: food.brandName),
            source: source,
            per100g: nutrition,
            servingGrams: servingGrams(size: food.servingSize?.value, unit: food.servingSizeUnit),
            servingLabel: cleanedServingLabel(food.householdServingFullText),
            barcode: food.gtinUpc?.value,
            fdcId: food.fdcId
        )
    }

    private static func nutrition(from values: [Int: Double]) -> Nutrition {
        // Foundation foods stopped reporting plain "Energy" (1008) in late 2020
        // in favour of the Atwater variants, so fall through them in order.
        var calories = values[NutrientID.energyKcal]
            ?? values[NutrientID.energyAtwaterSpecific]
            ?? values[NutrientID.energyAtwaterGeneral]
            ?? 0
        if calories == 0, let kj = values[NutrientID.energyKJ], kj > 0 {
            calories = kj / 4.184
        }

        return Nutrition(
            calories: calories,
            protein: values[NutrientID.protein] ?? 0,
            carbs: values[NutrientID.carbs] ?? 0,
            fat: values[NutrientID.fat] ?? 0,
            fiber: values[NutrientID.fiber],
            sugar: values[NutrientID.sugarsTotal] ?? values[NutrientID.sugarsNLEA],
            sodium: values[NutrientID.sodium],
            saturatedFat: values[NutrientID.saturatedFat]
        )
    }

    /// USDA descriptions are ALL CAPS on branded items and comma-heavy on
    /// reference ones. Title-case the shouty ones, leave the rest alone.
    private static func cleanedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.filter(\.isLetter)
        guard !letters.isEmpty else { return trimmed }
        let uppercaseRatio = Double(letters.filter(\.isUppercase).count) / Double(letters.count)
        guard uppercaseRatio > 0.85 else { return trimmed }
        return trimmed.capitalized
    }

    private static func brandLabel(owner: String?, name: String?) -> String? {
        let candidates = [name, owner]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = candidates.first else { return nil }
        return cleanedName(first)
    }

    /// Only mass and volume convert cleanly to a gram weight.
    ///
    /// USDA reports the unit as a UN/CEFACT code, not a plain abbreviation:
    /// branded foods come back as "GRM" and "MLT", never "g" or "ml". Missing
    /// those silently dropped every branded serving size.
    private static func servingGrams(size: Double?, unit: String?) -> Double? {
        guard let size, size > 0, let unit = unit?.lowercased() else { return nil }
        switch unit {
        case "g", "grm", "gram", "grams":
            return size
        case "ml", "mlt", "millilitre", "milliliter", "milliliters":
            return size          // assumes water-like density
        case "oz", "onz":
            return size * 28.3495
        case "lb", "lbr":
            return size * 453.592
        case "kg", "kgm":
            return size * 1000
        case "l", "ltr":
            return size * 1000
        default:
            return nil
        }
    }

    private static func cleanedServingLabel(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return cleanedName(raw)
    }
}
