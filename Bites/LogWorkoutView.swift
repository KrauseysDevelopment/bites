// LogWorkoutView.swift
import SwiftUI

struct LogWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workouts: WorkoutStore
    @EnvironmentObject private var store: DiaryStore

    private let existing: Workout?

    @State private var type: WorkoutType
    @State private var title: String
    @State private var start: Date
    @State private var minutes: Int
    @State private var caloriesText: String
    @State private var notes: String
    /// Once the user types a calorie value we stop overwriting it.
    @State private var caloriesEditedByHand: Bool

    private let minuteOptions = [10, 15, 20, 30, 45, 60, 75, 90]

    init(editing workout: Workout? = nil) {
        existing = workout
        _type    = State(initialValue: workout?.type ?? .walking)
        _title   = State(initialValue: workout?.title ?? "")
        _start   = State(initialValue: workout?.start ?? Date())
        _minutes = State(initialValue: workout?.minutes ?? 30)
        _notes   = State(initialValue: workout?.notes ?? "")
        _caloriesText = State(initialValue: workout.map { String($0.calories) } ?? "")
        _caloriesEditedByHand = State(initialValue: workout != nil)
    }

    private var isEditing: Bool { existing != nil }

    private var estimatedCalories: Int {
        type.estimatedCalories(minutes: minutes, bodyWeightPounds: store.latestWeight)
    }

    private var resolvedCalories: Int {
        Int(caloriesText) ?? estimatedCalories
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                durationSection
                caloriesSection

                Section("Details") {
                    DatePicker("Date & time", selection: $start)
                    TextField("Name (optional)", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if let existing, existing.source == .appleHealth {
                    Section {
                        Label(
                            "Imported from Apple Health. Edits stay in Bites and will not change your Health data.",
                            systemImage: "heart.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let existing { workouts.delete(id: existing.id) }
                            dismiss()
                        } label: {
                            Label("Delete Workout", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Workout" : "Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(minutes <= 0)
                }
            }
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section("Activity") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WorkoutType.allCases) { option in
                        WorkoutTypeChip(type: option, isSelected: option == type) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                type = option
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
        }
    }

    private var durationSection: some View {
        Section("Duration") {
            HStack {
                Text("Minutes")
                Spacer()
                Button {
                    minutes = max(1, minutes - 5)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(minutes)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .frame(minWidth: 54)
                    .contentTransition(.numericText())

                Button {
                    minutes += 5
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(type.color)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(minuteOptions, id: \.self) { option in
                        Button {
                            withAnimation(.spring(response: 0.25)) { minutes = option }
                        } label: {
                            Text("\(option)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    minutes == option ? type.color.opacity(0.18) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                                .foregroundStyle(minutes == option ? type.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 0))
        }
    }

    private var caloriesSection: some View {
        Section {
            HStack {
                Text("Calories burned")
                Spacer()
                TextField("\(estimatedCalories)", text: $caloriesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(.orange)
                    .fontWeight(.semibold)
                    .onChange(of: caloriesText) { _, _ in caloriesEditedByHand = true }
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !caloriesEditedByHand || caloriesText.isEmpty {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                    Text(estimateExplanation)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Energy")
        } footer: {
            Text("Leave this blank to use the estimate. Apple Health's own active-calorie total is used for your streak when it is higher.")
                .font(.caption)
        }
    }

    private var estimateExplanation: String {
        if store.latestWeight > 0 {
            return "Estimated \(estimatedCalories) kcal at \(Int(store.latestWeight)) lb"
        }
        return "Estimated \(estimatedCalories) kcal (log your weight for a closer number)"
    }

    // MARK: - Save

    private func save() {
        var workout = existing ?? Workout(type: type, minutes: minutes, calories: 0)
        workout.type = type
        workout.title = title
        workout.start = start
        workout.minutes = minutes
        workout.calories = resolvedCalories
        workout.notes = notes

        if existing == nil {
            workouts.add(workout)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            workouts.update(workout)
        }
        dismiss()
    }
}

// MARK: - Type Chip

struct WorkoutTypeChip: View {
    let type: WorkoutType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? type.color : type.color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : type.color)
                }
                Text(type.label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LogWorkoutView()
        .environmentObject(DiaryStore.shared)
        .environmentObject(WorkoutStore.shared)
}
