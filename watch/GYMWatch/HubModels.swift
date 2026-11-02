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
nonisolated struct SpendRow: Decodable { let occurredOn: String; let amount: Num; let category: String
    enum CodingKeys: String, CodingKey { case amount, category; case occurredOn = "occurred_on" } }
nonisolated struct BudgetLine: Decodable { let category: String?; let kind: String; let amount: Num }
nonisolated struct BudgetPlan: Decodable { let allocations: [BudgetLine] }
nonisolated struct BudgetRow: Decodable { let budget: BudgetPlan? }
nonisolated struct DayRow: Decodable { let performedOn: String
    enum CodingKeys: String, CodingKey { case performedOn = "performed_on" } }
nonisolated struct MealRow: Decodable { let eatenOn: String; let name: String; let calories: Num; let protein: Num; let carbs: Num; let fat: Num
    enum CodingKeys: String, CodingKey { case name, calories, protein, carbs, fat; case eatenOn = "eaten_on" } }
nonisolated struct FoodRow: Decodable { let name: String; let brand: String?; let calories: Num; let protein: Num; let carbs: Num; let fat: Num }
nonisolated struct MealGoalRow: Decodable { let calories: Num?; let protein: Num?; let carbs: Num?; let fat: Num? }
nonisolated struct JournalRow: Decodable { let writtenOn: String; let rating: Int; let body: String?
    enum CodingKeys: String, CodingKey { case rating, body; case writtenOn = "written_on" } }
nonisolated struct PagesRow: Decodable { let bookId: UUID; let readOn: String; let pages: Int
    enum CodingKeys: String, CodingKey { case pages; case bookId = "book_id"; case readOn = "read_on" } }
nonisolated struct BookRow: Decodable { let id: UUID; let title: String; let status: String; let finishedOn: String?; let totalPages: Int?
    enum CodingKeys: String, CodingKey { case id, title, status; case finishedOn = "finished_on"; case totalPages = "total_pages" } }
nonisolated struct BookRowNoPages: Decodable { let id: UUID; let title: String; let status: String; let finishedOn: String?
    enum CodingKeys: String, CodingKey { case id, title, status; case finishedOn = "finished_on" } }

nonisolated func formatMoney(_ v: Double) -> String {
    v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0)))
}

// What the quick-log screens need, kept from the last time the home screen loaded.
nonisolated struct HubData {
    var lastWeight: Double?
    var weightUnit = "lbs"
    var spentByCategory: [String: Double] = [:]
    var budgetByCategory: [String: Double] = [:]
    var mealKcal = 0.0
    var mealProtein = 0.0
    var mealCarbs = 0.0
    var mealFat = 0.0
    var mealGoal = 2000.0
    var proteinGoal: Double?
    var carbsGoal: Double?
    var fatGoal: Double?
    var foods: [QuickFood] = []
    var journalToday: JournalToday?
    var books: [ReadingBook] = []
    var pagesReady = true
    var bills: [DueBill] = []
    var debts: [WatchDebt] = []
    var debtsReady = false

    var billsThisWeek: [DueBill] { let end = Day.adding(6, to: Day.string()); return bills.filter { $0.day <= end } }
}

// A food to fill the MEAL screen with in one tap: something you logged recently, or one of MEAL's saved foods.
nonisolated struct QuickFood: Identifiable, Hashable {
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    var id: String { "\(name)|\(calories)|\(protein)|\(carbs)|\(fat)" }
}

// MONEY's scheduled bills and subscriptions, and its debts list.
nonisolated struct SubRow: Decodable { let name: String; let amount: Num; let cadence: String; let nextCharge: String?
    enum CodingKeys: String, CodingKey { case name, amount, cadence; case nextCharge = "next_charge" } }
nonisolated struct DebtRow: Decodable { let id: UUID; let name: String; let balance: Num; let minPayment: Num?
    enum CodingKeys: String, CodingKey { case id, name, balance; case minPayment = "min_payment" } }

// A bill's next charge day, worked out from its schedule as on the MONEY page.
nonisolated struct DueBill: Identifiable, Hashable {
    let name: String
    let amount: Double
    let day: String
    var id: String { name + day }
}

nonisolated struct WatchDebt: Identifiable, Hashable {
    let id: UUID
    let name: String
    var balance: Double
    let minPayment: Double?
}

nonisolated struct BookTitleRow: Decodable { let id: UUID; let title: String }

nonisolated struct JournalToday { let rating: Int; let body: String }

nonisolated struct ReadingBook: Identifiable, Hashable {
    let id: UUID
    let title: String
    let totalPages: Int?
    let pagesRead: Int
}

// A log saved on the watch and waiting to upload to one of the apps' tables.
// `body` is the row as JSON; `onConflict` names the columns to update in place (WRITE's one entry per day).
nonisolated struct OutboxItem: Codable, Identifiable, Hashable {
    let id: UUID
    let table: String
    let body: Data
    let onConflict: String?
}

// MONEY's categories, as on the MONEY page.
nonisolated enum MoneyCategory {
    static let all = ["Food & drink", "Groceries", "Transport", "Shopping", "Subscriptions", "Bills & utilities", "Housing", "Health", "Entertainment", "Travel", "Other"]
}
