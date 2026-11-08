// ServingPickerView.swift
import SwiftUI

/// Turns a per-100 g FoodItem into a logged portion.
/// Replaces ServingSizeEntryView, which assumed every food was 100 g per
/// serving because servingGrams was never populated.
struct ServingPickerView: View {
    let food: FoodItem
    let initialCategory: MealCategory
    let initialGrams: Double?
    let onConfirm: (Meal, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recents = RecentFoodsStore.shared
    @ObservedObject private var plan = PlanStore.shared

    @State private var amount: String
    @State private var unit: ServingUnit
    @State private var category: MealCategory

    init(
        food: FoodItem,
        category: MealCategory,
        initialGrams: Double? = nil,
        onConfirm: @escaping (Meal, Double) -> Void
    ) {
        self.food = food
        self.initialCategory = category
        self.initialGrams = initialGrams
        self.onConfirm = onConfirm

        _category = State(initialValue: category)

        // Prefer the declared serving, then whatever was logged last time,
        // then a plain 100 g.
        if food.hasServing {
            _unit = State(initialValue: .serving)
            if let grams = initialGrams, let size = food.servingGrams, size > 0 {
                _amount = State(initialValue: Self.trimmed(grams / size))
            } else {
                _amount = State(initialValue: "1")
            }
        } else {
            _unit = State(initialValue: .grams)
            _amount = State(initialValue: Self.trimmed(initialGrams ?? 100))
        }
    }

    enum ServingUnit: String, CaseIterable, Identifiable {
        case serving = "serving"
        case grams = "g"
        case ounces = "oz"
        case cups = "cup"
        case tablespoons = "tbsp"

        var id: String { rawValue }

        /// Volume conversions assume water-like density, the usual caveat.
        var gramsPerUnit: Double {
            switch self {
            case .serving:     return 1        // resolved from the food
            case .grams:       return 1
            case .ounces:      return 28.3495
            case .cups:        return 240
            case .tablespoons: return 14.7868
            }
        }
    }

    // MARK: - Math

    private var amountValue: Double {
        Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var totalGrams: Double {
        if unit == .serving {
            return amountValue * (food.servingGrams ?? 100)
        }
        return amountValue * unit.gramsPerUnit
    }

    private var scaled: Nutrition { food.per100g.scaled(toGrams: totalGrams) }

    private var availableUnits: [ServingUnit] {
        food.hasServing ? ServingUnit.allCases : ServingUnit.allCases.filter { $0 != .serving }
    }

    private var isValid: Bool { amountValue > 0 && totalGrams > 0 }

    private var portionName: String {
        let qty = Self.trimmed(amountValue)
        switch unit {
        case .serving:
            let label = food.servingLabel ?? "serving"
            return amountValue == 1 ? "\(label) \(food.name)" : "\(qty) × \(label) \(food.name)"
        case .grams:
            return "\(qty) g \(food.name)"
        default:
            return "\(qty) \(unit.rawValue) \(food.name)"
        }
    }

    /// Each unit gets amounts that make sense for it. Offering 25 through 250
    /// for tablespoons or ounces was nonsense.
    private var quickAmounts: [Double] {
        switch unit {
        case .serving:     return [0.5, 1, 1.5, 2, 3]
        case .grams:       return [25, 50, 100, 150, 200, 250]
        case .ounces:      return [1, 2, 3, 4, 6, 8]
        case .cups:        return [0.25, 0.33, 0.5, 0.75, 1, 1.5, 2]
        case .tablespoons: return [0.5, 1, 2, 3, 4, 6]
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("1", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .frame(width: 96)

                        Picker("Unit", selection: $unit) {
                            ForEach(availableUnits) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: unit) { previous, next in
                            convertAmount(from: previous, to: next)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickAmounts, id: \.self) { value in
                                Button {
                                    amount = Self.trimmed(value)
                                } label: {
                                    Text(Self.trimmed(value))
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(
                                            isSelected(value)
                                                ? Color.orange.opacity(0.18)
                                                : Color.secondary.opacity(0.1),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isSelected(value) ? .orange : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))

                    if let serving = food.servingDescription, food.hasServing {
                        Text("Declared serving: \(serving)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !food.hasServing {
                        Text("No serving size on file for this item, so enter a weight.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if totalGrams > 0 {
                        Text("Logging \(Int(totalGrams.rounded())) g")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("How much?")
                }

                Section("Meal") {
                    Picker("Category", selection: $category) {
                        ForEach(MealCategory.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("This Portion") {
                    if plan.trackingMode == .points {
                        pointsRow
                    }
                    macroRow("Calories", value: scaled.calories, unit: "kcal", color: .orange)
                    macroRow("Protein",  value: scaled.protein,  unit: "g", color: .green)
                    macroRow("Carbs",    value: scaled.carbs,    unit: "g", color: .purple)
                    macroRow("Fat",      value: scaled.fat,      unit: "g", color: .amber)
                    if let fiber = scaled.fiber {
                        macroRow("Fiber", value: fiber, unit: "g", color: .brown)
                    }
                    if let sodium = scaled.sodium {
                        macroRow("Sodium", value: sodium, unit: "mg", color: .blue)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per 100 g: \(Int(food.per100g.calories.rounded())) kcal • \(Int(food.per100g.protein.rounded()))P • \(Int(food.per100g.carbs.rounded()))C • \(Int(food.per100g.fat.rounded()))F")
                        Text("Source: \(food.source.label)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(food.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        recents.toggleFavorite(food)
                    } label: {
                        Image(systemName: recents.isFavorite(food) ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                    .accessibilityLabel(recents.isFavorite(food) ? "Remove from favorites" : "Add to favorites")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let meal = food.meal(grams: totalGrams, category: category, portionName: portionName)
                        onConfirm(meal, totalGrams)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isZeroPoint: Bool {
        plan.zeroPointFoodsEnabled && ZeroPointFoods.qualifies(food)
    }

    private var pointsRow: some View {
        HStack {
            Text("Bites Points")
                .fontWeight(.semibold)
            if isZeroPoint {
                Text("ZeroPoint")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }
            Spacer()
            Text("\(BitesPoints.points(for: food, grams: totalGrams))")
                .font(.title3.bold())
                .foregroundStyle(isZeroPoint ? .green : .orange)
        }
    }

    private func macroRow(_ label: String, value: Double, unit: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value.rounded()))")
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    /// Float equality would miss 0.33 typed against 0.33 stored.
    private func isSelected(_ value: Double) -> Bool {
        abs(amountValue - value) < 0.005
    }

    /// Keeps the actual quantity fixed when the unit changes: 100 g becomes
    /// 3.53 oz rather than a nonsensical 100 oz.
    private func convertAmount(from previous: ServingUnit, to next: ServingUnit) {
        guard previous != next else { return }
        let gramsPer = { (unit: ServingUnit) -> Double in
            unit == .serving ? (self.food.servingGrams ?? 100) : unit.gramsPerUnit
        }
        let grams = amountValue * gramsPer(previous)
        let divisor = gramsPer(next)
        guard grams > 0, divisor > 0 else { return }
        amount = Self.trimmed(grams / divisor)
    }

    /// "1.5" not "1.500000", "100" not "100.0".
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

#Preview {
    ServingPickerView(
        food: FoodItem(
            id: "usda:1",
            name: "Chicken, broiler, breast, skinless, boneless, meat only, raw",
            brand: nil,
            source: .usdaFoundation,
            per100g: Nutrition(calories: 120, protein: 22.5, carbs: 0, fat: 2.6, fiber: 0, sugar: 0, sodium: 45),
            servingGrams: 172,
            servingLabel: "1 breast",
            barcode: nil,
            fdcId: 1
        ),
        category: .dinner
    ) { _, _ in }
}
