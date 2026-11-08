// BitesApp.swift
import SwiftUI

@main
struct BitesApp: App {
    @StateObject private var store = DiaryStore.shared
    @StateObject private var workouts = WorkoutStore.shared
    // Held so its notification delegate is installed at launch.
    @StateObject private var reminder = WeighInReminder.shared
    @AppStorage("isDarkMode") private var isDarkMode = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(workouts)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
    }
}

/// Tabs plus everything app-wide: toasts, the achievement banner, the
/// first-launch plan setup, and keeping streaks and reminders current.
/// Split out of BitesApp so the type checker sees smaller expressions.
struct RootView: View {
    @EnvironmentObject private var store: DiaryStore
    @EnvironmentObject private var workouts: WorkoutStore
    @ObservedObject private var plan = PlanStore.shared
    @ObservedObject private var achievements = AchievementStore.shared

    var body: some View {
        tabs
            .overlay(alignment: .bottom) { mealToast }
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.showMealAddedToast)
            .onChange(of: store.showMealAddedToast) { _, isShowing in
                if isShowing {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .overlay(alignment: .top) { achievementBanner }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: achievements.banner)
            .onChange(of: achievements.banner) { _, badge in
                if badge != nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            // First launch: run the calorie / points calculator before anything else.
            .fullScreenCover(isPresented: setupBinding) {
                PlanSetupView(isFirstLaunch: true)
                    .environmentObject(store)
            }
            .modifier(DerivedStateRefresher(refresh: refreshDerivedState))
    }

    private var tabs: some View {
        TabView {
            ContentView()
                .tabItem { Label("Today", systemImage: "fork.knife") }

            FoodDiaryView()
                .tabItem { Label("Diary", systemImage: "book.closed") }

            SavedMealsView()
                .tabItem { Label("Meals", systemImage: "tray.full") }

            FitnessView()
                .tabItem { Label("Fitness", systemImage: "figure.run") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.orange)
    }

    @ViewBuilder
    private var mealToast: some View {
        if store.showMealAddedToast {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text("Meal Added")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
            .padding(.bottom, 92)
            .transition(
                .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.85))
            )
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var achievementBanner: some View {
        if let badge = achievements.banner {
            AchievementBanner(achievement: badge)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(11)
                .onTapGesture { achievements.banner = nil }
        }
    }

    private var setupBinding: Binding<Bool> {
        Binding(
            get: { !plan.hasCompletedSetup },
            set: { presented in
                if !presented { plan.hasCompletedSetup = true }
            }
        )
    }

    private func refreshDerivedState() {
        achievements.evaluate(diary: store, workouts: workouts)
        ReminderCenter.shared.reschedule(diary: store)
    }
}

/// Re-derives streaks, badges and logging reminders whenever their inputs change.
private struct DerivedStateRefresher: ViewModifier {
    let refresh: () -> Void

    @EnvironmentObject private var store: DiaryStore
    @EnvironmentObject private var workouts: WorkoutStore
    @ObservedObject private var plan = PlanStore.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    store.refreshToday()
                    refresh()
                }
            }
            .onChange(of: store.days) { _, _ in refresh() }
            .onChange(of: store.weightEntries) { _, _ in refresh() }
            .onChange(of: workouts.workouts) { _, _ in refresh() }
            .onChange(of: plan.trackingMode) { _, _ in refresh() }
            .onChange(of: plan.dailyPointsBudget) { _, _ in refresh() }
    }
}
