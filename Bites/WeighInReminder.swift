// WeighInReminder.swift
import Foundation
import SwiftUI
import UserNotifications

/// Weekly "step on the scale" nudge: a real notification on the chosen day plus
/// an in-app card, so missing the notification does not mean missing the week.
@MainActor
final class WeighInReminder: NSObject, ObservableObject {
    static let shared = WeighInReminder()

    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Keys.enabled); apply() } }
    /// Calendar convention: 1 = Sunday … 7 = Saturday.
    @Published var weekday: Int { didSet { defaults.set(weekday, forKey: Keys.weekday); apply() } }
    @Published var hour: Int    { didSet { defaults.set(hour, forKey: Keys.hour); apply() } }
    @Published var minute: Int  { didSet { defaults.set(minute, forKey: Keys.minute); apply() } }
    /// Daily weigh-ins give the trend chart the most to work with; weekly is
    /// the gentler option.
    @Published var isDaily: Bool { didSet { defaults.set(isDaily, forKey: Keys.daily); apply() } }

    /// Set when the user turned the reminder on but iOS notifications are off.
    @Published private(set) var permissionDenied = false
    @Published private(set) var isRequestingPermission = false

    private let defaults = UserDefaults.standard
    private let identifier = "bites.weighin.weekly"

    private enum Keys {
        static let enabled   = "WeighInReminderEnabled"
        static let weekday   = "WeighInReminderWeekday"
        static let hour      = "WeighInReminderHour"
        static let minute    = "WeighInReminderMinute"
        static let dismissed = "WeighInCardDismissedOn"
        static let daily     = "WeighInReminderDaily"
    }

    private override init() {
        isEnabled = defaults.bool(forKey: Keys.enabled)
        weekday   = defaults.int(forKey: Keys.weekday, default: 2)   // Monday
        hour      = defaults.int(forKey: Keys.hour, default: 8)
        minute    = defaults.int(forKey: Keys.minute, default: 0)
        isDaily   = defaults.bool(forKey: Keys.daily)
        super.init()
        UNUserNotificationCenter.current().delegate = self

        // Property observers do not run during init, so without this a
        // reminder enabled in an earlier session never gets re-registered
        // after a reinstall or once the pending request is cleared.
        if isEnabled {
            Task { await requestPermissionAndSchedule() }
        }
    }

    /// Re-evaluates the in-app card. Call when the app comes back to the
    /// foreground: `isDue` reads the clock, not published state, so crossing
    /// into the reminder day while backgrounded would otherwise go unnoticed.
    func refreshDueState() {
        objectWillChange.send()
    }

    // MARK: - Scheduling

    private var isBatchingEdit = false

    private func apply() {
        guard !isBatchingEdit else { return }
        guard isEnabled else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
            permissionDenied = false
            return
        }
        Task { await requestPermissionAndSchedule() }
    }

    func requestPermissionAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        isRequestingPermission = true
        defer { isRequestingPermission = false }

        let settings = await center.notificationSettings()
        var granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional

        if settings.authorizationStatus == .notDetermined {
            granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }

        permissionDenied = !granted
        guard granted else { return }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = isDaily ? "Morning weigh-in" : "Weekly weigh-in"
        content.body = "Time to step on the scale and log your weight in Bites."
        content.sound = .default

        var components = DateComponents()
        if !isDaily { components.weekday = weekday }
        components.hour = hour
        components.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    // MARK: - In-app card

    /// The most recent occurrence of the chosen weekday, today included.
    private var currentWeekAnchor: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        var back = todayWeekday - weekday
        if back < 0 { back += 7 }
        return calendar.date(byAdding: .day, value: -back, to: today) ?? today
    }

    /// Due when the reminder is on, the chosen day has come round, nothing has
    /// been logged since, and the card has not been dismissed today.
    func isDue(lastWeighIn: Date?) -> Bool {
        guard isEnabled else { return false }
        let anchor = isDaily ? Calendar.current.startOfDay(for: Date()) : currentWeekAnchor
        if let lastWeighIn, lastWeighIn >= anchor { return false }
        if let dismissed = defaults.object(forKey: Keys.dismissed) as? Date,
           Calendar.current.isDateInToday(dismissed) {
            return false
        }
        return true
    }

    func dismissCardForToday() {
        defaults.set(Date(), forKey: Keys.dismissed)
        objectWillChange.send()
    }

    // MARK: - Display helpers

    static let weekdayNames = Calendar.current.weekdaySymbols   // index 0 = Sunday

    var weekdayName: String {
        let names = Self.weekdayNames
        let index = weekday - 1
        return names.indices.contains(index) ? names[index] : "Monday"
    }

    var timeOfDay: Date {
        get {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            isBatchingEdit = true
            hour = parts.hour ?? 8
            isBatchingEdit = false
            minute = parts.minute ?? 0   // this one triggers the single reschedule
        }
    }

    var scheduleSummary: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let time = formatter.string(from: timeOfDay)
        return isDaily ? "every day at \(time)" : "\(weekdayName)s at \(time)"
    }
}

// Shows the reminder while the app is open instead of silently swallowing it.
extension WeighInReminder: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
