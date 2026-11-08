// FoodSearchService.swift
import Foundation
import SwiftUI

/// Coordinates the two food sources.
///
/// USDA FoodData Central handles text search: it is the only free source with
/// real generic ingredients ("Chicken, broiler or fryers, breast, skinless,
/// boneless, meat only, raw") rather than only packaged goods. Open Food Facts
/// handles barcodes, where its coverage beats USDA's, with USDA branded as a
/// fallback for products Open Food Facts has not seen.
@MainActor
final class FoodSearchService: ObservableObject {
    static let shared = FoodSearchService()

    @Published private(set) var wholeFoods: [FoodItem] = []
    @Published private(set) var brandedFoods: [FoodItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastQuery = ""

    @Published var isLookingUpBarcode = false
    @Published var barcodeError: String?

    private var searchTask: Task<Void, Never>?

    private init() {}

    var hasResults: Bool { !wholeFoods.isEmpty || !brandedFoods.isEmpty }
    var needsAPIKey: Bool { !Secrets.hasUSDAKey }

    // MARK: - Text search

    func search(_ query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            wholeFoods = []
            brandedFoods = []
            errorMessage = nil
            isSearching = false
            lastQuery = ""
            return
        }

        guard Secrets.hasUSDAKey else {
            wholeFoods = []
            brandedFoods = []
            isSearching = false
            errorMessage = FoodServiceError.missingAPIKey.errorDescription
            return
        }

        isSearching = true
        errorMessage = nil

        searchTask = Task { [weak self] in
            // Debounce so typing does not burn the hourly request budget.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.run(trimmed)
        }
    }

    private func run(_ query: String) async {
        let service = USDAFoodService.shared

        // Two requests, run concurrently, so branded volume can never crowd
        // out whole foods the way a single blended query does.
        let wholeTask = Task { try await service.searchWholeFoods(query) }
        let brandedTask = Task { try await service.searchBranded(query) }

        let whole = await wholeTask.result
        let branded = await brandedTask.result

        guard !Task.isCancelled else { return }

        lastQuery = query
        isSearching = false

        switch (whole, branded) {
        case let (.success(a), .success(b)):
            wholeFoods = Self.ranked(a)
            brandedFoods = Self.ranked(b)
            errorMessage = (a.isEmpty && b.isEmpty) ? "No foods matched \"\(query)\"." : nil

        case let (.success(a), .failure(error)):
            wholeFoods = Self.ranked(a)
            brandedFoods = []
            errorMessage = a.isEmpty ? Self.message(for: error) : nil

        case let (.failure(error), .success(b)):
            wholeFoods = []
            brandedFoods = Self.ranked(b)
            errorMessage = b.isEmpty ? Self.message(for: error) : nil

        case let (.failure(error), .failure):
            wholeFoods = []
            brandedFoods = []
            errorMessage = Self.message(for: error)
        }
    }

    /// Foundation before SR Legacy before Survey, de-duplicated by id.
    private static func ranked(_ items: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>()
        return items
            .filter { seen.insert($0.id).inserted }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.source.rank != rhs.element.source.rank {
                    return lhs.element.source.rank < rhs.element.source.rank
                }
                return lhs.offset < rhs.offset   // preserve USDA relevance within a tier
            }
            .map(\.element)
    }

    private static func message(for error: Error) -> String? {
        if error is CancellationError { return nil }
        return (error as? FoodServiceError)?.errorDescription
            ?? FoodServiceError.network.errorDescription
    }

    func clear() {
        searchTask?.cancel()
        wholeFoods = []
        brandedFoods = []
        errorMessage = nil
        isSearching = false
        lastQuery = ""
    }

    // MARK: - Barcode

    /// Open Food Facts first, USDA branded as fallback.
    func lookup(barcode: String) async -> FoodItem? {
        isLookingUpBarcode = true
        barcodeError = nil
        defer { isLookingUpBarcode = false }

        do {
            if let item = try await OpenFoodFactsService.shared.lookupBarcode(barcode) {
                RecentFoodsStore.shared.recordScan(item)
                return item
            }
        } catch is CancellationError {
            return nil
        } catch {
            // Fall through and try USDA before reporting anything.
        }

        if Secrets.hasUSDAKey {
            do {
                if let item = try await USDAFoodService.shared.lookupBarcode(barcode) {
                    RecentFoodsStore.shared.recordScan(item)
                    return item
                }
            } catch is CancellationError {
                return nil
            } catch {
                barcodeError = (error as? FoodServiceError)?.errorDescription
                return nil
            }
        }

        barcodeError = "No product found for \(barcode). You can still add it by hand."
        return nil
    }
}
