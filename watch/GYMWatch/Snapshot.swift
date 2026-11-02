import Foundation
import WidgetKit

// What the watch-face complication shows. The app saves it after every refresh; the complication reads it.
// They share it through an App Group named "group." + the watch app's bundle identifier. Without that
// App Group (a free Apple ID may not allow it) the complication can't see it and shows a YOU launcher instead.
// This file belongs to both targets: the watch app and the YOUComplication extension.
nonisolated struct Snapshot: Codable {
    nonisolated struct App: Codable {
        let kind: String
        let streak: Int
        let kept: Bool
        let logged: Bool
    }

    let day: String
    let logged: Int
    let connected: Int
    let apps: [App]

    // The app's own bundle id, worked out the same way in the app and in its extension (whose id adds one more part).
    static var groupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        if Bundle.main.bundleURL.pathExtension == "appex" {
            id = id.split(separator: ".").dropLast().joined(separator: ".")
        }
        return "group." + id
    }

    static func save(_ snapshot: Snapshot) {
        guard let shared = UserDefaults(suiteName: groupID), let data = try? JSONEncoder().encode(snapshot) else { return }
        shared.set(data, forKey: "snapshot")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    // On a new day nothing is logged yet. Yesterday's kept streaks are still alive; any others have ended.
    func asOf(_ date: Date) -> Snapshot {
        let today = Self.dayString(date)
        if day == today { return self }
        let yesterday = Self.dayString(Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date)
        let alive = day == yesterday
        return Snapshot(day: today, logged: 0, connected: connected, apps: apps.map {
            App(kind: $0.kind, streak: alive && $0.kept ? $0.streak : 0, kept: false, logged: false)
        })
    }

    var bestStreak: App? { apps.filter { $0.streak > 0 }.max { $0.streak < $1.streak } }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static let sample = Snapshot(day: dayString(Date()), logged: 4, connected: 6, apps: [
        App(kind: "body", streak: 3, kept: true, logged: true), App(kind: "money", streak: 12, kept: true, logged: true),
        App(kind: "gym", streak: 5, kept: false, logged: false), App(kind: "meal", streak: 8, kept: true, logged: true),
        App(kind: "write", streak: 21, kept: true, logged: true), App(kind: "read", streak: 0, kept: false, logged: false),
    ])
}
