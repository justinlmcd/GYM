import Foundation

// The home screen: one tile per app, read the way the YOU page reads them.
extension Store {
    // The tiles in YOU's order, with GYM's from the live data so a set you just logged counts at once.
    var hubTiles: [AppTile] { tiles.map { $0.kind == .gym && $0.status == .ok ? gymTile() : $0 } }
    var loggedTodayCount: Int { hubTiles.filter { $0.status == .ok && $0.loggedToday }.count }
    var connectedCount: Int { hubTiles.filter { $0.status == .ok }.count }

    // Each app is read on its own, so one that isn't set up never blanks the others.
    func loadHub() async {
        guard signedIn else { return }
        let body = await tile(.body) { try await self.bodyTile() }
        let money = await tile(.money) { try await self.moneyTile() }
        let gym = await tile(.gym) { try await self.loadCardioDays() }
        let meal = await tile(.meal) { try await self.mealTile() }
        let write = await tile(.write) { try await self.writeTile() }
        let read = await tile(.read) { try await self.readTile() }
        tiles = [body, money, gym, meal, write, read]
        hubLoaded = true
        // Hand today's numbers to the watch-face complication.
        Snapshot.save(Snapshot(day: Day.string(), logged: loggedTodayCount, connected: connectedCount, apps: hubTiles.filter { $0.status == .ok }.map {
            Snapshot.App(kind: $0.kind.rawValue, streak: $0.streak.days, kept: $0.streak.kept, logged: $0.loggedToday)
        }))
    }

    private func tile(_ kind: AppKind, _ make: () async throws -> AppTile) async -> AppTile {
        do {
            return try await make()
        } catch APIError.server(_, let message) where message.contains("schema cache") || message.contains("does not exist") {
            var t = AppTile(kind: kind)
            t.status = .notSetUp
            t.note = "not set up yet"
            return t
        } catch {
            if case APIError.signedOut = error { noteSignedOut() }
            // Keep what was showing; only a tile that never loaded says so.
            var t = tiles.first { $0.kind == kind } ?? AppTile(kind: kind)
            if t.value == "—" { t.status = .failed; t.note = "couldn't load" }
            return t
        }
    }

    private var since: String { Day.daysAgo(59) }

    private func bodyTile() async throws -> AppTile {
        let from = Day.daysAgo(89)
        let rows: [WeightRow] = try await api.rows("events?select=value,unit,occurred_at&metric=eq.weight&occurred_at=gte.\(from)T00:00:00Z&order=occurred_at.desc")
        let days = rows.map { Day.string(fromTimestamp: $0.occurredAt) }
        var t = AppTile(kind: .body)
        if let latest = rows.first {
            t.value = formatWeight((latest.value.value * 10).rounded() / 10)
            t.unit = latest.unit
            t.note = Day.label(days[0])
            t.loggedToday = days[0] == Day.string()
            hub.lastWeight = latest.value.value
            hub.weightUnit = latest.unit
        } else {
            t.note = "no readings yet"
        }
        t.streak = Streak(days: days, since: from)
        return t
    }

    // Money left this month against your budget when you have one, otherwise what you've spent.
    private func moneyTile() async throws -> AppTile {
        let rows: [SpendRow] = try await api.rows("transactions?select=occurred_on,amount,category&occurred_on=gte.\(since)&order=occurred_on.desc")
        let today = Day.string(), month = String(today.prefix(8)) + "01"
        let spent = rows.filter { $0.occurredOn >= month && $0.occurredOn <= today }.reduce(0) { $0 + $1.amount.value }
        let spentToday = rows.filter { $0.occurredOn == today }.reduce(0) { $0 + $1.amount.value }
        let budgets: [BudgetRow]? = try? await api.rows("money_profile?select=budget")
        let spendLines = budgets?.first?.budget?.allocations.filter { $0.kind == "need" || $0.kind == "want" } ?? []
        let plan = spendLines.reduce(0) { $0 + $1.amount.value }
        hub.budgetByCategory = Dictionary(spendLines.compactMap { l in l.category.map { ($0, l.amount.value) } }, uniquingKeysWith: +)
        hub.spentByCategory = Dictionary(rows.filter { $0.occurredOn >= month && $0.occurredOn <= today }.map { ($0.category, $0.amount.value) }, uniquingKeysWith: +)
        let todayNote = spentToday > 0 ? "\(formatMoney(spentToday)) today" : "nothing today"
        var t = AppTile(kind: .money)
        if plan > 0 {
            t.value = formatMoney(abs(plan - spent))
            t.unit = plan >= spent ? "left" : "over"
            t.note = "of \(formatMoney(plan)) this month · \(todayNote)"
        } else {
            t.value = formatMoney(spent)
            t.unit = "spent"
            t.note = "this month · \(todayNote)"
        }
        t.loggedToday = spentToday > 0
        t.streak = Streak(days: rows.map(\.occurredOn), since: since)
        return t
    }

    private func loadCardioDays() async throws -> AppTile {
        let rows: [DayRow]? = try? await api.rows("cardio?select=performed_on&performed_on=gte.\(since)")
        cardioDays = rows?.map(\.performedOn) ?? []
        return gymTile()
    }

    func gymTile() -> AppTile {
        let days = Set(allSets.map(\.performedOn) + cardioDays + todayCardio.map(\.performedOn))
        let week = days.filter { $0 >= Day.weekStart() }.count
        var t = AppTile(kind: .gym)
        t.value = "\(week)"
        t.unit = week == 1 ? "workout" : "workouts"
        t.note = days.max().map { "this week · last \(Day.label($0))" } ?? "this week · nothing yet"
        t.loggedToday = days.contains(Day.string())
        t.streak = Streak(days: Array(days), since: since)
        return t
    }

    private func mealTile() async throws -> AppTile {
        let rows: [MealRow] = try await api.rows("meal_entries?select=eaten_on,name,calories,protein,carbs,fat&eaten_on=gte.\(since)&order=eaten_on.desc")
        let goals: [MealGoalRow]? = try? await api.rows("meal_goals?select=calories,protein,carbs,fat&limit=1")
        let goal = goals?.first?.calories?.value ?? 2000
        let today = rows.filter { $0.eatenOn == Day.string() }
        let kcal = today.reduce(0) { $0 + $1.calories.value }, protein = today.reduce(0) { $0 + $1.protein.value }
        hub.mealKcal = kcal
        hub.mealProtein = protein
        hub.mealGoal = goal
        hub.proteinGoal = goals?.first?.protein?.value
        hub.mealCarbs = today.reduce(0) { $0 + $1.carbs.value }
        hub.mealFat = today.reduce(0) { $0 + $1.fat.value }
        hub.carbsGoal = goals?.first?.carbs?.value
        hub.fatGoal = goals?.first?.fat?.value
        // Quick picks: what you've eaten lately, newest first, then MEAL's saved foods. Each name once.
        let saved: [FoodRow] = (try? await api.rows("foods?select=name,brand,calories,protein,carbs,fat&order=name")) ?? []
        let pick = { (name: String, c: Num, p: Num, cb: Num, f: Num) in
            QuickFood(name: name, calories: Int(c.value.rounded()), protein: Int(p.value.rounded()), carbs: Int(cb.value.rounded()), fat: Int(f.value.rounded()))
        }
        var seen = Set<String>(), foods: [QuickFood] = []
        for r in rows where r.name != "Quick add" {
            if seen.insert(r.name.lowercased()).inserted { foods.append(pick(r.name, r.calories, r.protein, r.carbs, r.fat)) }
        }
        for f in saved {
            if seen.insert(f.name.lowercased()).inserted { foods.append(pick(f.name, f.calories, f.protein, f.carbs, f.fat)) }
        }
        hub.foods = Array(foods.prefix(25))
        var t = AppTile(kind: .meal)
        t.value = "\(Int(kcal.rounded()))"
        t.unit = "kcal"
        t.note = today.isEmpty ? "of \(Int(goal)) · nothing logged today" : "of \(Int(goal)) · \(Int(protein.rounded())) g protein"
        t.loggedToday = !today.isEmpty
        t.streak = Streak(days: rows.map(\.eatenOn), since: since)
        return t
    }

    private static var ratingWords: [Int: String] {
        [1: "Awful", 2: "Rough", 3: "Bad", 4: "Meh", 5: "Okay", 6: "Fine", 7: "Good", 8: "Great", 9: "Excellent", 10: "Perfect"]
    }

    private func writeTile() async throws -> AppTile {
        let rows: [JournalRow] = try await api.rows("journal_entries?select=written_on,rating,body&written_on=gte.\(since)&order=written_on.desc")
        var t = AppTile(kind: .write)
        hub.journalToday = rows.first { $0.writtenOn == Day.string() }.map { JournalToday(rating: $0.rating, body: $0.body ?? "") }
        if let latest = rows.first {
            t.value = "\(latest.rating)"
            t.unit = "/10"
            t.note = "\(Day.label(latest.writtenOn)) · \(Self.ratingWords[latest.rating] ?? "")"
            t.loggedToday = latest.writtenOn == Day.string()
        } else {
            t.note = "no entries yet"
        }
        t.streak = Streak(days: rows.map(\.writtenOn), since: since)
        return t
    }

    // Pages read today when READ's page log exists (pages.sql), otherwise books finished this year.
    private func readTile() async throws -> AppTile {
        var books: [BookRow]
        do {
            books = try await api.rows("books?select=id,title,status,finished_on,total_pages")
        } catch APIError.server(_, let message) where message.contains("total_pages") {
            let older: [BookRowNoPages] = try await api.rows("books?select=id,title,status,finished_on")
            books = older.map { BookRow(id: $0.id, title: $0.title, status: $0.status, finishedOn: $0.finishedOn, totalPages: nil) }
        }
        let logs: [PagesRow]? = try? await api.rows("reading_log?select=book_id,read_on,pages")
        hub.pagesReady = logs != nil
        hub.books = books.filter { $0.status == "reading" }.map { b in
            ReadingBook(id: b.id, title: b.title, totalPages: b.totalPages, pagesRead: logs?.filter { $0.bookId == b.id }.reduce(0) { $0 + $1.pages } ?? 0)
        }
        var t = AppTile(kind: .read)
        if let logs {
            let pages = logs.filter { $0.readOn == Day.string() }.reduce(0) { $0 + $1.pages }
            t.value = "\(pages)"
            t.unit = pages == 1 ? "page" : "pages"
            t.note = hub.books.first.map { "today · \($0.title)" } ?? "today"
            t.loggedToday = pages > 0
            t.streak = Streak(days: logs.map(\.readOn).filter { $0 >= since }, since: since)
        } else {
            let year = String(Day.string().prefix(4))
            let finished = books.filter { $0.status == "finished" && ($0.finishedOn ?? "").hasPrefix(year) }.count
            t.value = "\(finished)"
            t.unit = finished == 1 ? "book" : "books"
            t.note = "finished in \(year)"
        }
        return t
    }
}

// The quick-log screens' saves. Each goes into the outbox, then uploads to that app's own table.
extension Store {
    func logWeight(_ value: Double, unit: String) {
        queue("events", [
            "occurred_at": ISO8601DateFormatter().string(from: Date()), "metric": "weight",
            "value": (value * 10).rounded() / 10, "unit": unit, "event_type": "measurement",
            "source": "watch", "source_id": UUID().uuidString.lowercased(), "context": ["area": "body"],
        ])
    }

    func logExpense(_ amount: Double, category: String, merchant: String) {
        queue("transactions", ["occurred_on": Day.string(), "amount": amount, "category": category, "merchant": merchant, "note": ""])
    }

    func logMeal(kcal: Int, protein: Int, carbs: Int, fat: Int, name: String, slot: String) {
        queue("meal_entries", ["eaten_on": Day.string(), "slot": slot, "name": name, "calories": kcal, "protein": protein, "carbs": carbs, "fat": fat, "source": "manual"])
    }

    // One entry per day: the rating replaces today's, and a new note is added under any note already there.
    func saveDay(rating: Int, note: String) {
        var fields: [String: Any] = ["written_on": Day.string(), "rating": rating, "updated_at": ISO8601DateFormatter().string(from: Date())]
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let before = hub.journalToday?.body ?? ""
            fields["body"] = before.isEmpty ? text : before + "\n\n" + text
        }
        queue("journal_entries", fields, onConflict: "user_id,written_on")
    }

    func logPages(_ pages: Int, book: UUID) {
        queue("reading_log", ["book_id": book.uuidString.lowercased(), "read_on": Day.string(), "pages": pages])
    }
}
