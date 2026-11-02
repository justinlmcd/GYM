import SwiftUI
import WatchKit

// The screen each home-screen row opens. GYM keeps its own screens.
@ViewBuilder
func quickLog(for kind: AppKind) -> some View {
    switch kind {
    case .body: BodyLogView()
    case .money: MoneyLogView()
    case .gym: ExerciseListView()
    case .meal: MealLogView()
    case .write: WriteLogView()
    case .read: ReadLogView()
    }
}

// The big button at the bottom of each log screen, in that app's colour.
private struct LogButton: View {
    let title: String
    let kind: AppKind
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button {
            action()
            WKInterfaceDevice.current().play(.success)
        } label: {
            Text(title).font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(kind.color)
        .disabled(disabled)
        .listRowBackground(Color.clear)
    }
}

// BODY: today's weight on the crown, starting from your last reading, in its unit.
struct BodyLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var weight: Double = 0
    @State private var seeded = false

    var body: some View {
        let unit = store.hub.weightUnit
        List {
            Dial(value: String(format: "%.1f", weight), unit: unit, active: focused)
                .focusable()
                .focused($focused)
                .digitalCrownRotation($weight, from: 0, through: 1000, by: 0.1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .listRowBackground(Color.clear)
            LogButton(title: "Log weight", kind: .body, disabled: weight <= 0) {
                store.logWeight(weight, unit: unit)
                dismiss()
            }
            if let last = store.hub.lastWeight {
                Text("Last reading \(formatWeight((last * 10).rounded() / 10)) \(unit)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("BODY")
        .onAppear {
            guard !seeded else { return }
            seeded = true
            weight = store.hub.lastWeight ?? (unit == "kg" ? 70 : 160)
            focused = true
        }
    }
}

// MONEY: an amount on the crown in whole units, a category, and where. Shows what's left of that category's budget.
struct MoneyLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var amount: Double = 0
    @State private var category = "Food & drink"
    @State private var merchant = ""

    var body: some View {
        List {
            Dial(value: formatMoney(amount), unit: "spent", active: focused)
                .focusable()
                .focused($focused)
                .digitalCrownRotation($amount, from: 0, through: 5000, by: 1, sensitivity: .high, isContinuous: false, isHapticFeedbackEnabled: true)
                .listRowBackground(Color.clear)
            Picker("Category", selection: $category) {
                ForEach(MoneyCategory.all, id: \.self) { Text($0).tag($0) }
            }
            TextField("Where (optional)", text: $merchant)
            LogButton(title: amount > 0 ? "Log \(formatMoney(amount))" : "Log expense", kind: .money, disabled: amount <= 0) {
                store.logExpense(amount, category: category, merchant: merchant.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            Text(budgetNote).font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("MONEY")
        .onAppear { focused = true }
    }

    private var budgetNote: String {
        let spent = store.hub.spentByCategory[category] ?? 0
        guard let plan = store.hub.budgetByCategory[category] else { return "\(formatMoney(spent)) on \(category) this month" }
        let left = plan - spent
        return left >= 0 ? "\(formatMoney(left)) left of \(formatMoney(plan)) for \(category) this month" : "\(formatMoney(-left)) over your \(formatMoney(plan)) for \(category)"
    }
}

// MEAL: calories and protein on the crown, a name if you want one, and the meal it was.
struct MealLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    private enum Field { case kcal, protein }
    @FocusState private var focus: Field?
    @State private var kcal: Double = 300
    @State private var protein: Double = 20
    @State private var name = ""
    @State private var slot = MealLogView.slotNow()

    var body: some View {
        List {
            HStack(spacing: 6) {
                Dial(value: "\(Int(kcal))", unit: "kcal", active: focus == .kcal)
                    .focusable()
                    .focused($focus, equals: .kcal)
                    .digitalCrownRotation($kcal, from: 0, through: 5000, by: 10, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onTapGesture { focus = .kcal }
                Dial(value: "\(Int(protein))", unit: "g protein", active: focus == .protein)
                    .focusable()
                    .focused($focus, equals: .protein)
                    .digitalCrownRotation($protein, from: 0, through: 400, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onTapGesture { focus = .protein }
            }
            .listRowBackground(Color.clear)
            TextField("What (optional)", text: $name)
            Picker("Meal", selection: $slot) {
                ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            LogButton(title: "Log meal", kind: .meal, disabled: kcal <= 0 && protein <= 0) {
                let what = name.trimmingCharacters(in: .whitespaces)
                store.logMeal(kcal: Int(kcal), protein: Int(protein), name: what.isEmpty ? "Quick add" : what, slot: slot)
                dismiss()
            }
            Text(todayNote).font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("MEAL")
        .onAppear { focus = .kcal }
    }

    private var todayNote: String {
        let h = store.hub
        let protein = h.proteinGoal.map { " · \(Int(h.mealProtein)) of \(Int($0)) g protein" } ?? " · \(Int(h.mealProtein)) g protein"
        return "Today \(Int(h.mealKcal)) of \(Int(h.mealGoal)) kcal" + protein
    }

    // Breakfast before 10:30, lunch until 3, dinner until 9, otherwise a snack.
    private static func slotNow() -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let m = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        if m < 630 { return "breakfast" }
        if m < 900 { return "lunch" }
        if m < 1260 { return "dinner" }
        return "snack"
    }
}

// WRITE: rate today 1–10 on the crown and add a note by voice. Saving again updates today's entry.
struct WriteLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var rating: Double = 7
    @State private var note = ""
    @State private var seeded = false

    private static let words = [1: "Awful", 2: "Rough", 3: "Bad", 4: "Meh", 5: "Okay", 6: "Fine", 7: "Good", 8: "Great", 9: "Excellent", 10: "Perfect"]

    var body: some View {
        let today = store.hub.journalToday
        List {
            Dial(value: "\(Int(rating))", unit: Self.words[Int(rating)] ?? "", active: focused)
                .focusable()
                .focused($focused)
                .digitalCrownRotation($rating, from: 1, through: 10, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .listRowBackground(Color.clear)
            TextField(today?.body.isEmpty == false ? "Add to today's note" : "How did today go? (optional)", text: $note)
            LogButton(title: today == nil ? "Save today" : "Update today", kind: .write) {
                store.saveDay(rating: Int(rating), note: note)
                dismiss()
            }
            if let today, !today.body.isEmpty {
                Text(today.body).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
            }
        }
        .navigationTitle("WRITE")
        .onAppear {
            guard !seeded else { return }
            seeded = true
            if let today { rating = Double(today.rating) }
            focused = true
        }
    }
}

// READ: pages read today for a book you're reading, with where they take you.
struct ReadLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var pages: Double = 10
    @State private var bookId: UUID?

    var body: some View {
        let books = store.hub.books
        let book = books.first { $0.id == bookId } ?? books.first
        List {
            if !store.hub.pagesReady {
                Text("To log pages, run pages.sql in Supabase once, then refresh.").font(.footnote).foregroundStyle(.orange)
            } else if let book {
                if books.count > 1 {
                    Picker("Book", selection: Binding(get: { book.id }, set: { bookId = $0 })) {
                        ForEach(books) { Text($0.title).tag($0.id) }
                    }
                } else {
                    Text(book.title).font(.headline)
                }
                Dial(value: "\(Int(pages))", unit: "pages", active: focused)
                    .focusable()
                    .focused($focused)
                    .digitalCrownRotation($pages, from: 1, through: 500, by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                    .listRowBackground(Color.clear)
                if let total = book.totalPages, total > 0 {
                    let after = book.pagesRead + Int(pages)
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(min(after, total)), total: Double(total)).tint(AppKind.read.color)
                        Text("\(book.pagesRead) → \(after) of \(total) · \(min(100, after * 100 / total))%")
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    .listRowBackground(Color.clear)
                }
                LogButton(title: "Log \(Int(pages)) pages", kind: .read) {
                    store.logPages(Int(pages), book: book.id)
                    dismiss()
                }
            } else {
                Text("Set a book to Reading now in READ, then refresh.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("READ")
        .onAppear { focused = true }
    }
}
