import SwiftUI

// The six apps YOU brings together, in YOU's order, each with its own colour from the web pages.
nonisolated enum AppKind: String, CaseIterable, Identifiable, Hashable {
    case body, money, gym, meal, write, read

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var symbol: String {
        switch self {
        case .body: return "figure.stand"
        case .money: return "creditcard"
        case .gym: return "dumbbell"
        case .meal: return "fork.knife"
        case .write: return "pencil.line"
        case .read: return "book"
        }
    }

    var color: Color {
        switch self {
        case .body: return Color(red: 0.561, green: 0.827, blue: 1.0)
        case .money: return Color(red: 0.561, green: 0.890, blue: 0.690)
        case .gym: return Color(red: 1.0, green: 0.608, blue: 0.608)
        case .meal: return Color(red: 0.788, green: 0.655, blue: 1.0)
        case .write: return Color(red: 1.0, green: 0.851, blue: 0.541)
        case .read: return Color(red: 1.0, green: 0.722, blue: 0.420)
        }
    }
}

// One app's line on the home screen: today's number, a short note and its streak.
nonisolated struct AppTile: Identifiable, Hashable {
    nonisolated enum Status: Hashable { case ok, notSetUp, failed }

    let kind: AppKind
    var status: Status = .ok
    var value = "—"
    var unit = ""
    var note = ""
    var loggedToday = false
    var streak = Streak()

    var id: AppKind { kind }
}

// Days in a row with something logged, counting back from today, as on YOU.
// Today isn't over, so a streak that only misses today is still alive ("kept" is false until you log).
nonisolated struct Streak: Hashable {
    var days = 0
    var kept = false
    var more = false

    init() {}

    init(days list: [String], since: String) {
        let has = Set(list)
        let today = Day.string()
        kept = has.contains(today)
        var day = kept ? today : Day.daysAgo(1)
        var n = 0
        while day >= since && has.contains(day) {
            n += 1
            day = Day.before(day)
        }
        days = n
        more = day < since
    }

    var label: String { "\(days)\(more ? "+" : "")" }
}

// PostgREST sends numeric columns as JSON numbers, but a string or null must not break the screen.
nonisolated struct Num: Decodable, Hashable {
    let value: Double

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
        else { value = 0 }
    }
}

// The rows each app writes, only the columns the home screen reads.
nonisolated struct WeightRow: Decodable { let value: Num; let unit: String; let occurredAt: String
    enum CodingKeys: String, CodingKey { case value, unit; case occurredAt = "occurred_at" } }
nonisolated struct SpendRow: Decodable { let occurredOn: String; let amount: Num
    enum CodingKeys: String, CodingKey { case amount; case occurredOn = "occurred_on" } }
nonisolated struct BudgetLine: Decodable { let kind: String; let amount: Num }
nonisolated struct BudgetPlan: Decodable { let allocations: [BudgetLine] }
nonisolated struct BudgetRow: Decodable { let budget: BudgetPlan? }
nonisolated struct DayRow: Decodable { let performedOn: String
    enum CodingKeys: String, CodingKey { case performedOn = "performed_on" } }
nonisolated struct MealRow: Decodable { let eatenOn: String; let calories: Num; let protein: Num
    enum CodingKeys: String, CodingKey { case calories, protein; case eatenOn = "eaten_on" } }
nonisolated struct MealGoalRow: Decodable { let calories: Num? }
nonisolated struct JournalRow: Decodable { let writtenOn: String; let rating: Int
    enum CodingKeys: String, CodingKey { case rating; case writtenOn = "written_on" } }
nonisolated struct PagesRow: Decodable { let readOn: String; let pages: Int
    enum CodingKeys: String, CodingKey { case pages; case readOn = "read_on" } }
nonisolated struct BookRow: Decodable { let title: String; let status: String; let finishedOn: String?
    enum CodingKeys: String, CodingKey { case title, status; case finishedOn = "finished_on" } }

nonisolated func formatMoney(_ v: Double) -> String {
    v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
}
