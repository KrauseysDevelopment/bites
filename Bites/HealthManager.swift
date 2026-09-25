// HealthManager.swift
import Foundation
import HealthKit

@MainActor
final class HealthManager: ObservableObject {
    static let shared = HealthManager()

    private let healthStore = HKHealthStore()

    // Today's snapshot
    @Published var steps = 0
    @Published var activeCalories = 0.0
    @Published var exerciseMinutes = 0.0
    @Published var distanceInMeters = 0.0
    @Published var restingCalories = 0.0

    @Published var isAuthorized = false
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?
    @Published var errorMessage: String?

    /// How far back to pull history for streaks and charts.
    private let historyDays = 180

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.bodyMass),
            HKObjectType.workoutType()
        ]
        types.insert(HKQuantityType(.distanceCycling))
        return types
    }

    // MARK: - Entry point

    /// Requests permission if needed, then reloads today's numbers, the daily
    /// history used for streaks, and any workouts recorded in Health.
    func refresh(into workoutStore: WorkoutStore, diaryStore: DiaryStore? = nil) async {
        guard isAvailable else {
            errorMessage = "Apple Health is not available on this device."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            errorMessage = nil
        } catch {
            isAuthorized = false
            errorMessage = "Health access was not granted."
            return
        }

        await loadTodayStats()
        await loadDailyHistory(into: workoutStore)

        if workoutStore.importFromHealth {
            let imported = await loadWorkouts()
            workoutStore.mergeHealthWorkouts(imported)
        }

        if let diaryStore { await syncLatestWeight(into: diaryStore) }

        lastRefresh = Date()
    }

    // MARK: - Today

    private func loadTodayStats() async {
        let start = Calendar.current.startOfDay(for: Date())
        let now = Date()

        steps            = Int(await sum(.stepCount, unit: .count(), from: start, to: now))
        activeCalories   = await sum(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        restingCalories  = await sum(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        exerciseMinutes  = await sum(.appleExerciseTime, unit: .minute(), from: start, to: now)
        distanceInMeters = await sum(.distanceWalkingRunning, unit: .meter(), from: start, to: now)
    }

    // MARK: - Daily history (streaks)

    private func loadDailyHistory(into workoutStore: WorkoutStore) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -historyDays, to: today) else { return }

        let now = Date()
        let caloriesByDay = await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        let minutesByDay  = await dailySums(.appleExerciseTime, unit: .minute(), from: start, to: now)

        workoutStore.healthActiveCalories  = caloriesByDay.mapValues { Int($0.rounded()) }
        workoutStore.healthExerciseMinutes = minutesByDay.mapValues { Int($0.rounded()) }
    }

    // MARK: - Workouts

    private func loadWorkouts() async -> [Workout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -historyDays, to: today) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let samples: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            healthStore.execute(query)
        }

        return samples.compactMap { sample in
            let minutes = Int((sample.duration / 60).rounded())
            guard minutes > 0 else { return nil }

            let burned = sample.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie()) ?? 0

            let type = WorkoutType(hkActivityType: sample.workoutActivityType)

            return Workout(
                type: type,
                start: sample.startDate,
                minutes: minutes,
                calories: Int(burned.rounded()),
                source: .appleHealth,
                healthKitID: sample.uuid
            )
        }
    }

    // MARK: - Weight

    private func syncLatestWeight(into diaryStore: DiaryStore) async {
        let type = HKQuantityType(.bodyMass)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, results, _ in
                continuation.resume(returning: results?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }

        guard let sample else { return }
        let pounds = sample.quantity.doubleValue(for: .pound())
        guard pounds > 0 else { return }

        let day = Calendar.current.startOfDay(for: sample.startDate)
        // Do not clobber a value typed in the app on the same day.
        if diaryStore.weightEntries.contains(where: { $0.date == day }) { return }
        diaryStore.logWeight(pounds, on: sample.startDate)
    }

    // MARK: - Query helpers

    private func sum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: anchor, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var totals: [Date: Double] = [:]
                collection?.enumerateStatistics(from: anchor, to: end) { statistics, _ in
                    let day = calendar.startOfDay(for: statistics.startDate)
                    totals[day] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Mapping Apple's activity types onto ours

extension WorkoutType {
    init(hkActivityType: HKWorkoutActivityType) {
        switch hkActivityType {
        case .walking:
            self = .walking
        case .running, .trackAndField:
            self = .running
        case .cycling, .handCycling:
            self = .cycling
        case .hiking:
            self = .hiking
        case .swimming, .waterFitness, .swimBikeRun:
            self = .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            self = .strength
        case .highIntensityIntervalTraining:
            self = .hiit
        case .rowing, .paddleSports:
            self = .rowing
        case .elliptical:
            self = .elliptical
        case .stairClimbing, .stairs, .stepTraining:
            self = .stairs
        case .yoga, .mindAndBody:
            self = .yoga
        case .pilates, .barre, .flexibility, .coreTraining:
            self = .pilates
        case .basketball, .soccer, .americanFootball, .baseball, .softball,
             .tennis, .volleyball, .golf, .hockey, .racquetball, .squash,
             .pickleball, .badminton, .tableTennis, .lacrosse, .rugby, .cricket:
            self = .sports
        case .cardioDance, .socialDance:
            self = .dance
        case .boxing, .martialArts, .kickboxing, .wrestling, .taiChi:
            self = .martialArts
        default:
            self = .other
        }
    }
}
