import Foundation
import UserNotifications
import WatchKit

// The evening streak-saver: at your reminder time, a nudge listing what isn't logged yet today
// and the biggest streak that ends at midnight. Nothing comes when everything is logged.
// The text is worked out whenever today's numbers refresh, including a quiet background refresh
// half an hour before the reminder, so logs made on the web count too.
extension Store {
    static let reminderOnKey = "reminderOn"
    static let reminderHourKey = "reminderHour"
    static let refreshTaskID = "streaks"

    var reminderOn: Bool { UserDefaults.standard.object(forKey: Self.reminderOnKey) as? Bool ?? true }
    var reminderHour: Int { UserDefaults.standard.object(forKey: Self.reminderHourKey) as? Int ?? 20 }

    // Today's reminder from today's numbers, then a general one for each of the next six evenings
    // in case the watch doesn't get to refresh first. Each refresh replaces all seven.
    func scheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<7).map { "streaks-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard reminderOn, signedIn else { return }

        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            settings = await center.notificationSettings()
        }
        remindersBlocked = settings.authorizationStatus == .denied
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let cal = Calendar.current
        for (i, id) in ids.enumerated() {
            guard let day = cal.date(byAdding: .day, value: i, to: Date()),
                  let fire = cal.date(bySettingHour: reminderHour, minute: 0, second: 0, of: day),
                  fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.sound = .default
            if i == 0 {
                guard hubLoaded, let text = reminderText() else { continue } // all logged: no reminder today
                content.title = "Keep your streaks"
                content.body = text
            } else {
                content.title = "Anything left to log?"
                content.body = "Open YOU to log what you haven't today and keep your streaks going."
            }
            let when = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)))
        }
        scheduleBackgroundRefresh()
    }

    // "WRITE and READ aren't logged yet today. 🔥 21 on WRITE ends at midnight."
    func reminderText() -> String? {
        let missing = hubTiles.filter { $0.status == .ok && !$0.loggedToday }
        guard !missing.isEmpty else { return nil }
        let names = missing.map(\.kind.title)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        var text = "\(list) \(names.count == 1 ? "isn't" : "aren't") logged yet today."
        if let risk = missing.filter({ $0.streak.days > 0 }).max(by: { $0.streak.days < $1.streak.days }) {
            text += " 🔥 \(risk.streak.label) on \(risk.kind.title) ends at midnight."
        }
        return text
    }

    // Asks watchOS to wake the app half an hour before the next reminder to refresh its text.
    func scheduleBackgroundRefresh() {
        let cal = Calendar.current
        guard var when = cal.date(bySettingHour: reminderHour, minute: 0, second: 0, of: Date())?.addingTimeInterval(-30 * 60) else { return }
        if when <= Date() { when = cal.date(byAdding: .day, value: 1, to: when) ?? when }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: when, userInfo: Self.refreshTaskID as NSString) { _ in }
    }

    // Runs in the background: upload anything waiting, reload today's numbers (which reschedules the reminders).
    func backgroundRefresh() async {
        guard signedIn else { return }
        await flush()
        await loadHub()
    }
}
