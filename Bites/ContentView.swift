// ContentView.swift
import SwiftUI

// Shared amber color for fat macros — available across all files in this module
extension Color {
    static let amber = Color(red: 0.95, green: 0.75, blue: 0.1)
}

struct ContentView: View {
    @EnvironmentObject var store: DiaryStore
    @State private var showingAddMeal = false
    @State private var ringAnimated = false

    private var calorieProgress: Double {
        guard store.calorieGoal > 0 else { return 0 }
        return min(Double(store.today.totalCalories) / Double(store.calorieGoal), 1.0)
    }

    private var remaining: Int {
        store.calorieGoal - store.today.totalCalories
    }

    private var ringColor: Color {
        calorieProgress >= 1.0 ? .red : .orange
    }

    private var ringGradientColors: [Color] {
        calorieProgress >= 1.0
            ? [Color.red.opacity(0.6), Color.red]
            : [Color.orange.opacity(0.55), Color.orange]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    calorieRingCard
                    macroRow
                    waterCard
                    weeklyCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
            .navigationTitle("Today")
            .overlay(alignment: .bottomTrailing) {
                fabButton
            }
            .sheet(isPresented: $showingAddMeal) {
                AddMealView()
            }
        }
    }

    // MARK: - Calorie Ring Card
    private var calorieRingCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 6)

            VStack(spacing: 0) {
                // Date + progress pill
                HStack {
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(remaining >= 0 ? "\(Int(calorieProgress * 100))%" : "Over!")
                        .font(.caption.bold())
                        .foregroundStyle(ringColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(ringColor.opacity(0.13))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)

                // Ring
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 18)

                    Circle()
                        .trim(from: 0, to: ringAnimated ? calorieProgress : 0)
                        .stroke(
                            AngularGradient(
                                colors: ringGradientColors,
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.76), value: ringAnimated)

                    VStack(spacing: 3) {
                        Text("\(store.today.totalCalories)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4), value: store.today.totalCalories)

                        Text("kcal eaten")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 36, height: 1)
                            .padding(.vertical, 8)

                        Group {
                            if remaining >= 0 {
                                Text("\(remaining) remaining")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(abs(remaining)) over goal")
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.caption.bold())
                        .contentTransition(.numericText())
                    }
                }
                .frame(width: 210, height: 210)
                .padding(.vertical, 14)
                .onAppear {
                    withAnimation { ringAnimated = true }
                }
                .onChange(of: store.today.totalCalories) { _, _ in
                    ringAnimated = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation { ringAnimated = true }
                    }
                }

                Text("Goal  \(store.calorieGoal) kcal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 22)
            }
        }
    }

    // MARK: - Macro Row
    private var macroRow: some View {
        HStack(spacing: 12) {
            MacroCard(value: store.today.totalProtein, goal: store.proteinGoal,
                      label: "Protein", color: .green)
            MacroCard(value: store.today.totalCarbs, goal: store.carbsGoal,
                      label: "Carbs", color: .purple)
            MacroCard(value: store.today.totalFat, goal: store.fatGoal,
                      label: "Fat", color: .amber)
        }
    }

    // MARK: - Water Card
    private var waterCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
            .overlay {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Water")
                            .font(.headline)
                        Text("\(store.today.waterGlasses) of \(store.waterGoal) glasses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        ForEach(0..<max(store.waterGoal, 1), id: \.self) { i in
                            Circle()
                                .fill(store.today.waterGlasses > i
                                      ? Color.blue
                                      : Color.secondary.opacity(0.2))
                                .frame(width: 13, height: 13)
                                .scaleEffect(store.today.waterGlasses > i ? 1.1 : 0.9)
                                .animation(.spring(response: 0.25, dampingFraction: 0.6),
                                           value: store.today.waterGlasses)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    let newCount = store.today.waterGlasses > i ? i : i + 1
                                    store.setWaterGlasses(to: newCount)
                                }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 72)
    }

    // MARK: - Weekly Card
    private var weeklyCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
            .overlay {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("This Week")
                            .font(.headline)
                        Spacer()
                        Text("kcal / day")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    WeeklySparkline(days: store.days, goal: store.calorieGoal)
                        .frame(height: 64)
                }
                .padding(18)
            }
            .frame(height: 116)
    }

    // MARK: - FAB
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
}

// MARK: - Macro Card
struct MacroCard: View {
    let value: Int
    let goal: Int
    let label: String
    let color: Color

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(value) / Double(goal), 1.0)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
            .overlay {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                        Text(label)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                    }

                    Spacer()

                    Text("\(value)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: value)

                    Text("/ \(goal)g")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(color.opacity(0.12))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [color.opacity(0.65), color],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geo.size.width * progress, 0), height: 5)
                                .animation(.spring(response: 0.7, dampingFraction: 0.8), value: progress)
                        }
                    }
                    .frame(height: 5)
                }
                // Same reason as MetricCard: .overlay centres a stack that is
                // only as wide as its content, and only the GeometryReader was
                // stretching this to full width.
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 118)
    }
}

// MARK: - Weekly Sparkline
struct WeeklySparkline: View {
    let days: [DayEntry]
    let goal: Int

    private var data: [(label: String, calories: Int)] {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return (0..<7).map { i in
            let date = cal.date(byAdding: .day, value: -(6 - i), to: Date())!
            let start = cal.startOfDay(for: date)
            let cals = days.first(where: { $0.date == start })?.totalCalories ?? 0
            return (label: formatter.string(from: date), calories: cals)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let maxCal = max(data.map(\.calories).max() ?? 1, goal)
            let barW = (geo.size.width - CGFloat(6) * 8) / 7

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let item = data[i]
                    let isToday = i == 6
                    let metGoal = item.calories >= goal && item.calories > 0
                    let barH = item.calories > 0
                        ? max(CGFloat(item.calories) / CGFloat(maxCal) * (geo.size.height - 18), 4)
                        : 3

                    VStack(spacing: 5) {
                        if isToday {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.65), .orange],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                                .frame(width: barW, height: barH)
                        } else if metGoal {
                            Capsule()
                                .fill(Color.green.opacity(0.65))
                                .frame(width: barW, height: barH)
                        } else {
                            Capsule()
                                .fill(Color.secondary.opacity(0.22))
                                .frame(width: barW, height: barH)
                        }

                        Text(item.label)
                            .font(.system(size: 9, weight: isToday ? .bold : .medium))
                            .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
