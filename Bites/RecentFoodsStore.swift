// RecentFoodsStore.swift
import Foundation
import SwiftUI

/// Recents and favourites are what make logging feel instant: most days you
/// eat the same twenty things, so the search box should rarely be needed.
final class RecentFoodsStore: ObservableObject {
    static let shared = RecentFoodsStore()

    struct Entry: Identifiable, Codable, Hashable {
        var food: FoodItem
        var lastUsed: Date
        var useCount: Int
        /// Grams of the portion logged last time, so re-logging is one tap.
        var lastGrams: Double?
        var isFavorite: Bool

        var id: String { food.id }

        init(food: FoodItem, lastUsed: Date = Date(), useCount: Int = 1, lastGrams: Double? = nil, isFavorite: Bool = false) {
            self.food = food
            self.lastUsed = lastUsed
            self.useCount = useCount
            self.lastGrams = lastGrams
            self.isFavorite = isFavorite
        }

        private enum CodingKeys: String, CodingKey {
            case food, lastUsed, useCount, lastGrams, isFavorite
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            food       = try c.decode(FoodItem.self, forKey: .food)
            lastUsed   = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
            useCount   = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 1
            lastGrams  = try c.decodeIfPresent(Double.self, forKey: .lastGrams)
            isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        }
    }

    @Published private(set) var entries: [Entry] = [] { didSet { save() } }

    private let key = "BitesRecentFoodsV1"
    private let maxRecents = 60
    private var isLoading = true

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        isLoading = false
    }

    // MARK: - Reads

    /// Favourites first, then most recently used.
    var recents: [Entry] {
        entries
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(30)
            .map { $0 }
    }

    var favorites: [Entry] {
        entries
            .filter(\.isFavorite)
            .sorted { $0.useCount > $1.useCount }
    }

    var hasAnything: Bool { !entries.isEmpty }

    func isFavorite(_ food: FoodItem) -> Bool {
        entries.first(where: { $0.food.id == food.id })?.isFavorite ?? false
    }

    // MARK: - Writes

    func record(_ food: FoodItem, grams: Double?) {
        if let index = entries.firstIndex(where: { $0.food.id == food.id }) {
            entries[index].food = food          // refresh in case nutrition changed
            entries[index].lastUsed = Date()
            entries[index].useCount += 1
            entries[index].lastGrams = grams ?? entries[index].lastGrams
        } else {
            entries.append(Entry(food: food, lastGrams: grams))
        }
        trim()
    }

    func toggleFavorite(_ food: FoodItem) {
        if let index = entries.firstIndex(where: { $0.food.id == food.id }) {
            entries[index].isFavorite.toggle()
        } else {
            entries.append(Entry(food: food, useCount: 0, isFavorite: true))
        }
    }

    func remove(_ food: FoodItem) {
        entries.removeAll { $0.food.id == food.id }
    }

    func clearRecents() {
        entries.removeAll { !$0.isFavorite }
    }

    /// Favourites are never dropped, however old.
    private func trim() {
        guard entries.count > maxRecents else { return }
        let sorted = entries.sorted { $0.lastUsed > $1.lastUsed }
        var kept: [Entry] = []
        var nonFavoriteCount = 0
        for entry in sorted {
            if entry.isFavorite {
                kept.append(entry)
            } else if nonFavoriteCount < maxRecents {
                kept.append(entry)
                nonFavoriteCount += 1
            }
        }
        entries = kept
    }

    private func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
