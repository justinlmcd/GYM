import Foundation

nonisolated struct Exercise: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let unit: String
    let targetSets: Int
    let targetReps: Int
    let increment: Double

    enum CodingKeys: String, CodingKey {
        case id, name, unit, increment
        case targetSets = "target_sets"
        case targetReps = "target_reps"
    }

    // The Digital Crown moves weight by the exercise's own increment.
    var step: Double { increment > 0 ? increment : (unit == "kg" ? 2.5 : 5) }
}

// One row of public.sets. `id` is made on the watch so a retried upload never duplicates.
nonisolated struct LoggedSet: Codable, Identifiable, Hashable {
    let id: UUID
    let exerciseId: UUID
    let performedOn: String
    let setNo: Int
    let weight: Double
    let reps: Int

    enum CodingKeys: String, CodingKey {
        case id, weight, reps
        case exerciseId = "exercise_id"
        case performedOn = "performed_on"
        case setNo = "set_no"
    }
}

// One row of public.cardio. Blank speed or calories are left out, so they save as empty.
nonisolated struct CardioSession: Codable, Identifiable, Hashable {
    let id: UUID
    let performedOn: String
    let kind: String
    let minutes: Double
    let speed: Double?
    let speedUnit: String
    let calories: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, minutes, speed, calories
        case performedOn = "performed_on"
        case speedUnit = "speed_unit"
    }

    var label: String { CardioKind(rawValue: kind)?.label ?? kind.capitalized }
}

// GYM's cardio types. The web app saves "Other" types as their lowercase name, so
// rowing and elliptical show up there by name.
nonisolated enum CardioKind: String, CaseIterable, Identifiable {
    case treadmill, stairmaster, bike, rowing, elliptical, other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var defaultUnit: String {
        switch self {
        case .treadmill: return "mph"
        case .stairmaster: return "level"
        case .bike: return "rpm"
        case .rowing: return "spm"
        case .elliptical, .other: return "level"
        }
    }

    static let units = ["mph", "km/h", "level", "spm", "rpm"]
}

// A workout from GYM, like "Chest day 1": its exercises, in order.
nonisolated struct Workout: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let exerciseIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case id, name
        case exerciseIds = "exercise_ids"
    }
}

// One exercise opened from a workout, so its screen can offer the next one.
nonisolated struct WorkoutStep: Hashable {
    let workout: Workout
    let exerciseId: UUID
}

nonisolated struct Session: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
}

nonisolated enum Day {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // Local calendar day, matching GYM's today().
    static func string(_ date: Date = Date()) -> String { formatter.string(from: date) }
    static func daysAgo(_ n: Int) -> String {
        string(Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date())
    }

    // The day before a "yyyy-MM-dd" day.
    static func before(_ day: String) -> String {
        guard let d = formatter.date(from: day) else { return "" }
        return string(Calendar.current.date(byAdding: .day, value: -1, to: d) ?? d)
    }

    // The local day of a timestamp like "2026-11-02T14:05:00.123+00:00" (BODY's readings).
    static func string(fromTimestamp ts: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: ts) { return string(d) }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: ts) { return string(d) }
        return String(ts.prefix(10))
    }

    static func adding(_ n: Int, to day: String) -> String {
        guard let d = formatter.date(from: day) else { return day }
        return string(Calendar.current.date(byAdding: .day, value: n, to: d) ?? d)
    }

    // A bill's next charge on or after today: its first date rolled forward on its schedule
    // (weekly, monthly or yearly) past dates already gone, as on the MONEY page. Jan 31 monthly lands on Feb 28.
    static func nextDue(from first: String, cadence: String) -> String? {
        guard let start = formatter.date(from: first) else { return nil }
        let today = string()
        var k = 0, day = first
        while day < today && k < 600 {
            k += 1
            let next: Date?
            switch cadence {
            case "weekly": next = Calendar.current.date(byAdding: .day, value: 7 * k, to: start)
            case "yearly": next = Calendar.current.date(byAdding: .year, value: k, to: start)
            default: next = Calendar.current.date(byAdding: .month, value: k, to: start)
            }
            day = next.map { string($0) } ?? today
        }
        return day
    }

    // The Monday that starts this week, as on GYM and YOU.
    static func weekStart() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return string(start)
    }

    // "today", "yesterday" or "Nov 1".
    static func label(_ day: String) -> String {
        if day == string() { return "today" }
        if day == daysAgo(1) { return "yesterday" }
        guard let d = formatter.date(from: day) else { return day }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}

nonisolated func formatWeight(_ w: Double) -> String {
    w.rounded() == w ? String(Int(w)) : String(format: "%g", w)
}
