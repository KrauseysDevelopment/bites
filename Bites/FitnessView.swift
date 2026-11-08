// FitnessView.swift
import SwiftUI

struct FitnessView: View {
    @StateObject private var health = HealthManager.shared
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var workouts: WorkoutStore
    @StateObject private var reminder = WeighInReminder.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingLogWorkout = false
    @State private var showingWeightEntry = false
    @State private var editingWorkout: Workout?
    @State private var weightInput = ""
    @State private var logExpanded = false

    private var distanceValue: Double {
        health.distanceInMeters / store.distanceUnit.toMeters
    }

    private var todayActivity: DayActivity {
        workouts.activity(on: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if reminder.isDue(lastWeighIn: store.lastWeighInDate) {
                        weighInPrompt
                    }

                    StreakCard(
                        streak: workouts.currentStreak,
                        longest: workouts.longestStreak,
                        todayMet: workouts.todayMetGoal,
                        week: workouts.recentActivity(days: 7),
                        minutesGoal: workouts.exerciseMinutesGoal,
                        calorieGoal: workouts.activeCalorieGoal
                    )

                    NavigationLink { AchievementsView() } label: { AchievementsSummaryCard() }
                        .buttonStyle(.plain)

                    TodayGoalCard(
                        activity: todayActivity,
                        minutesGoal: workouts.exerciseMinutesGoal,
                        calorieGoal: workouts.activeCalorieGoal,
                        appleExerciseMinutes: Int(health.exerciseMinutes)
                    )

                    weeklySummaryRow

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        MetricCard(
                            icon: "figure.walk", iconColor: .blue,
                            title: "Steps", value: health.steps.formatted(), unit: "steps",
                            progress: min(Double(health.steps) / 10_000, 1.0), progressColor: .blue
                        )
                        MetricCard(
                            icon: "flame.fill", iconColor: .orange,
                            title: "Active Cal", value: "\(Int(health.activeCalories))", unit: "kcal",
                            progress: workouts.activeCalorieGoal > 0
                                ? min(health.activeCalories / Double(workouts.activeCalorieGoal), 1.0) : nil,
                            progressColor: .orange
                        )
                        MetricCard(
                            icon: "timer", iconColor: .green,
                            title: "Apple Exercise", value: "\(Int(health.exerciseMinutes))", unit: "min",
                            progress: workouts.exerciseMinutesGoal > 0
                                ? min(health.exerciseMinutes / Double(workouts.exerciseMinutesGoal), 1.0) : nil,
                            progressColor: .green
                        )
                        MetricCard(
                            icon: "location.fill", iconColor: .purple,
                            title: "Distance", value: String(format: "%.1f", distanceValue),
                            unit: store.distanceUnit.rawValue, progress: nil, progressColor: .purple
                        )
                    }

                    NavigationLink { WeightView() } label: { weightCard }
                        .buttonStyle(.plain)

                    workoutLogSection

                    if let message = health.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
            .navigationTitle("Fitness")
            .overlay(alignment: .bottomTrailing) { logWorkoutFAB }
            .task { await health.refresh(into: workouts, diaryStore: store) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reminder.refreshDueState() }
            }
            .refreshable { await health.refresh(into: workouts, diaryStore: store) }
            .sheet(isPresented: $showingLogWorkout) {
                LogWorkoutView()
            }
            .sheet(item: $editingWorkout) { workout in
                LogWorkoutView(editing: workout)
            }
            .sheet(isPresented: $showingWeightEntry) { weightEntrySheet }
        }
    }

    // MARK: - Weekly summary

    private var weeklySummaryRow: some View {
        HStack(spacing: 12) {
            SummaryTile(
                value: "\(workouts.thisWeekWorkouts)",
                label: "Workouts",
                sublabel: "last 7 days",
                color: .orange
            )
            SummaryTile(
                value: "\(workouts.thisWeekMinutes)",
                label: "Minutes",
                sublabel: "last 7 days",
                color: .green
            )
            SummaryTile(
                value: "\(workouts.recentActivity(days: 7).filter { $0.metGoal(minutesGoal: workouts.exerciseMinutesGoal, calorieGoal: workouts.activeCalorieGoal) }.count)/7",
                label: "Goal days",
                sublabel: "last 7 days",
                color: .blue
            )
        }
    }

    // MARK: - Workout log
    //
    // Collapsed by default. The full history lives on its own screen so this
    // page stays a fixed height no matter how many workouts have piled up.

    private static let collapsedCount = 3

    private var recentWorkouts: [Workout] {
        Array(workouts.workouts.prefix(logExpanded ? 10 : Self.collapsedCount))
    }

    private var workoutLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Workouts")
                    .font(.headline)
                Spacer()
                if workouts.workouts.count > Self.collapsedCount {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            logExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(logExpanded ? "Less" : "More")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(logExpanded ? 180 : 0))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)

            if workouts.workouts.isEmpty {
                emptyWorkoutState
            } else {
                ForEach(recentWorkouts) { workout in
                    WorkoutRow(workout: workout, showsDate: true)
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                        .onTapGesture { editingWorkout = workout }
                        .contextMenu {
                            Button { editingWorkout = workout } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                withAnimation(.spring(response: 0.35)) {
                                    workouts.delete(id: workout.id)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }

                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    HStack {
                        Text("View all \(workouts.workouts.count) workouts")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyWorkoutState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.1)).frame(width: 66, height: 66)
                Image(systemName: "figure.run")
                    .font(.system(size: 28))
                    .foregroundStyle(.green.opacity(0.65))
            }
            Text("No workouts yet")
                .font(.subheadline.bold())
            Text("Tap + to log one, or pull down to\nimport from Apple Health.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Weight

    private var sparklineValues: [Double] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date()))
        let recent = store.weightEntries
            .filter { cutoff == nil || $0.date >= cutoff! }
            .sorted { $0.date < $1.date }
            .map(\.pounds)
        return recent.count >= 2 ? recent : []
    }

    private var weighInPrompt: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.14)).frame(width: 44, height: 44)
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly weigh-in")
                    .font(.subheadline.bold())
                Text("Log your weight to keep the trend honest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                weightInput = store.latestWeight > 0 ? String(format: "%.1f", store.latestWeight) : ""
                showingWeightEntry = true
            } label: {
                Text("Log")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.indigo, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.indigo.opacity(0.2), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation { reminder.dismissCardForToday() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(7)
            }
            .buttonStyle(.plain)
        }
    }

    private var weightCard: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.07), radius: 16, x: 0, y: 5)
            .overlay {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().fill(Color.indigo.opacity(0.12)).frame(width: 56, height: 56)
                        Image(systemName: "scalemass.fill")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Weight")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if store.todaysWeight > 0 {
                            Text("\(store.todaysWeight, specifier: "%.1f") lb")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        } else if store.latestWeight > 0 {
                            Text("\(store.latestWeight, specifier: "%.1f") lb")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not logged")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            if store.weeklyAverageWeight > 0 {
                                Text("7-day avg \(store.weeklyAverageWeight, specifier: "%.1f")")
                            }
                            if let change = store.monthlyWeightChange {
                                Label(
                                    "\(abs(change), specifier: "%.1f") lb",
                                    systemImage: change < 0 ? "arrow.down" : "arrow.up"
                                )
                                .foregroundStyle(change < 0 ? .green : .orange)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    // A glance at the shape of the trend; the full chart with
                    // range filters lives on its own screen so this page keeps
                    // its fixed height.
                    WeightSparkline(values: sparklineValues)
                        .frame(width: 66, height: 34)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .frame(height: 104)
    }

    private var weightEntrySheet: some View {
        NavigationStack {
            Form {
                Section("Enter Your Weight") {
                    HStack {
                        TextField("e.g. 185.5", text: $weightInput)
                            .keyboardType(.decimalPad)
                        Text("lb").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log Weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingWeightEntry = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let weight = Double(weightInput), weight > 0 {
                            store.logWeight(weight)
                        }
                        weightInput = ""
                        showingWeightEntry = false
                    }
                    .disabled(Double(weightInput) == nil)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    // MARK: - FAB

    private var logWorkoutFAB: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingLogWorkout = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green, Color(red: 0.0, green: 0.62, blue: 0.38)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: .green.opacity(0.45), radius: 16, x: 0, y: 6)
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 22)
        .padding(.bottom, 16)
    }
}

// MARK: - Streak Card

struct StreakCard: View {
    let streak: Int
    let longest: Int
    let todayMet: Bool
    let week: [DayActivity]
    let minutesGoal: Int
    let calorieGoal: Int

    private var flameColors: [Color] {
        streak == 0
            ? [Color.secondary.opacity(0.45), Color.secondary.opacity(0.25)]
            : [Color.orange, Color(red: 1, green: 0.32, blue: 0.12)]
    }

    private var subtitle: String {
        if streak == 0 { return "Hit your goal today to start one" }
        if todayMet { return "Today is in the bag" }
        return "Keep it alive: today is not counted yet"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 26)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
            .overlay {
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [flameColors[0].opacity(0.22), .clear],
                                        center: .center, startRadius: 2, endRadius: 40
                                    )
                                )
                                .frame(width: 72, height: 72)
                            Image(systemName: streak == 0 ? "flame" : "flame.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(
                                    LinearGradient(colors: flameColors, startPoint: .bottom, endPoint: .top)
                                )
                                .symbolEffect(.bounce, value: streak)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(streak)")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                                Text(streak == 1 ? "day" : "days")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text("BEST")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(.tertiary)
                            Text("\(longest)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().opacity(0.4)

                    HStack(spacing: 0) {
                        ForEach(week, id: \.date) { day in
                            StreakDot(
                                date: day.date,
                                met: day.metGoal(minutesGoal: minutesGoal, calorieGoal: calorieGoal),
                                isToday: Calendar.current.isDateInToday(day.date)
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 188)
    }
}

struct StreakDot: View {
    let date: Date
    let met: Bool
    let isToday: Bool

    private var initial: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(met ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.1))
                    .frame(width: 30, height: 30)

                if met {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.28))
                        .frame(width: 7, height: 7)
                }

                if isToday {
                    Circle()
                        .strokeBorder(met ? Color.orange : Color.secondary.opacity(0.5), lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
            }
            Text(initial)
                .font(.system(size: 10, weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - Today Goal Card

struct TodayGoalCard: View {
    let activity: DayActivity
    let minutesGoal: Int
    let calorieGoal: Int
    let appleExerciseMinutes: Int

    private var minutesProgress: Double {
        guard minutesGoal > 0 else { return 0 }
        return min(Double(activity.workoutMinutes) / Double(minutesGoal), 1.0)
    }

    private var caloriesShown: Int {
        max(activity.healthActiveCalories, activity.workoutCalories)
    }

    private var caloriesProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(Double(caloriesShown) / Double(calorieGoal), 1.0)
    }

    private var met: Bool {
        activity.metGoal(minutesGoal: minutesGoal, calorieGoal: calorieGoal)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 4)
            .overlay {
                VStack(spacing: 14) {
                    HStack {
                        Text("Today's Goal")
                            .font(.headline)
                        Spacer()
                        Text(met ? "Met" : "In progress")
                            .font(.caption.bold())
                            .foregroundStyle(met ? .green : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                (met ? Color.green : Color.secondary).opacity(0.13),
                                in: Capsule()
                            )
                    }

                    HStack(spacing: 22) {
                        GoalRing(
                            progress: minutesProgress,
                            value: "\(activity.workoutMinutes)",
                            unit: "of \(minutesGoal) min",
                            color: .green,
                            icon: "timer"
                        )
                        GoalRing(
                            progress: caloriesProgress,
                            value: "\(caloriesShown)",
                            unit: "of \(calorieGoal) kcal",
                            color: .orange,
                            icon: "flame.fill"
                        )
                    }

                    Text("Either ring filling counts the day toward your streak. Apple Exercise: \(appleExerciseMinutes) min.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .frame(height: 230)
    }
}

struct GoalRing: View {
    let progress: Double
    let value: String
    let unit: String
    let color: Color
    let icon: String

    @State private var animated = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.13), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: animated ? progress : 0)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.55), color],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(value)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 96, height: 96)

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.8)) { animated = true }
        }
        .onChange(of: progress) { _, _ in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { animated = true }
        }
    }
}

// MARK: - Summary Tile

struct SummaryTile: View {
    let value: String
    let label: String
    let sublabel: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.bold())
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Workout Row

struct WorkoutRow: View {
    let workout: Workout
    /// The condensed list on the Fitness tab is not grouped by day, so each
    /// row has to say which day it belongs to.
    var showsDate: Bool = false

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: workout.start)
        guard showsDate else { return time }
        return "\(WorkoutHistoryView.dayLabel(workout.day)) · \(time)"
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(workout.type.color)
                .frame(width: 4)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(workout.type.color.opacity(0.13))
                        .frame(width: 42, height: 42)
                    Image(systemName: workout.type.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(workout.type.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(timeText)
                        if workout.source == .appleHealth {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.pink)
                        }
                        if !workout.notes.isEmpty {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 8))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(workout.minutes)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(workout.type.color)
                    + Text(" min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if workout.calories > 0 {
                        Text("\(workout.calories) kcal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String
    let progress: Double?
    let progressColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 3)
            .overlay {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack {
                        Circle().fill(iconColor.opacity(0.12)).frame(width: 38, height: 38)
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // The bar row is always laid out, even for a card with no
                    // goal to track. Otherwise that card's text sits lower than
                    // its neighbours and the grid stops lining up.
                    Group {
                        if let progress {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(progressColor.opacity(0.12)).frame(height: 4)
                                    Capsule()
                                        .fill(progressColor)
                                        .frame(width: max(geo.size.width * progress, 0), height: 4)
                                }
                            }
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: 4)
                    .padding(.top, 8)

                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                // Without this the stack is only as wide as its content, and
                // .overlay centres it. The cards that happen to contain a
                // GeometryReader were stretched to full width by accident,
                // which is why only Distance looked centred.
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 148)
    }
}

#Preview {
    FitnessView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}

// MARK: - Weight Sparkline

/// Deliberately bare: no axes, no labels, no interaction. It signals direction
/// only, and the Weight screen carries the readable version.
struct WeightSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 0.1)
                let stepX = geo.size.width / CGFloat(values.count - 1)
                let point: (Int) -> CGPoint = { index in
                    CGPoint(
                        x: CGFloat(index) * stepX,
                        y: geo.size.height * (1 - CGFloat((values[index] - lo) / span))
                    )
                }

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for index in values.indices { path.addLine(to: point(index)) }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.22), Color.indigo.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: point(0))
                        for index in values.indices.dropFirst() { path.addLine(to: point(index)) }
                    }
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Circle()
                        .fill(Color.indigo)
                        .frame(width: 5, height: 5)
                        .position(point(values.count - 1))
                }
            } else {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .accessibilityHidden(true)
    }
}
