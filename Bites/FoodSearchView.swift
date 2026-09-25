// FoodSearchView.swift
import SwiftUI

struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = FoodSearchService.shared
    @StateObject private var recents = RecentFoodsStore.shared

    @State private var searchText = ""
    @State private var selectedFood: FoodItem?
    @State private var showingScanner = false
    @State private var pendingBarcode: String?

    /// Category applied to the meal handed back to the caller.
    var category: MealCategory = .snack
    /// Building a multi-item saved meal keeps the search open between picks.
    var dismissAfterSelection: Bool = true
    let onFoodSelected: (Meal) -> Void

    private var isIdle: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count < 2
    }

    var body: some View {
        NavigationStack {
            List {
                if service.isLookingUpBarcode {
                    statusRow { ProgressView(); Text("Looking up barcode…") }
                }
                if let message = service.barcodeError {
                    noticeRow(message, icon: "barcode.viewfinder", tint: .orange)
                }

                if isIdle {
                    idleContent
                } else {
                    resultsContent
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search foods, brands, ingredients")
            .autocorrectionDisabled()
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Scan barcode")
                }
            }
            .onChange(of: searchText) { _, newValue in
                service.search(newValue)
            }
            .sheet(isPresented: $showingScanner, onDismiss: handleScannedBarcode) {
                BarcodeScannerView { code in
                    pendingBarcode = code
                }
            }
            .sheet(item: $selectedFood) { food in
                ServingPickerView(
                    food: food,
                    category: category,
                    initialGrams: recents.entries.first(where: { $0.food.id == food.id })?.lastGrams
                ) { meal, grams in
                    recents.record(food, grams: grams)
                    onFoodSelected(meal)
                    if dismissAfterSelection { dismiss() }
                }
            }
        }
    }

    /// Deferred to the scanner sheet's dismissal, otherwise the serving-picker
    /// sheet can be swallowed by the still-running dismiss transition.
    private func handleScannedBarcode() {
        guard let code = pendingBarcode else { return }
        pendingBarcode = nil
        Task {
            if let item = await service.lookup(barcode: code) {
                selectedFood = item
            }
        }
    }

    // MARK: - Idle (recents / favourites)

    @ViewBuilder
    private var idleContent: some View {
        if service.needsAPIKey {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("USDA key needed", systemImage: "key.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                    Text("Food search uses the USDA FoodData Central database. Add your free API key in Settings. Barcode scanning still works without it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }

        if !recents.favorites.isEmpty {
            Section("Favorites") {
                ForEach(recents.favorites) { entry in
                    entryRow(entry)
                }
            }
        }

        if !recents.recents.isEmpty {
            Section {
                ForEach(recents.recents) { entry in
                    entryRow(entry)
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { recents.clearRecents() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }

        if !recents.hasAnything && !service.needsAPIKey {
            Section {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange.opacity(0.65))
            }
            Text("Search or scan")
                .font(.subheadline.bold())
            Text("Whole ingredients come from USDA lab data.\nScan a package to pull it up instantly.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .listRowBackground(Color.clear)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsContent: some View {
        if service.isSearching && !service.hasResults {
            statusRow { ProgressView(); Text("Searching…") }
        }

        if let message = service.errorMessage, !service.isSearching {
            noticeRow(message, icon: "exclamationmark.circle", tint: .secondary)
        }

        if !service.wholeFoods.isEmpty {
            Section {
                ForEach(service.wholeFoods) { food in
                    foodRow(food)
                }
            } header: {
                sectionHeader("Whole Foods", subtitle: "USDA reference data")
            }
        }

        if !service.brandedFoods.isEmpty {
            Section {
                ForEach(service.brandedFoods) { food in
                    foodRow(food)
                }
            } header: {
                sectionHeader("Branded", subtitle: "Packaged products")
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(nil)
        }
    }

    // MARK: - Rows

    private func foodRow(_ food: FoodItem) -> some View {
        Button {
            selectedFood = food
        } label: {
            FoodRowContent(food: food, isFavorite: recents.isFavorite(food))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                recents.toggleFavorite(food)
            } label: {
                Label("Favorite", systemImage: recents.isFavorite(food) ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
    }

    private func entryRow(_ entry: RecentFoodsStore.Entry) -> some View {
        Button {
            selectedFood = entry.food
        } label: {
            FoodRowContent(
                food: entry.food,
                isFavorite: entry.isFavorite,
                trailingNote: entry.lastGrams.map { "\(Int($0.rounded())) g last time" }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                recents.toggleFavorite(entry.food)
            } label: {
                Label("Favorite", systemImage: entry.isFavorite ? "star.slash" : "star.fill")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                recents.remove(entry.food)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Small pieces

    @ViewBuilder
    private func statusRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(Color.clear)
    }

    private func noticeRow(_ message: String, icon: String, tint: Color) -> some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(tint)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Row content

struct FoodRowContent: View {
    let food: FoodItem
    var isFavorite: Bool = false
    var trailingNote: String?

    private var per100: Nutrition { food.per100g }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(food.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
                Spacer(minLength: 8)
                Text("\(Int(per100.calories.rounded()))")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            if let brand = food.brand {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                MacroPill(value: Int(per100.protein.rounded()), label: "P", color: .green)
                MacroPill(value: Int(per100.carbs.rounded()), label: "C", color: .purple)
                MacroPill(value: Int(per100.fat.rounded()), label: "F", color: .amber)
                Spacer()
            }

            HStack(spacing: 6) {
                Text(food.source.label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(food.source.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(food.source.color.opacity(0.12), in: Capsule())

                Text("per 100 g")
                if let serving = food.servingDescription {
                    Text("•")
                    Text(serving).lineLimit(1)
                }
                if let trailingNote {
                    Text("•")
                    Text(trailingNote)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
