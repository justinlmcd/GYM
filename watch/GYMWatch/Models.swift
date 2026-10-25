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
}

nonisolated func formatWeight(_ w: Double) -> String {
    w.rounded() == w ? String(Int(w)) : String(format: "%g", w)
}
