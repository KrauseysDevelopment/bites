// AchievementsView.swift
import SwiftUI

/// Streaks up top, then badges by category, Apple Fitness style: earned ones
/// in color with the date, locked ones grey with progress toward them.
struct AchievementsView: View {
    @ObservedObject private var achievements = AchievementStore.shared
    @State private var selected: Achievement?

    private let categories = ["Food", "Fitness", "Weight", "Water"]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                streakGrid

                ForEach(categories, id: \.self) { category in
                    let items = Achievement.all.filter { $0.kind.category == category }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(category)
                            .font(.title3.bold())
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(items) { achievement in
                                Button { selected = achievement } label: {
                                    BadgeView(
                                        achievement: achievement,
                                        isUnlocked: achievements.isUnlocked(achievement),
                                        progress: achievements.progress(achievement)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { achievement in
            BadgeDetailView(
                achievement: achievement,
                unlockedOn: achievements.unlocked[achievement.id],
                progress: achievements.progress(achievement)
            )
            .presentationDetents([.medium])
        }
    }

    private var streakGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StreakTile(title: "Food logging", icon: "flame.fill", color: .orange, info: achievements.logging)
            StreakTile(title: "On budget", icon: "target", color: .green, info: achievements.onBudget)
            StreakTile(title: "Exercise goal", icon: "figure.run", color: .mint, info: achievements.workout)
            StreakTile(title: "Weigh-ins", icon: "scalemass.fill", color: .indigo, info: achievements.weighIn)
        }
    }
}

// MARK: - Pieces

struct StreakTile: View {
    let title: String
    let icon: String
    let color: Color
    let info: AchievementStore.StreakInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(info.current)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(info.current == 1 ? "day" : "days")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Best: \(info.best)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct BadgeView: View {
    let achievement: Achievement
    let isUnlocked: Bool
    let progress: Int

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        isUnlocked
                            ? AnyShapeStyle(LinearGradient(
                                colors: [achievement.color.opacity(0.75), achievement.color],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.secondary.opacity(0.12))
                    )
                    .frame(width: 74, height: 74)
                    .shadow(color: isUnlocked ? achievement.color.opacity(0.35) : .clear, radius: 8, y: 4)
                Image(systemName: achievement.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isUnlocked ? Color.white : Color.secondary.opacity(0.5))
                if achievement.threshold > 1 {
                    Text("\(achievement.threshold)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(isUnlocked ? achievement.color : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemBackground), in: Capsule())
                        .offset(y: 36)
                }
            }
            .frame(height: 86)

            Text(achievement.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(isUnlocked ? .primary : .secondary)

            if !isUnlocked {
                Text("\(progress)/\(achievement.threshold)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct BadgeDetailView: View {
    let achievement: Achievement
    let unlockedOn: Date?
    let progress: Int

    var body: some View {
        VStack(spacing: 16) {
            BadgeView(achievement: achievement, isUnlocked: unlockedOn != nil, progress: progress)
                .scaleEffect(1.4)
                .padding(.top, 36)
                .padding(.bottom, 12)
            Text(achievement.detail)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let unlockedOn {
                Text("Earned \(unlockedOn.formatted(date: .long, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: Double(progress), total: Double(achievement.threshold))
                    .tint(achievement.color)
                    .padding(.horizontal, 40)
                Text("\(progress) of \(achievement.threshold) \(achievement.kind.unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

/// Fitness-tab card that links to the full screen.
struct AchievementsSummaryCard: View {
    @ObservedObject private var achievements = AchievementStore.shared

    private var recent: [Achievement] {
        Achievement.all
            .filter { achievements.unlocked[$0.id] != nil }
            .sorted { (achievements.unlocked[$0.id] ?? .distantPast) > (achievements.unlocked[$1.id] ?? .distantPast) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Achievements", systemImage: "rosette")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
                Text("\(achievements.unlockedCount) of \(Achievement.all.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            if recent.isEmpty {
                Text("Log your first meal to earn your first badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    ForEach(recent) { achievement in
                        ZStack {
                            Circle()
                                .fill(achievement.color.gradient)
                                .frame(width: 44, height: 44)
                            Image(systemName: achievement.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }
}

/// Slides in at the top when a badge is earned while the app is open.
struct AchievementBanner: View {
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(achievement.color.gradient)
                    .frame(width: 40, height: 40)
                Image(systemName: achievement.icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 17, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Achievement unlocked")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(achievement.title)
                    .font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 24)
    }
}
