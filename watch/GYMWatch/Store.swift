import Foundation
import Observation

// Everything the screens show. Sets and cardio are saved on the watch first, then uploaded;
// anything logged without a connection waits here and uploads on the next try.
@MainActor
@Observable
final class Store {
    private let api = Supabase(url: Config.supabaseURL, key: Config.publishableKey)
    private static let pendingKey = "pendingSets"
    private static let pendingCardioKey = "pendingCardio"
    private static let cardioStartKey = "cardioStartedAt"

    var signedIn = false
    var email: String?
    var exercises: [Exercise] = []
    var history: [LoggedSet] = []
    var pending: [LoggedSet] = []
    var cardio: [CardioSession] = []
    var pendingCardio: [CardioSession] = []
    var cardioMissing = false
    private(set) var cardioStartedAt: Date?
    var loading = false
    var error: String?
    var lastLoggedAt: Date?
    private var flushing = false

    init() {
        pending = Self.restore(Self.pendingKey)
        pendingCardio = Self.restore(Self.pendingCardioKey)
        let started = UserDefaults.standard.double(forKey: Self.cardioStartKey)
        if started > 0 { cardioStartedAt = Date(timeIntervalSince1970: started) }
    }

    func start() async {
        email = await api.email
        signedIn = email != nil
        if signedIn { await load() }
    }

    func signIn(email: String, password: String) async {
        error = nil
        do {
            try await api.signIn(email: email, password: password)
            self.email = email
            signedIn = true
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        await api.signOut()
        signedIn = false
        email = nil
        exercises = []
        history = []
        pending = []
        cardio = []
        pendingCardio = []
        setCardioTimer(nil)
        savePending()
    }

    func load() async {
        loading = true
        defer { loading = false }
        await flush()
        do {
            async let ex = api.exercises()
            async let sets = api.sets(since: Day.daysAgo(120))
            exercises = try await ex
            history = try await sets
            error = nil
        } catch {
            handle(error)
            return
        }
        // Cardio is optional in GYM (cardio.sql), so a missing table only affects the cardio screen.
        do {
            cardio = try await api.cardio(on: Day.string())
            cardioMissing = false
        } catch APIError.server(_, let message) where message.contains("schema cache") || message.contains("does not exist") {
            cardioMissing = true
        } catch {
            handle(error)
        }
    }

    // MARK: - Reading

    private var allSets: [LoggedSet] {
        let pendingIds = Set(pending.map(\.id))
        return history.filter { !pendingIds.contains($0.id) } + pending
    }

    func todaySets(_ ex: Exercise) -> [LoggedSet] {
        let today = Day.string()
        return allSets.filter { $0.exerciseId == ex.id && $0.performedOn == today }.sorted { $0.setNo < $1.setNo }
    }

    var todayCardio: [CardioSession] {
        let today = Day.string()
        let pendingIds = Set(pendingCardio.map(\.id))
        return (cardio.filter { !pendingIds.contains($0.id) } + pendingCardio).filter { $0.performedOn == today }
    }

    // GYM's progressive-overload rule, using the last session before today so the
    // suggestion doesn't move mid-workout: hit every target set for target reps
    // at the top weight → add the increment, otherwise repeat the weight.
    func suggestion(_ ex: Exercise) -> (weight: Double?, why: String) {
        let today = Day.string()
        let past = allSets.filter { $0.exerciseId == ex.id && $0.performedOn < today }
        guard let lastDay = past.map(\.performedOn).max() else {
            return (nil, "First session. Start light.")
        }
        let rows = past.filter { $0.performedOn == lastDay }
        let top = rows.map(\.weight).max() ?? 0
        let atTop = rows.filter { $0.weight == top }
        let hit = atTop.count >= ex.targetSets && atTop.allSatisfy { $0.reps >= ex.targetReps }
        if hit { return (top + ex.increment, "Hit \(ex.targetSets)×\(ex.targetReps) last time. +\(formatWeight(ex.increment)).") }
        let done = atTop.map { String($0.reps) }.joined(separator: "/")
        return (top, "Last: \(done) at \(formatWeight(top)).")
    }

    // MARK: - Writing

    func log(_ ex: Exercise, weight: Double, reps: Int) {
        let next = (todaySets(ex).map(\.setNo).max() ?? 0) + 1
        let set = LoggedSet(id: UUID(), exerciseId: ex.id, performedOn: Day.string(),
                            setNo: min(next, 50), weight: max(0, weight), reps: max(0, reps))
        pending.append(set)
        savePending()
        lastLoggedAt = Date()
        Task { await flush() }
    }

    func delete(_ set: LoggedSet) async {
        if pending.contains(where: { $0.id == set.id }) {
            pending.removeAll { $0.id == set.id }
            savePending()
            return
        }
        do {
            try await api.delete(from: "sets", id: set.id)
            history.removeAll { $0.id == set.id }
        } catch {
            handle(error)
        }
    }

    // Calories or speed of 0 are saved as blank, like leaving them empty on the web.
    func logCardio(kind: CardioKind, minutes: Int, speed: Double, speedUnit: String, calories: Int) {
        let session = CardioSession(id: UUID(), performedOn: Day.string(), kind: kind.rawValue,
                                    minutes: Double(min(max(minutes, 1), 1440)),
                                    speed: speed > 0 ? (speed * 10).rounded() / 10 : nil, speedUnit: speedUnit,
                                    calories: calories > 0 ? Double(calories) : nil)
        pendingCardio.append(session)
        savePending()
        setCardioTimer(nil)
        Task { await flush() }
    }

    // The cardio timer survives closing the app, so you can start it and put your wrist down.
    func setCardioTimer(_ start: Date?) {
        cardioStartedAt = start
        if let start { UserDefaults.standard.set(start.timeIntervalSince1970, forKey: Self.cardioStartKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.cardioStartKey) }
    }

    func delete(_ session: CardioSession) async {
        if pendingCardio.contains(where: { $0.id == session.id }) {
            pendingCardio.removeAll { $0.id == session.id }
            savePending()
            return
        }
        do {
            try await api.delete(from: "cardio", id: session.id)
            cardio.removeAll { $0.id == session.id }
        } catch {
            handle(error)
        }
    }

    func flush() async {
        guard !flushing, signedIn else { return }
        flushing = true
        defer { flushing = false }
        guard await upload(\.pending, table: "sets", onSaved: { self.history.append($0) }) else { return }
        _ = await upload(\.pendingCardio, table: "cardio", onSaved: { self.cardio.append($0) })
    }

    // Uploads one queue in order. Returns false when the connection dropped or the
    // sign-in expired, so the rest waits for the next try.
    private func upload<T: Identifiable & Codable & Sendable>(
        _ queue: ReferenceWritableKeyPath<Store, [T]>, table: String, onSaved: (T) -> Void
    ) async -> Bool where T.ID == UUID {
        // Rows logged while this runs are picked up too.
        var tried = Set<UUID>()
        while let row = self[keyPath: queue].first(where: { !tried.contains($0.id) }) {
            tried.insert(row.id)
            do {
                try await api.insert(row, into: table)
                if self[keyPath: queue].contains(where: { $0.id == row.id }) {
                    self[keyPath: queue].removeAll { $0.id == row.id }
                    onSaved(row)
                } else {
                    try? await api.delete(from: table, id: row.id) // Deleted on the watch while it was uploading.
                }
            } catch let error where APIError.isTransient(error) {
                return false // No connection: keep the rest queued.
            } catch {
                handle(error)
                if !signedIn { return false }
                self[keyPath: queue].removeAll { $0.id == row.id } // Rejected by the server (e.g. exercise deleted on the web).
            }
            savePending()
        }
        return true
    }

    private func handle(_ error: Error) {
        if case APIError.signedOut = error {
            signedIn = false
            email = nil
            self.error = "Signed out. Sign in again."
        } else if APIError.isTransient(error) {
            self.error = "No connection. Your log is saved on the watch."
        } else {
            self.error = error.localizedDescription
        }
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
        if let data = try? JSONEncoder().encode(pendingCardio) {
            UserDefaults.standard.set(data, forKey: Self.pendingCardioKey)
        }
    }

    private static func restore<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([T].self, from: data) else { return [] }
        return saved
    }
}
