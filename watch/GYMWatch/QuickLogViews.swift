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

            // Bills due in the next 7 days, or the next one coming.
            Section {
                let week = store.hub.billsThisWeek
                if week.isEmpty {
                    if let next = store.hub.bills.first {
                        Text("Nothing in the next 7 days. Next: \(next.name) \(formatMoney(next.amount)) \(Day.label(next.day)).")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Give your bills a next charge date in MONEY to see them here.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(week) { bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bill.name).lineLimit(1)
                            Text(Day.label(bill.day)).font(.caption2)
                                .foregroundStyle(bill.day <= Day.adding(1, to: Day.string()) ? Color.red : Color.secondary)
                        }
                        Spacer()
                        Text(formatMoney(bill.amount)).monospacedDigit()
                    }
                }
            } header: {
                let total = store.hub.billsThisWeek.reduce(0) { $0 + $1.amount }
                Text(total > 0 ? "Due this week · \(formatMoney(total))" : "Due this week")
            }

            // Your debts: tap one to record a payment.
            if store.hub.debtsReady && !store.hub.debts.isEmpty {
                Section {
                    ForEach(store.hub.debts.filter { $0.balance > 0 }) { debt in
                        NavigationLink { DebtPayView(debt: debt) } label: {
                            HStack {
                                Text(debt.name).lineLimit(1)
                                Spacer()
                                Text(formatMoney(debt.balance)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Debts · \(formatMoney(store.hub.debts.reduce(0) { $0 + $1.balance })) left")
                }
            }
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

// A payment on one debt: the amount on the crown, starting at its minimum, and the balance it leaves.
struct DebtPayView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    let debt: WatchDebt
    @State private var amount: Double = 0
    @State private var seeded = false

    var body: some View {
        List {
            Dial(value: formatMoney(amount), unit: "paid", active: focused)
                .focusable()
                .focused($focused)
                .digitalCrownRotation($amount, from: 0, through: max(debt.balance, 1), by: 5, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .listRowBackground(Color.clear)
            Text("\(formatMoney(debt.balance)) → \(formatMoney(max(0, debt.balance - amount))) left")
                .font(.footnote).monospacedDigit()
                .listRowBackground(Color.clear)
            LogButton(title: "Record payment", kind: .money, disabled: amount <= 0) {
                store.recordDebtPayment(amount, debt: debt)
                dismiss()
            }
            if let min = debt.minPayment {
                Text("Minimum \(formatMoney(min)) a month").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(debt.name)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            amount = min(debt.balance, debt.minPayment ?? 50)
            focused = true
        }
    }
}

// MEAL: calories, protein, carbs and fat on the crown (tap one to turn it), a name, and which meal.
// A recent or saved food fills all of them in one tap; you still press Log meal to save.
struct MealLogView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    private enum Field { case kcal, protein, carbs, fat }
    @FocusState private var focus: Field?
    @State private var kcal: Double = 300
    @State private var protein: Double = 20
    @State private var carbs: Double = 30
    @State private var fat: Double = 10
    @State private var name = ""
    @State private var slot = MealLogView.slotNow()

    var body: some View {
        List {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    dial("\(Int(kcal))", "kcal", .kcal, $kcal, through: 5000, by: 10, sensitivity: .medium)
                    dial("\(Int(protein))", "g protein", .protein, $protein, through: 400, by: 1, sensitivity: .low)
                }
                HStack(spacing: 6) {
                    dial("\(Int(carbs))", "g carbs", .carbs, $carbs, through: 600, by: 1, sensitivity: .low)
                    dial("\(Int(fat))", "g fat", .fat, $fat, through: 300, by: 1, sensitivity: .low)
                }
            }
            .listRowBackground(Color.clear)
            TextField("What (optional)", text: $name)
            Picker("Meal", selection: $slot) {
                ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            LogButton(title: "Log meal", kind: .meal, disabled: kcal <= 0 && protein <= 0 && carbs <= 0 && fat <= 0) {
                let what = name.trimmingCharacters(in: .whitespaces)
                store.logMeal(kcal: Int(kcal), protein: Int(protein), carbs: Int(carbs), fat: Int(fat), name: what.isEmpty ? "Quick add" : what, slot: slot)
                dismiss()
            }
            Text(todayNote).font(.footnote).foregroundStyle(.secondary)

            if !store.hub.foods.isEmpty {
                Section("Recent & saved") {
                    ForEach(store.hub.foods) { food in
                        Button {
                            name = food.name
                            kcal = Double(food.calories)
                            protein = Double(food.protein)
                            carbs = Double(food.carbs)
                            fat = Double(food.fat)
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(food.name).lineLimit(2)
                                Text("\(food.calories) kcal · P \(food.protein) · C \(food.carbs) · F \(food.fat)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityHint("Fills in this food. Press Log meal to save it.")
                    }
                }
            }
        }
        .navigationTitle("MEAL")
        .onAppear { focus = .kcal }
    }

    private func dial(_ value: String, _ unit: String, _ field: Field, _ binding: Binding<Double>, through: Double, by step: Double, sensitivity: DigitalCrownRotationalSensitivity) -> some View {
        Dial(value: value, unit: unit, active: focus == field)
            .focusable()
            .focused($focus, equals: field)
            .digitalCrownRotation(binding, from: 0, through: through, by: step, sensitivity: sensitivity, isContinuous: false, isHapticFeedbackEnabled: true)
            .onTapGesture { focus = field }
    }

    private var todayNote: String {
        let h = store.hub
        func part(_ v: Double, _ goal: Double?, _ label: String) -> String {
            goal.map { "\(Int(v))/\(Int($0)) g \(label)" } ?? "\(Int(v)) g \(label)"
        }
        return "Today \(Int(h.mealKcal)) of \(Int(h.mealGoal)) kcal · " + [part(h.mealProtein, h.proteinGoal, "protein"), part(h.mealCarbs, h.carbsGoal, "carbs"), part(h.mealFat, h.fatGoal, "fat")].joined(separator: " · ")
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
