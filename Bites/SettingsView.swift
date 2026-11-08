// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @AppStorage("isDarkMode") private var isDarkMode = false
    @EnvironmentObject var store: DiaryStore
    @EnvironmentObject var workouts: WorkoutStore
    @State private var usdaKeyInput = Secrets.storedKeyForDisplay
    @StateObject private var reminder = WeighInReminder.shared
    @ObservedObject private var plan = PlanStore.shared
    @ObservedObject private var reminders = ReminderCenter.shared
    @State private var showingPlanSetup = false

    var body: some View {
        NavigationStack {
            List {
                planSection
                remindersSection

                // MARK: - Appearance
                Section {
                    SettingsToggleRow(
                        icon: "moon.fill",
                        iconColor: .indigo,
                        label: "Dark Mode",
                        isOn: $isDarkMode
                    )
                } header: {
                    SettingsSectionHeader("Appearance")
                }

                // MARK: - Units
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue.opacity(0.13))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "location.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                            Text("Distance Unit")
                                .font(.body)
                        }
                        Picker("Distance", selection: $store.distanceUnit) {
                            Text("Kilometers").tag(DistanceUnit.kilometers)
                            Text("Miles").tag(DistanceUnit.miles)
                        }
                        .pickerStyle(.segmented)
                        .padding(.leading, 46)
                    }
                    .padding(.vertical, 4)
                } header: {
                    SettingsSectionHeader("Units")
                }

                // MARK: - Daily Goals
                Section {
                    GoalRow(icon: "flame.fill",  iconColor: .orange, label: "Calories",
                            value: $store.calorieGoal, placeholder: "2500", unit: "kcal")
                    GoalRow(icon: "bolt.fill",   iconColor: .green,  label: "Protein",
                            value: $store.proteinGoal, placeholder: "150",  unit: "g")
                    GoalRow(icon: "leaf.fill",   iconColor: .purple, label: "Carbs",
                            value: $store.carbsGoal,   placeholder: "250",  unit: "g")
                    GoalRow(icon: "drop.triangle.fill", iconColor: .amber, label: "Fat",
                            value: $store.fatGoal,     placeholder: "80",   unit: "g")
                    GoalRow(icon: "drop.fill",    iconColor: .blue,   label: "Water",
                            value: $store.waterGoal,   placeholder: "8",    unit: "cups")
                } header: {
                    SettingsSectionHeader("Daily Goals")
                } footer: {
                    Text("These targets are reflected on the Today dashboard and macro progress bars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Fitness Goals
                Section {
                    GoalRow(icon: "timer",      iconColor: .green,  label: "Exercise",
                            value: $workouts.exerciseMinutesGoal, placeholder: "30", unit: "min")
                    GoalRow(icon: "flame.fill", iconColor: .orange, label: "Active Burn",
                            value: $workouts.activeCalorieGoal,   placeholder: "500", unit: "kcal")

                    HStack(spacing: 12) {
                        SettingsIconView(icon: "heart.fill", color: .pink)
                        Toggle("Import from Apple Health", isOn: $workouts.importFromHealth)
                            .tint(.orange)
                    }
                } header: {
                    SettingsSectionHeader("Fitness Goals")
                } footer: {
                    Text("A day counts toward your streak when you hit either the exercise minutes or the active calorie target. Turning off the Health import leaves the workout log manual only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Weigh-in Reminder
                Section {
                    HStack(spacing: 12) {
                        SettingsIconView(icon: "scalemass.fill", color: .indigo)
                        Toggle("Weigh-in Reminder", isOn: $reminder.isEnabled)
                            .tint(.orange)
                    }

                    if reminder.isEnabled {
                        HStack(spacing: 12) {
                            SettingsIconView(icon: "repeat", color: .purple)
                            Text("Frequency")
                            Spacer()
                            Picker("Frequency", selection: $reminder.isDaily) {
                                Text("Daily").tag(true)
                                Text("Weekly").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 150)
                        }
                    }

                    if reminder.isEnabled && !reminder.isDaily {
                        HStack(spacing: 12) {
                            SettingsIconView(icon: "calendar", color: .blue)
                            Text("Day")
                            Spacer()
                            Picker("Day", selection: $reminder.weekday) {
                                ForEach(Array(WeighInReminder.weekdayNames.enumerated()), id: \.offset) { index, name in
                                    Text(name).tag(index + 1)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    if reminder.isEnabled {
                        HStack(spacing: 12) {
                            SettingsIconView(icon: "clock.fill", color: .green)
                            DatePicker(
                                "Time",
                                selection: Binding(
                                    get: { reminder.timeOfDay },
                                    set: { reminder.timeOfDay = $0 }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                        }

                        if reminder.permissionDenied {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Notifications are turned off for Bites", systemImage: "bell.slash.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                                Text("The in-app reminder still appears on the Fitness tab. Turn notifications on in iOS Settings to get the alert too.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Open iOS Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    SettingsSectionHeader("Weigh-in Reminder")
                } footer: {
                    Text(reminder.isEnabled
                         ? "Reminding you \(reminder.scheduleSummary). A card also appears on the Fitness tab until you log."
                         : "Get a daily or weekly nudge to step on the scale.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Food Database
                // Hidden when the key ships in Secrets.plist: nothing to set.
                if !Secrets.keyIsBundled {
                    Section {
                        HStack(spacing: 12) {
                            SettingsIconView(icon: "key.fill", color: .green)
                            Text("USDA API Key")
                            Spacer()
                            if Secrets.keyIsBundled {
                                Text("From Secrets.plist")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                SecureField("Paste key", text: $usdaKeyInput)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit { Secrets.storeUSDAKey(usdaKeyInput) }
                                    .onChange(of: usdaKeyInput) { _, newValue in
                                        Secrets.storeUSDAKey(newValue)
                                    }
                            }
                        }

                        HStack(spacing: 12) {
                            SettingsIconView(
                                icon: Secrets.hasUSDAKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                color: Secrets.hasUSDAKey ? .green : .orange
                            )
                            Text(Secrets.hasUSDAKey ? "Food search is active" : "Food search needs a key")
                                .font(.subheadline)
                                .foregroundStyle(Secrets.hasUSDAKey ? .primary : .secondary)
                        }

                        if !Secrets.hasUSDAKey {
                            Link(destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup/")!) {
                                Label("Get a free key from USDA", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        SettingsSectionHeader("Food Database")
                    } footer: {
                        Text("Whole foods and branded products come from USDA FoodData Central. Barcode scanning uses Open Food Facts and works without a key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - App Info
                Section {
                    HStack {
                        SettingsIconView(icon: "fork.knife.circle.fill", color: .orange)
                        Text("Bites")
                            .font(.body)
                        Spacer()
                        Text("v1.0")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SettingsSectionHeader("About")
                }
            }
            .navigationTitle("Settings")
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .sheet(isPresented: $showingPlanSetup) {
                PlanSetupView()
            }
        }
    }

    private var planSection: some View {
        Section {
            Picker("Tracking", selection: $plan.trackingMode) {
                ForEach(TrackingMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Button {
                showingPlanSetup = true
            } label: {
                HStack(spacing: 12) {
                    SettingsIconView(icon: "function", color: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calorie & Deficit Calculator")
                            .foregroundStyle(.primary)
                        Text(plan.hasCompletedSetup
                             ? "\(store.calorieGoal) kcal · \(plan.dailyPointsBudget) pts a day"
                             : "Work out your calories, macros and points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
            }

            if plan.trackingMode == .points {
                GoalRow(icon: "circle.hexagongrid.fill", iconColor: .orange, label: "Daily Points",
                        value: $plan.dailyPointsBudget, placeholder: "30", unit: "pts")
                GoalRow(icon: "calendar", iconColor: .purple, label: "Weekly Points",
                        value: $plan.weeklyPointsAllowance, placeholder: "28", unit: "pts")
                HStack(spacing: 12) {
                    SettingsIconView(icon: "leaf.circle.fill", color: .green)
                    Toggle("ZeroPoint Foods", isOn: $plan.zeroPointFoodsEnabled)
                        .tint(.orange)
                }
                HStack(spacing: 12) {
                    SettingsIconView(icon: "arrow.uturn.forward.circle.fill", color: .blue)
                    Toggle("Roll Over Unused Points", isOn: $plan.rolloverEnabled)
                        .tint(.orange)
                }
            }
        } header: {
            SettingsSectionHeader("Your Plan")
        } footer: {
            Text(plan.trackingMode == .points
                 ? "Points weigh calories, saturated fat and sugar up and protein down. Plain fruit, vegetables, eggs, lean poultry, fish, beans and nonfat plain yogurt count as zero. Up to \(PlanStore.maxRolloverPerDay) unused daily points a day roll into your weekly points."
                 : "Track calories and macros against the goals below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var remindersSection: some View {
        Section {
            HStack(spacing: 12) {
                SettingsIconView(icon: "fork.knife", color: .orange)
                Toggle("Evening Log Nudge", isOn: $reminders.logNudgeEnabled)
                    .tint(.orange)
            }
            if reminders.logNudgeEnabled {
                DatePicker("Nudge at", selection: Binding(
                    get: { reminders.logNudgeTime },
                    set: { reminders.logNudgeTime = $0 }
                ), displayedComponents: .hourAndMinute)
                .padding(.leading, 46)
            }

            HStack(spacing: 12) {
                SettingsIconView(icon: "flame.fill", color: .red)
                Toggle("Streak at Risk", isOn: $reminders.streakAlertEnabled)
                    .tint(.orange)
            }
            if reminders.streakAlertEnabled {
                DatePicker("Warn at", selection: Binding(
                    get: { reminders.streakAlertTime },
                    set: { reminders.streakAlertTime = $0 }
                ), displayedComponents: .hourAndMinute)
                .padding(.leading, 46)
            }

            HStack(spacing: 12) {
                SettingsIconView(icon: "rosette", color: .purple)
                Toggle("Achievement Alerts", isOn: $reminders.achievementAlertsEnabled)
                    .tint(.orange)
            }

            if reminders.permissionDenied {
                Button("Notifications are off for Bites. Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(.orange)
            }
        } header: {
            SettingsSectionHeader("Reminders")
        } footer: {
            Text("The nudge only fires on days nothing has been logged by that time. The streak alert only fires while you have a streak going and today is still empty.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reusable Setting Rows

struct SettingsSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

struct SettingsIconView: View {
    let icon: String
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.13))
                .frame(width: 34, height: 34)
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconView(icon: icon, color: iconColor)
            Toggle(label, isOn: $isOn)
                .tint(.orange)
        }
    }
}

struct GoalRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    @Binding var value: Int
    let placeholder: String
    let unit: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIconView(icon: icon, color: iconColor)
            Text(label)
            Spacer()
            TextField(placeholder, value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .foregroundStyle(iconColor)
                .fontWeight(.semibold)
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
