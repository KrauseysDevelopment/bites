// AddMealView.swift
import SwiftUI

struct AddMealView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DiaryStore

    @StateObject private var search = FoodSearchService.shared
    @StateObject private var recents = RecentFoodsStore.shared

    @State private var foodName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var selectedCategory: MealCategory = MealCategory.suggested()

    @State private var showingDatabaseSearch = false
    @State private var showingScanner = false
    @State private var pendingBarcode: String?
    @State private var scannedFood: FoodItem?

    private var canSave: Bool {
        Int(calories) != nil || !foodName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Search and scan are the two ways most meals get logged, so
                // they belong at the top of this screen rather than buried
                // inside the search sheet's toolbar.
                Section {
                    HStack(spacing: 12) {
                        entryButton(
                            title: "Search Foods",
                            subtitle: "USDA database",
                            icon: "magnifyingglass",
                            tint: .orange
                        ) {
                            showingDatabaseSearch = true
                        }

                        entryButton(
                            title: "Scan Barcode",
                            subtitle: "Packaged food",
                            icon: "barcode.viewfinder",
                            tint: .blue
                        ) {
                            showingScanner = true
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)

                    if search.isLookingUpBarcode {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking up barcode…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                    }

                    if let message = search.barcodeError {
                        Label(message, systemImage: "barcode.viewfinder")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Food / Meal") {
                    TextField("e.g. Chicken & rice", text: $foodName, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Category") {
                    Picker("Meal", selection: $selectedCategory) {
                        ForEach(MealCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Macros") {
                    macroRow("Calories", binding: $calories, unit: "kcal", color: .orange)
                    macroRow("Protein",  binding: $protein,  unit: "g",    color: .green)
                    macroRow("Carbs",    binding: $carbs,    unit: "g",    color: .purple)
                    macroRow("Fat",      binding: $fat,      unit: "g",    color: .amber)
                }
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingDatabaseSearch) {
                FoodSearchView(category: selectedCategory) { scaledMeal in
                    apply(scaledMeal)
                }
            }
            .sheet(isPresented: $showingScanner, onDismiss: handleScannedBarcode) {
                BarcodeScannerView { code in
                    pendingBarcode = code
                }
            }
            .sheet(item: $scannedFood) { food in
                ServingPickerView(
                    food: food,
                    category: selectedCategory,
                    initialGrams: recents.entries.first(where: { $0.food.id == food.id })?.lastGrams
                ) { meal, grams in
                    recents.record(food, grams: grams)
                    apply(meal)
                }
            }
            .onAppear { search.barcodeError = nil }
        }
    }

    // MARK: - Actions

    /// Runs after the scanner sheet has finished dismissing. Presenting the
    /// serving picker from inside the scan callback raced the dismissal and
    /// the second sheet could be dropped without a trace.
    private func handleScannedBarcode() {
        guard let code = pendingBarcode else { return }
        pendingBarcode = nil
        Task {
            if let item = await search.lookup(barcode: code) {
                scannedFood = item
            }
        }
    }

    private func apply(_ meal: Meal) {
        foodName = meal.name
        calories = String(meal.calories)
        protein  = String(meal.protein)
        carbs    = String(meal.carbs)
        fat      = String(meal.fat)
        selectedCategory = meal.category
    }

    private func save() {
        let trimmed = foodName.trimmingCharacters(in: .whitespaces)
        let meal = Meal(
            name: trimmed.isEmpty ? selectedCategory.rawValue : trimmed,
            calories: Int(calories) ?? 0,
            protein: Int(protein) ?? 0,
            carbs: Int(carbs) ?? 0,
            fat: Int(fat) ?? 0,
            category: selectedCategory
        )
        store.addMeal(meal)
        dismiss()
    }

    // MARK: - Pieces

    private func entryButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func macroRow(_ label: String, binding: Binding<String>, unit: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .foregroundStyle(color)
                .fontWeight(.semibold)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
    }
}

#Preview {
    AddMealView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
