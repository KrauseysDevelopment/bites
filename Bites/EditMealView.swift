// EditMealView.swift
import SwiftUI

/// Edits a meal already in the diary. Until now the only thing you could do to
/// a logged meal was delete it and re-add it.
struct EditMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DiaryStore

    private let original: Meal

    @State private var name: String
    @State private var category: MealCategory
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var loggedDate: Date
    @State private var showingDeleteConfirm = false

    init(meal: Meal, day: Date?) {
        original = meal
        _name     = State(initialValue: meal.name)
        _category = State(initialValue: meal.category)
        _calories = State(initialValue: String(meal.calories))
        _protein  = State(initialValue: String(meal.protein))
        _carbs    = State(initialValue: String(meal.carbs))
        _fat      = State(initialValue: String(meal.fat))

        // Keep the original clock time but let the day be changed.
        let baseDay = day ?? Calendar.current.startOfDay(for: meal.loggedAt)
        let time = Calendar.current.dateComponents([.hour, .minute], from: meal.loggedAt)
        _loggedDate = State(
            initialValue: Calendar.current.date(
                bySettingHour: time.hour ?? 12,
                minute: time.minute ?? 0,
                second: 0,
                of: baseDay
            ) ?? baseDay
        )
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Int(calories) != nil
    }

    /// Derived so you can sanity-check the macros against the calorie figure.
    private var macroCalories: Int {
        (Int(protein) ?? 0) * 4 + (Int(carbs) ?? 0) * 4 + (Int(fat) ?? 0) * 9
    }

    private var macroMismatch: Bool {
        guard let stated = Int(calories), stated > 0, macroCalories > 0 else { return false }
        return abs(stated - macroCalories) > max(30, stated / 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Category") {
                    Picker("Meal", selection: $category) {
                        ForEach(MealCategory.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    macroField("Calories", text: $calories, unit: "kcal", color: .orange)
                    macroField("Protein",  text: $protein,  unit: "g",    color: .green)
                    macroField("Carbs",    text: $carbs,    unit: "g",    color: .purple)
                    macroField("Fat",      text: $fat,      unit: "g",    color: .amber)
                } header: {
                    Text("Macros")
                } footer: {
                    if macroMismatch {
                        Label(
                            "Macros work out to about \(macroCalories) kcal, which does not match the calories above.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Section {
                    DatePicker("Logged", selection: $loggedDate)
                } footer: {
                    Text("Changing the date moves this meal to that day in your diary.")
                        .font(.caption)
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Meal", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this meal?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteMeal(id: original.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private func save() {
        var updated = original
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.category = category
        updated.calories = Int(calories) ?? 0
        updated.protein = Int(protein) ?? 0
        updated.carbs = Int(carbs) ?? 0
        updated.fat = Int(fat) ?? 0
        updated.loggedAt = loggedDate

        store.updateMeal(updated, movingTo: loggedDate)
        dismiss()
    }

    private func macroField(_ label: String, text: Binding<String>, unit: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 84)
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
    EditMealView(
        meal: Meal(name: "Chicken and rice", calories: 620, protein: 48, carbs: 70, fat: 12, category: .dinner),
        day: Date()
    )
    .environmentObject(DiaryStore.shared)
}
