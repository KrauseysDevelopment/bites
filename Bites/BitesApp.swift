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
            .environmentObject(store)
            .environmentObject(workouts)
            .preferredColorScheme(isDarkMode ? .dark : .light)
            .overlay(alignment: .bottom) {
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
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.showMealAddedToast)
            .onChange(of: store.showMealAddedToast) { _, isShowing in
                if isShowing {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
}
