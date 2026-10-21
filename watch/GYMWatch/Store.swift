import Foundation
import Observation

// Everything the screens show. Sets are saved on the watch first, then uploaded;
// anything logged without a connection waits here and uploads on the next try.
@MainActor
@Observable
final class Store {
    private let api = Supabase()
    private static let pendingKey = "pendingSets"

    var signedIn = false
    var email: String?
    var exercises: [Exercise] = []
    var history: [LoggedSet] = []
    var pending: [LoggedSet] = []
    var loading = false
    var error: String?
    var lastLoggedAt: Date?
    private var flushing = false

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([LoggedSet].self, from: data) {
            pending = saved
        }
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
            try await api.delete(setId: set.id)
            history.removeAll { $0.id == set.id }
        } catch {
            handle(error)
        }
    }

    func flush() async {
        guard !flushing, signedIn else { return }
        flushing = true
        defer { flushing = false }
        // Sets logged while this runs are picked up too.
        var tried = Set<UUID>()
        while let set = pending.first(where: { !tried.contains($0.id) }) {
            tried.insert(set.id)
            do {
                try await api.insert(set)
                if pending.contains(where: { $0.id == set.id }) {
                    pending.removeAll { $0.id == set.id }
                    history.append(set)
                } else {
                    try? await api.delete(setId: set.id) // Deleted on the watch while it was uploading.
                }
            } catch let error where APIError.isTransient(error) {
                return // No connection: keep the rest queued.
            } catch {
                handle(error)
                if !signedIn { return }
                pending.removeAll { $0.id == set.id } // Rejected by the server (e.g. exercise deleted on the web).
            }
            savePending()
        }
    }

    private func handle(_ error: Error) {
        if case APIError.signedOut = error {
            signedIn = false
            email = nil
            self.error = "Signed out. Sign in again."
        } else if APIError.isTransient(error) {
            self.error = "No connection. Sets are saved on the watch."
        } else {
            self.error = error.localizedDescription
        }
    }

    private func savePending() {
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }
}
