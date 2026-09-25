// OpenFoodFactsService.swift
import Foundation

// MARK: - Wire types

private struct OFFProductResponse: Decodable {
    let status: Int?
    let product: OFFProduct?
}

struct OFFProduct: Decodable {
    let code: String?
    let product_name: String?
    let generic_name: String?
    let brands: String?
    let quantity: String?
    let serving_size: String?
    let serving_quantity: LooseDouble?
    let nutriments: OFFNutriments?
}

struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcal: Double?
    let energy100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?
    let salt100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g    = "energy-kcal_100g"
        case energyKcal        = "energy-kcal"
        case energy100g        = "energy_100g"
        case proteins100g      = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g           = "fat_100g"
        case fiber100g         = "fiber_100g"
        case sugars100g        = "sugars_100g"
        case sodium100g        = "sodium_100g"
        case salt100g          = "salt_100g"
    }

    var nutrition: Nutrition {
        var calories = energyKcal100g ?? energyKcal ?? 0
        if calories == 0, let kj = energy100g, kj > 0 {
            calories = kj / 4.184
        }

        // Open Food Facts reports sodium in grams per 100 g. Salt is the more
        // commonly filled field outside the US, so fall back to salt / 2.5.
        var sodiumMg: Double?
        if let sodium = sodium100g {
            sodiumMg = sodium * 1000
        } else if let salt = salt100g {
            sodiumMg = salt * 1000 / 2.5
        }

        return Nutrition(
            calories: calories,
            protein: proteins100g ?? 0,
            carbs: carbohydrates100g ?? 0,
            fat: fat100g ?? 0,
            fiber: fiber100g,
            sugar: sugars100g,
            sodium: sodiumMg
        )
    }
}

// MARK: - Service

/// Open Food Facts is kept for one job: barcodes. Its coverage of scanned
/// packages beats USDA's, which has no barcode endpoint at all. Text search
/// goes to USDA instead, because Open Food Facts has almost no generic
/// ingredients.
actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let session: URLSession

    /// Open Food Facts rejects or throttles requests without an identifying
    /// User-Agent.
    private let userAgent = "Bites/1.0 (iOS; personal food diary)"

    private let fields = [
        "code", "product_name", "generic_name", "brands", "quantity",
        "serving_size", "serving_quantity", "nutriments"
    ].joined(separator: ",")

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func lookupBarcode(_ barcode: String) async throws -> FoodItem? {
        let digits = barcode.filter(\.isNumber)
        guard Barcode.isPlausible(digits) else { throw FoodServiceError.notFound }
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)") else {
            throw FoodServiceError.network
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw FoodServiceError.network
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard (200..<300).contains(http.statusCode) else {
                throw FoodServiceError.http(http.statusCode)
            }
        }

        guard
            let decoded = try? JSONDecoder().decode(OFFProductResponse.self, from: data),
            decoded.status == 1,
            let product = decoded.product
        else { return nil }

        return Self.foodItem(from: product, fallbackBarcode: digits)
    }

    // MARK: Mapping

    static func foodItem(from product: OFFProduct, fallbackBarcode: String) -> FoodItem? {
        let nutrition = product.nutriments?.nutrition ?? Nutrition()
        guard nutrition.isUsable else { return nil }

        let name = [product.product_name, product.generic_name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let brand = product.brands?
            .split(separator: ",")
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let code = product.code ?? fallbackBarcode

        return FoodItem(
            id: "off:\(code)",
            name: name ?? "Unnamed product",
            brand: (brand?.isEmpty == false) ? brand : nil,
            source: .openFoodFacts,
            per100g: nutrition,
            servingGrams: servingGrams(from: product),
            servingLabel: product.serving_size?.trimmingCharacters(in: .whitespaces),
            barcode: code,
            fdcId: nil
        )
    }

    private static func servingGrams(from product: OFFProduct) -> Double? {
        if let value = product.serving_quantity?.value, value > 0 { return value }
        guard let text = product.serving_size else { return nil }
        return parseGrams(from: text)
    }

    /// Pulls a gram weight out of strings like "40 g" or "1 cup (240 ml)".
    static func parseGrams(from text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        var number = ""
        for character in normalized {
            if character.isNumber || character == "." {
                number.append(character)
            } else if !number.isEmpty {
                break
            }
        }
        guard let value = Double(number), value > 0 else { return nil }

        let lower = normalized.lowercased()
        if lower.contains("kg") { return value * 1000 }
        if lower.contains("oz") { return value * 28.3495 }
        if lower.contains("lb") { return value * 453.592 }
        return value
    }
}
