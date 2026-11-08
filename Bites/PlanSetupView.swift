// PlanSetupView.swift
import SwiftUI

/// Calorie deficit calculator. Shown automatically on first launch, and from
/// Settings → Your Plan any time after. Results update live as you type.
struct PlanSetupView: View {
    /// First launch shows a welcome header and "Skip" instead of "Cancel".
    var isFirstLaunch: Bool = false

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DiaryStore
    @ObservedObject private var plan = PlanStore.shared

    @State private var profile: BodyProfile
    @State private var mode: TrackingMode
    @State private var weightText: String
    @State private var feet: Int
    @State private var inches: Int

    init(isFirstLaunch: Bool = false) {
        self.isFirstLaunch = isFirstLaunch
        var start = PlanStore.shared.profile
        let latest = DiaryStore.shared.latestWeight
        if latest > 0 { start.weightPounds = latest }
        _profile = State(initialValue: start)
        _mode = State(initialValue: PlanStore.shared.hasCompletedSetup ? PlanStore.shared.trackingMode : .points)
        _weightText = State(initialValue: Self.format(start.weightPounds))
        _feet = State(initialValue: start.heightInches / 12)
        _inches = State(initialValue: start.heightInches % 12)
    }

    private var calc: CalorieCalculation { CalorieCalculation(profile: profile) }

    private var weightIsValid: Bool {
        guard let w = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return false }
        return (70...700).contains(w)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isFirstLaunch {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            Text("Welcome to Bites")
                                .font(.title2.bold())
                            Text("Answer a few questions and Bites will work out your daily calories, macros and points budget. You can redo this any time in Settings.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("About You") {
                    Picker("Sex", selection: $profile.sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Stepper(value: $profile.age, in: 13...100) {
                        HStack {
                            Text("Age")
                            Spacer()
                            Text("\(profile.age)")
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack {
                        Text("Height")
                        Spacer()
                        Picker("Feet", selection: $feet) {
                            ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Picker("Inches", selection: $inches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("185", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                        Text("lb").foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Activity", selection: $profile.activity) {
                        ForEach(ActivityLevel.allCases) { level in
                            VStack(alignment: .leading) {
                                Text(level.title)
                                Text(level.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Activity Level")
                } footer: {
                    Text("Count everyday movement too. If you are unsure, pick the lower level; workouts you log can be eaten back.")
                }

                Section("Goal") {
                    Picker("Goal", selection: $profile.goal) {
                        ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section("How do you want to track?") {
                    ForEach(TrackingMode.allCases) { option in
                        Button {
                            mode = option
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.icon)
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.headline)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: mode == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(mode == option ? Color.orange : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                resultsSection
            }
            .navigationTitle(isFirstLaunch ? "Set Up Your Plan" : "Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFirstLaunch ? "Skip" : "Cancel") {
                        if isFirstLaunch { plan.hasCompletedSetup = true }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!weightIsValid)
                }
            }
            .onChange(of: weightText) { _, newValue in
                if let w = Double(newValue.replacingOccurrences(of: ",", with: ".")), w > 0 {
                    profile.weightPounds = w
                }
            }
            .onChange(of: feet) { _, _ in profile.heightInches = feet * 12 + inches }
            .onChange(of: inches) { _, _ in profile.heightInches = feet * 12 + inches }
        }
        .interactiveDismissDisabled(isFirstLaunch)
    }

    // MARK: - Results

    private var resultsSection: some View {
        Section {
            resultRow("Resting burn (BMR)", "\(calc.bmr) kcal")
            resultRow("Total daily burn (TDEE)", "\(calc.tdee) kcal")
            resultRow(calc.dailyDeficit >= 0 ? "Daily deficit" : "Daily surplus",
                      "\(abs(calc.dailyDeficit)) kcal")

            HStack {
                Text("Daily calorie target").fontWeight(.semibold)
                Spacer()
                Text("\(calc.targetCalories) kcal")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }

            if mode == .points {
                HStack {
                    Text("Daily Bites Points").fontWeight(.semibold)
                    Spacer()
                    Text("\(calc.dailyPoints)")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                }
                resultRow("Weekly extra points", "\(calc.weeklyPoints)")
            }

            resultRow("Protein / Carbs / Fat", "\(calc.proteinGrams) / \(calc.carbGrams) / \(calc.fatGrams) g")
        } header: {
            Text("Your Numbers")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(projectionText)
                if calc.wasClamped {
                    Label("That pace would put you under \(calc.minimumSafeCalories) kcal a day, so the target is held at that floor. Pick a slower pace for a lower number than this.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text("Calculated with the Mifflin-St Jeor equation. Estimates only, not medical advice.")
            }
            .font(.caption)
        }
    }

    private var projectionText: String {
        let pace = calc.projectedPoundsPerWeek
        if abs(pace) < 0.05 { return "At this target your weight should hold steady." }
        let direction = pace < 0 ? "lose" : "gain"
        return "At this target you would \(direction) about \(Self.format(abs(pace))) lb a week."
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        profile.heightInches = feet * 12 + inches
        plan.apply(CalorieCalculation(profile: profile), mode: mode, to: store)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    PlanSetupView(isFirstLaunch: true)
        .environmentObject(DiaryStore.shared)
}
