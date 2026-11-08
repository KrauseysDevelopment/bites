// FoodDiaryView.swift
import SwiftUI

struct FoodDiaryView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var showingAddMeal = false
    @State private var editingMeal: Meal?
    @ObservedObject private var plan = PlanStore.shared

    private var groupedDays: [(date: Date, meals: [Meal])] {
        let sortedDays = store.days.sorted { $0.date > $1.date }
        var groups: [(date: Date, meals: [Meal])] = []
        for day in sortedDays {
            let start = day.date.startOfDay()
            if let idx = groups.firstIndex(where: { $0.date == start }) {
                groups[idx].meals.append(contentsOf: day.meals)
            } else {
                groups.append((date: start, meals: day.meals))
            }
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedDays, id: \.date) { group in
                    Section {
                        if group.meals.isEmpty {
                            Text("No meals logged")
                                .foregroundStyle(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(group.meals) { meal in
                                MealCard(meal: meal)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .contentShape(RoundedRectangle(cornerRadius: 16))
                                    .onTapGesture { editingMeal = meal }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteMeal(meal)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            editingMeal = meal
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.orange)
                                    }
                                    .contextMenu {
                                        Button { editingMeal = meal } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) { deleteMeal(meal) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayHeaderTitle(for: group.date))
                                .font(.title3.bold())
                                .foregroundStyle(.primary)
                                .textCase(nil)
                            Spacer()
                            let totalCal = group.meals.reduce(0) { $0 + $1.calories }
                            let totalPts = group.meals.reduce(0) { $0 + $1.points }
                            if totalCal > 0 {
                                Text(plan.trackingMode == .points ? "\(totalPts) pts" : "\(totalCal) kcal")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 4)
                                    .background(.orange.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Diary")
            .overlay(alignment: .bottomTrailing) {
                fabButton
            }
            .sheet(isPresented: $showingAddMeal) {
                AddMealView()
            }
            .sheet(item: $editingMeal) { meal in
                EditMealView(meal: meal, day: store.date(ofMeal: meal.id))
            }
        }
    }

    private var fabButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingAddMeal = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color(red: 1, green: 0.38, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: .orange.opacity(0.5), radius: 16, x: 0, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.trailing, 22)
        .padding(.bottom, 16)
    }

    private func deleteMeal(_ meal: Meal) {
        withAnimation(.spring(response: 0.4)) {
            store.deleteMeal(id: meal.id)
        }
    }

    private func dayHeaderTitle(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Meal Card
struct MealCard: View {
    let meal: Meal
    @ObservedObject private var plan = PlanStore.shared

    var body: some View {
        HStack(spacing: 0) {
            // Category color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(meal.category.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(meal.name)
                            .font(.headline)
                            .lineLimit(1)
                        Label(meal.category.rawValue, systemImage: meal.category.icon)
                            .font(.caption)
                            .foregroundStyle(meal.category.color)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        if plan.trackingMode == .points {
                            Text("\(meal.points)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(meal.points == 0 ? .green : .orange)
                            Text(meal.points == 0 && meal.isZeroPoint ? "ZeroPoint" : "pts · \(meal.calories) kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(meal.calories)")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("kcal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 7) {
                    MacroPill(value: meal.protein, label: "P", color: .green)
                    MacroPill(value: meal.carbs,   label: "C", color: .purple)
                    MacroPill(value: meal.fat,     label: "F", color: .amber)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Macro Pill
struct MacroPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("\(value)g")
                .fontWeight(.semibold)
            Text(label)
                .foregroundStyle(color)
                .fontWeight(.bold)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

#Preview {
    FoodDiaryView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
