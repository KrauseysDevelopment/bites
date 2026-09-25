// Secrets.swift
import Foundation

/// Resolves the USDA FoodData Central API key.
///
/// Lookup order:
///   1. `Secrets.plist` in the app bundle, key `USDA_API_KEY`. This file is
///      gitignored so the key never lands in the repo. USDA deactivates keys
///      it finds published.
///   2. A key pasted into Settings, stored in UserDefaults.
///
/// Free signup, key arrives by email immediately:
/// https://fdc.nal.usda.gov/api-key-signup/
enum Secrets {
    private static let userDefaultsKey = "USDAAPIKey"

    static var usdaAPIKey: String? {
        if let bundled = bundledKey, !bundled.isEmpty, bundled != placeholder {
            return bundled
        }
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stored?.isEmpty == false) ? stored : nil
    }

    static var hasUSDAKey: Bool { usdaAPIKey != nil }

    static func storeUSDAKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
    }

    static var storedKeyForDisplay: String {
        UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
    }

    /// True when the key came from the bundled plist rather than Settings,
    /// so the Settings field can say so instead of looking empty.
    static var keyIsBundled: Bool {
        guard let bundled = bundledKey else { return false }
        return !bundled.isEmpty && bundled != placeholder
    }

    private static let placeholder = "PASTE_YOUR_USDA_API_KEY_HERE"

    private static var bundledKey: String? {
        guard
            let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["USDA_API_KEY"] as? String
    }
}
