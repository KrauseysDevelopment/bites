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
        /// Set when the food came from the barcode scanner. Drives the Scanned list.
        var scannedAt: Date?

        var id: String { food.id }

        init(food: FoodItem, lastUsed: Date = Date(), useCount: Int = 1, lastGrams: Double? = nil,
             isFavorite: Bool = false, scannedAt: Date? = nil) {
            self.food = food
            self.lastUsed = lastUsed
            self.useCount = useCount
            self.lastGrams = lastGrams
            self.isFavorite = isFavorite
            self.scannedAt = scannedAt
        }

        private enum CodingKeys: String, CodingKey {
            case food, lastUsed, useCount, lastGrams, isFavorite, scannedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            food       = try c.decode(FoodItem.self, forKey: .food)
            lastUsed   = try c.decodeIfPresent(Date.self, forKey: .lastUsed) ?? Date()
            useCount   = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 1
            lastGrams  = try c.decodeIfPresent(Double.self, forKey: .lastGrams)
            isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
            scannedAt  = try c.decodeIfPresent(Date.self, forKey: .scannedAt)
        }
    }

    @Published private(set) var entries: [Entry] = [] { didSet { save() } }

    private let key = "BitesRecentFoodsV1"
    private let maxRecents = 60
    private let maxScanned = 200
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
            .filter { $0.useCount > 0 }   // scanned or starred but never logged
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(30)
            .map { $0 }
    }

    var favorites: [Entry] {
        entries
            .filter(\.isFavorite)
            .sorted { $0.useCount > $1.useCount }
    }

    /// Everything that came through the barcode scanner, newest first.
    var scanned: [Entry] {
        entries
            .filter { $0.scannedAt != nil }
            .sorted { ($0.scannedAt ?? .distantPast) > ($1.scannedAt ?? .distantPast) }
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

    /// Called on every successful barcode lookup, whether or not it gets logged.
    func recordScan(_ food: FoodItem) {
        if let index = entries.firstIndex(where: { $0.food.id == food.id }) {
            entries[index].food = food
            entries[index].scannedAt = Date()
        } else {
            entries.append(Entry(food: food, useCount: 0, scannedAt: Date()))
        }
        trim()
    }

    /// Takes a food off the Scanned list, and drops it entirely when nothing
    /// else (favourite, recent use) is keeping it.
    func removeFromScanned(_ food: FoodItem) {
        guard let index = entries.firstIndex(where: { $0.food.id == food.id }) else { return }
        if entries[index].isFavorite || entries[index].useCount > 0 {
            entries[index].scannedAt = nil
        } else {
            entries.remove(at: index)
        }
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

    /// Clears the Recent list only. Favourites and scanned foods stay.
    func clearRecents() {
        entries.removeAll { !$0.isFavorite && $0.scannedAt == nil }
    }

    /// Favourites are never dropped, however old. Scanned foods are kept up to
    /// their own, larger limit.
    private func trim() {
        let favorites = entries.filter(\.isFavorite)
        let scannedOnly = entries
            .filter { !$0.isFavorite && $0.scannedAt != nil }
            .sorted { ($0.scannedAt ?? .distantPast) > ($1.scannedAt ?? .distantPast) }
            .prefix(maxScanned)
        let others = entries
            .filter { !$0.isFavorite && $0.scannedAt == nil }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(maxRecents)
        let kept = favorites + Array(scannedOnly) + Array(others)
        guard kept.count != entries.count else { return }
        entries = kept
    }

    private func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
