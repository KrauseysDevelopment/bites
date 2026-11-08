// ReminderCenter.swift
import Foundation
import SwiftUI
import UserNotifications

/// Local reminders that depend on what has been logged: the evening "nothing
/// logged yet" nudge, the late "streak at risk" alert, and achievement alerts.
/// The weigh-in reminder lives in WeighInReminder.
///
/// Local notifications cannot check a condition when they fire, so instead the
/// next seven days are scheduled one by one and the whole set is rebuilt
/// whenever the diary changes. Logging a meal today removes today's nudge.
@MainActor
final class ReminderCenter: ObservableObject {
    static let shared = ReminderCenter()

    @Published var logNudgeEnabled: Bool { didSet { defaults.set(logNudgeEnabled, forKey: Keys.nudge); settingsChanged() } }
    @Published var logNudgeHour: Int { didSet { defaults.set(logNudgeHour, forKey: Keys.nudgeHour); settingsChanged() } }
    @Published var logNudgeMinute: Int { didSet { defaults.set(logNudgeMinute, forKey: Keys.nudgeMinute); settingsChanged() } }

    @Published var streakAlertEnabled: Bool { didSet { defaults.set(streakAlertEnabled, forKey: Keys.streak); settingsChanged() } }
    @Published var streakAlertHour: Int { didSet { defaults.set(streakAlertHour, forKey: Keys.streakHour); settingsChanged() } }
    @Published var streakAlertMinute: Int { didSet { defaults.set(streakAlertMinute, forKey: Keys.streakMinute); settingsChanged() } }

    @Published var achievementAlertsEnabled: Bool { didSet { defaults.set(achievementAlertsEnabled, forKey: Keys.achievements); settingsChanged() } }

    @Published private(set) var permissionDenied = false

    private let defaults = UserDefaults.standard
    private let nudgePrefix = "bites.lognudge."
    private let streakPrefix = "bites.streak."
    private let horizonDays = 7
    private var isBatchingEdit = false

    private enum Keys {
        static let nudge        = "LogNudgeEnabled"
        static let nudgeHour    = "LogNudgeHour"
        static let nudgeMinute  = "LogNudgeMinute"
        static let streak       = "StreakAlertEnabled"
        static let streakHour   = "StreakAlertHour"
        static let streakMinute = "StreakAlertMinute"
        static let achievements = "AchievementAlertsEnabled"
    }

    private init() {
        logNudgeEnabled    = defaults.bool(forKey: Keys.nudge)
        logNudgeHour       = defaults.int(forKey: Keys.nudgeHour, default: 19)
        logNudgeMinute     = defaults.int(forKey: Keys.nudgeMinute, default: 0)
        streakAlertEnabled = defaults.bool(forKey: Keys.streak)
        streakAlertHour    = defaults.int(forKey: Keys.streakHour, default: 20)
        streakAlertMinute  = defaults.int(forKey: Keys.streakMinute, default: 30)
        achievementAlertsEnabled = defaults.object(forKey: Keys.achievements) as? Bool ?? true
    }

    // MARK: - Times as Dates for DatePicker

    var logNudgeTime: Date {
        get { Self.date(hour: logNudgeHour, minute: logNudgeMinute) }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            isBatchingEdit = true
            logNudgeHour = parts.hour ?? 19
            isBatchingEdit = false
            logNudgeMinute = parts.minute ?? 0
        }
    }

    var streakAlertTime: Date {
        get { Self.date(hour: streakAlertHour, minute: streakAlertMinute) }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            isBatchingEdit = true
            streakAlertHour = parts.hour ?? 20
            isBatchingEdit = false
            streakAlertMinute = parts.minute ?? 30
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Permission

    /// Asks once; afterwards reports whether alerts are allowed.
    func ensurePermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        permissionDenied = !granted
        return granted
    }

    // MARK: - Scheduling

    private func settingsChanged() {
        guard !isBatchingEdit else { return }
        reschedule(diary: .shared)
    }

    /// Rebuilds the nudge and streak alerts for the next week.
    func reschedule(diary: DiaryStore) {
        let loggedToday = !diary.today.meals.isEmpty
        let logged = Streaks.loggedDays(diary.days)
        let streak = Streaks.current(qualifyingDays: logged)
        let nudgeOn = logNudgeEnabled
        let streakOn = streakAlertEnabled
        let nudgeTime = (logNudgeHour, logNudgeMinute)
        let streakTime = (streakAlertHour, streakAlertMinute)

        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(nudgePrefix) || $0.hasPrefix(streakPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            guard nudgeOn || streakOn else { return }
            guard await ensurePermission() else { return }

            let calendar = Calendar.current
            let now = Date()
            let today = calendar.startOfDay(for: now)

            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let isToday = offset == 0

                if nudgeOn && !(isToday && loggedToday) {
                    await schedule(
                        id: nudgePrefix + Self.stamp(day),
                        on: day, hour: nudgeTime.0, minute: nudgeTime.1, now: now,
                        title: "Nothing logged yet today",
                        body: "Take a minute to add today's meals in Bites."
                    )
                }

                // Only worth warning about a streak that exists. Today's alert
                // names the number; later days assume it is still going.
                if streakOn && streak > 0 && !(isToday && loggedToday) {
                    let body = isToday
                        ? "Your \(streak)-day logging streak ends tonight. Log something to keep it."
                        : "Log today to keep your streak alive."
                    await schedule(
                        id: streakPrefix + Self.stamp(day),
                        on: day, hour: streakTime.0, minute: streakTime.1, now: now,
                        title: "Streak at risk 🔥",
                        body: body
                    )
                }
            }
        }
    }

    private func schedule(id: String, on day: Date, hour: Int, minute: Int, now: Date,
                          title: String, body: String) async {
        let calendar = Calendar.current
        guard let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
              fire > now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func stamp(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    // MARK: - Achievements

    func notifyAchievement(_ achievement: Achievement) {
        guard achievementAlertsEnabled else { return }
        Task {
            guard await ensurePermission() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Achievement unlocked: \(achievement.title)"
            content.body = achievement.detail
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "bites.achievement.\(achievement.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}
