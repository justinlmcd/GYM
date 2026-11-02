import AppIntents

// "Hey Siri" logging: say the phrase, Siri asks for the number, and it's saved to that app
// like a log made on the watch, uploaded before Siri answers. Works with the app closed.

// MONEY's categories, so you can say "log groceries in YOU".
nonisolated enum SpendCategory: String, AppEnum {
    case foodAndDrink, groceries, transport, shopping, subscriptions, bills, housing, health, entertainment, travel, other

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var caseDisplayRepresentations: [SpendCategory: DisplayRepresentation] {
        [.foodAndDrink: "Food & drink", .groceries: "Groceries", .transport: "Transport", .shopping: "Shopping",
         .subscriptions: "Subscriptions", .bills: "Bills & utilities", .housing: "Housing", .health: "Health",
         .entertainment: "Entertainment", .travel: "Travel", .other: "Other"]
    }

    // The category's name in MONEY.
    var moneyName: String {
        switch self {
        case .foodAndDrink: return "Food & drink"
        case .bills: return "Bills & utilities"
        default: return rawValue.capitalized
        }
    }
}

private let signInFirst: IntentDialog = "Open YOU on your watch and sign in first."

nonisolated struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource { "Log weight" }
    static var description: IntentDescription { IntentDescription("Log today's weight to BODY.") }

    @Parameter(title: "Weight", requestValueDialog: "What did you weigh?")
    var weight: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard await store.readyForIntent() else { return .result(dialog: signInFirst) }
        let value = snap(weight, to: 0.1), unit = store.lastWeightUnit
        store.logWeight(value, unit: unit, upload: false)
        await store.finishIntent()
        return .result(dialog: "Logged \(formatWeight(value)) \(unit) to BODY.")
    }
}

nonisolated struct LogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "Log expense" }
    static var description: IntentDescription { IntentDescription("Log money you spent to MONEY.") }

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "Category", requestValueDialog: "Which category?")
    var category: SpendCategory

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard await store.readyForIntent() else { return .result(dialog: signInFirst) }
        let value = snap(amount, to: 0.01), name = category.moneyName
        guard value > 0 else { return .result(dialog: "Say an amount above zero.") }
        store.logExpense(value, category: name, merchant: "", upload: false)
        await store.finishIntent()
        return .result(dialog: "Logged \(value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) to \(name).")
    }
}

nonisolated struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource { "Log meal" }
    static var description: IntentDescription { IntentDescription("Log a meal's calories to MEAL.") }

    @Parameter(title: "Calories", requestValueDialog: "How many calories?")
    var calories: Int

    @Parameter(title: "Protein (g)")
    var protein: Int?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard await store.readyForIntent() else { return .result(dialog: signInFirst) }
        guard calories > 0 else { return .result(dialog: "Say the calories as a number above zero.") }
        let slot = MealLogView.slotNow()
        store.logMeal(kcal: calories, protein: max(0, protein ?? 0), carbs: 0, fat: 0, name: "Quick add", slot: slot, upload: false)
        await store.finishIntent()
        return .result(dialog: "Logged \(calories) calories for \(slot).")
    }
}

nonisolated struct RateDayIntent: AppIntent {
    static var title: LocalizedStringResource { "Rate my day" }
    static var description: IntentDescription { IntentDescription("Rate today 1 to 10 in WRITE.") }

    @Parameter(title: "Rating", requestValueDialog: "How was your day, 1 to 10?")
    var rating: Int

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard await store.readyForIntent() else { return .result(dialog: signInFirst) }
        let value = min(10, max(1, rating))
        if note?.isEmpty == false { await store.loadJournalToday() } // a new note goes under today's
        store.saveDay(rating: value, note: note ?? "", upload: false)
        await store.finishIntent()
        return .result(dialog: "Saved today as \(value) out of 10.")
    }
}

nonisolated struct LogPagesIntent: AppIntent {
    static var title: LocalizedStringResource { "Log pages" }
    static var description: IntentDescription { IntentDescription("Log pages read today to READ, for the book you're reading.") }

    @Parameter(title: "Pages", requestValueDialog: "How many pages?")
    var pages: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        guard await store.readyForIntent() else { return .result(dialog: signInFirst) }
        guard pages > 0 else { return .result(dialog: "Say the pages as a number above zero.") }
        guard let book = await store.currentBook() else {
            return .result(dialog: "Set a book to Reading now in READ first.")
        }
        store.logPages(pages, book: book.id, upload: false)
        await store.finishIntent()
        return .result(dialog: "Logged \(pages) pages of \(book.title).")
    }
}

// The phrases Siri listens for. Each has to name the app; Siri asks for the number.
nonisolated struct YOUShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWeightIntent(), phrases: [
            "Log my weight in \(.applicationName)",
            "Log weight in \(.applicationName)",
        ], shortTitle: "Log weight", systemImageName: "figure.stand")
        AppShortcut(intent: LogExpenseIntent(), phrases: [
            "Log an expense in \(.applicationName)",
            "Log spending in \(.applicationName)",
            "Log \(\.$category) in \(.applicationName)",
        ], shortTitle: "Log expense", systemImageName: "creditcard")
        AppShortcut(intent: LogMealIntent(), phrases: [
            "Log a meal in \(.applicationName)",
            "Log calories in \(.applicationName)",
        ], shortTitle: "Log meal", systemImageName: "fork.knife")
        AppShortcut(intent: RateDayIntent(), phrases: [
            "Rate my day in \(.applicationName)",
            "Rate today in \(.applicationName)",
        ], shortTitle: "Rate my day", systemImageName: "pencil.line")
        AppShortcut(intent: LogPagesIntent(), phrases: [
            "Log pages in \(.applicationName)",
            "Log reading in \(.applicationName)",
        ], shortTitle: "Log pages", systemImageName: "book")
    }
}
