import Foundation

struct Exercise: Codable, Identifiable, Hashable {
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
struct LoggedSet: Codable, Identifiable, Hashable {
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

struct Session: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var email: String
}

enum Day {
    private static let formatter: DateFormatter = {
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

func formatWeight(_ w: Double) -> String {
    w.rounded() == w ? String(Int(w)) : String(format: "%g", w)
}
