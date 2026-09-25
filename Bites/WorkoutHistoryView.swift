// WorkoutHistoryView.swift
import SwiftUI

/// The full workout log, moved off the Fitness tab so a month of history
/// cannot stretch that page to several screens tall.
struct WorkoutHistoryView: View {
    @EnvironmentObject private var workouts: WorkoutStore
    @State private var editingWorkout: Workout?
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case logged = "Logged"
        case health = "Health"

        var id: String { rawValue }

        func matches(_ workout: Workout) -> Bool {
            switch self {
            case .all:    return true
            case .logged: return workout.source == .manual
            case .health: return workout.source == .appleHealth
            }
        }
    }

    private var filtered: [Workout] {
        workouts.workouts.filter(filter.matches)
    }

    private var grouped: [(day: Date, workouts: [Workout])] {
        Dictionary(grouping: filtered, by: \.day)
            .keys
            .sorted(by: >)
            .map { day in
                let items = filtered.filter { $0.day == day }.sorted { $0.start > $1.start }
                return (day: day, workouts: items)
            }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Section {
                    Text(filter == .all ? "No workouts logged yet." : "Nothing matches this filter.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(grouped, id: \.day) { group in
                Section {
                    ForEach(group.workouts) { workout in
                        WorkoutRow(workout: workout)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { editingWorkout = workout }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    workouts.delete(id: workout.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(WorkoutHistoryView.dayLabel(group.day))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .textCase(nil)
                        Spacer()
                        Text("\(group.workouts.reduce(0) { $0 + $1.minutes }) min")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle("Workout Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .sheet(item: $editingWorkout) { workout in
            LogWorkoutView(editing: workout)
        }
    }

    static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "EEEE, MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryView()
            .environmentObject(WorkoutStore.shared)
            .environmentObject(DiaryStore.shared)
    }
}
