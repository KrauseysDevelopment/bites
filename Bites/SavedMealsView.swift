// SavedMealsView.swift
import SwiftUI

struct SavedMealsView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var showingCreateNew = false
    @State private var editingMeal: SavedMeal?

    var body: some View {
        NavigationStack {
            Group {
                if store.savedMeals.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.savedMeals) { savedMeal in
                            SavedMealCard(savedMeal: savedMeal) {
                                let combined = Meal(
                                    name: savedMeal.name,
                                    calories: savedMeal.totalCalories,
                                    protein:  savedMeal.totalProtein,
                                    carbs:    savedMeal.totalCarbs,
                                    fat:      savedMeal.totalFat,
                                    category: MealCategory.suggested()
                                )
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                store.addMeal(combined)
                            }
                            .onTapGesture { editingMeal = savedMeal }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if let idx = store.savedMeals.firstIndex(where: { $0.id == savedMeal.id }) {
                                        store.savedMeals.remove(at: idx)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Saved Meals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateNew = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("New")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingCreateNew) {
                CreateSavedMealView()
            }
            .sheet(item: $editingMeal) { meal in
                EditSavedMealView(savedMeal: meal)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "tray")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange.opacity(0.6))
            }
            Text("No Saved Meals")
                .font(.title3.bold())
            Text("Create meal templates to quickly\nlog your favourite combos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Saved Meal Card
struct SavedMealCard: View {
    let savedMeal: SavedMeal
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(savedMeal.name)
                        .font(.title3.bold())
                    Text("\(savedMeal.items.count) item\(savedMeal.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(savedMeal.totalCalories)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                + Text(" kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Macro pills row
            HStack(spacing: 10) {
                SavedMealMacroPill(
                    value: savedMeal.totalProtein,
                    label: "Protein", color: .green
                )
                SavedMealMacroPill(
                    value: savedMeal.totalCarbs,
                    label: "Carbs", color: .purple
                )
                SavedMealMacroPill(
                    value: savedMeal.totalFat,
                    label: "Fat", color: .amber
                )
                Spacer()
            }

            // Add button
            Button(action: onAdd) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add to Diary")
                        .fontWeight(.semibold)
                }
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color(red: 1, green: 0.38, blue: 0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Saved Meal Macro Pill
struct SavedMealMacroPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)g")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Edit Saved Meal
struct EditSavedMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: DiaryStore

    @State var savedMeal: SavedMeal
    @State private var showingFoodSearch = false

    init(savedMeal: SavedMeal) {
        _savedMeal = State(initialValue: savedMeal)
    }

    private var totalCalories: Int { savedMeal.items.reduce(0) { $0 + $1.meal.calories } }
    private var totalProtein: Int  { savedMeal.items.reduce(0) { $0 + $1.meal.protein } }
    private var totalCarbs: Int    { savedMeal.items.reduce(0) { $0 + $1.meal.carbs } }
    private var totalFat: Int      { savedMeal.items.reduce(0) { $0 + $1.meal.fat } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Name") {
                    TextField("Name", text: $savedMeal.name)
                }

                Section("Foods") {
                    ForEach(savedMeal.items, id: \.meal.id) { item in
                        HStack {
                            Text(item.meal.name)
                            Spacer()
                            Text("\(item.meal.calories) kcal")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .onDelete { savedMeal.items.remove(atOffsets: $0) }

                    Button {
                        showingFoodSearch = true
                    } label: {
                        Label("Add Food", systemImage: "plus")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Total Macros") {
                    macroRow("Calories", value: "\(totalCalories) kcal", color: .orange)
                    macroRow("Protein",  value: "\(totalProtein)g",      color: .green)
                    macroRow("Carbs",    value: "\(totalCarbs)g",        color: .purple)
                    macroRow("Fat",      value: "\(totalFat)g",          color: .amber)
                }
            }
            .navigationTitle("Edit Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let index = store.savedMeals.firstIndex(where: { $0.id == savedMeal.id }) {
                            store.savedMeals[index] = savedMeal
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingFoodSearch) {
                FoodSearchView(dismissAfterSelection: false) { meal in
                    savedMeal.items.append(SavedMealItem(meal: meal))
                }
            }
        }
    }

    @ViewBuilder
    private func macroRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    SavedMealsView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
