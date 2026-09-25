// CreateSavedMealView.swift
import SwiftUI

struct CreateSavedMealView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var store: DiaryStore
    
    @State private var mealName = ""
    @State private var selectedMeals: [Meal] = []
    @State private var showingDatabaseSearch = false
    
    var totalCalories: Int { selectedMeals.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int  { selectedMeals.reduce(0) { $0 + $1.protein } }
    var totalCarbs: Int    { selectedMeals.reduce(0) { $0 + $1.carbs } }
    var totalFat: Int      { selectedMeals.reduce(0) { $0 + $1.fat } }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal Name") {
                    TextField("e.g. Chicken + Rice Bowl", text: $mealName)
                }
                
                Section {
                    Button {
                        showingDatabaseSearch = true
                    } label: {
                        Label("Search Food Database", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.orange)
                }
                
                if !selectedMeals.isEmpty {
                    Section("Foods in this meal") {
                        ForEach(selectedMeals) { meal in
                            HStack {
                                Text(meal.name)
                                Spacer()
                                Text("\(meal.calories) kcal")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .onDelete { selectedMeals.remove(atOffsets: $0) }
                    }
                    
                    Section("Total Macros") {
                        macroRow("Calories", value: totalCalories, unit: "kcal", color: .orange)
                        macroRow("Protein",  value: totalProtein,  unit: "g", color: .green)
                        macroRow("Carbs",    value: totalCarbs,    unit: "g", color: .purple)
                        macroRow("Fat",      value: totalFat,      unit: "g", color: .yellow)
                    }
                }
            }
            .navigationTitle("Create Saved Meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = SavedMeal(
                            name: mealName.isEmpty ? "My Meal" : mealName,
                            items: selectedMeals.map { SavedMealItem(meal: $0) }
                        )
                        store.savedMeals.append(saved)
                        dismiss()
                    }
                    .disabled(mealName.isEmpty || selectedMeals.isEmpty)
                }
            }
            .sheet(isPresented: $showingDatabaseSearch) {
                FoodSearchView(dismissAfterSelection: false) { meal in
                    selectedMeals.append(meal)
                }
            }
        }
    }
    
    private func macroRow(_ label: String, value: Int, unit: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CreateSavedMealView()
        .environmentObject(DiaryStore.shared)
}
