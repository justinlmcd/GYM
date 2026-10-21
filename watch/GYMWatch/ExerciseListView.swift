import SwiftUI

// Your exercises from GYM. Ones you've trained today float to the top.
struct ExerciseListView: View {
    @Environment(Store.self) private var store

    private var ordered: [Exercise] {
        let done = store.exercises.filter { !store.todaySets($0).isEmpty }
        return done + store.exercises.filter { store.todaySets($0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.pending.isEmpty {
                    Label("\(store.pending.count) set\(store.pending.count == 1 ? "" : "s") waiting to sync", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                if store.exercises.isEmpty && !store.loading {
                    Text("No exercises yet. Add them in the GYM app first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(ordered) { ex in
                    NavigationLink(value: ex) { ExerciseRow(exercise: ex) }
                }
                Section {
                    Button("Refresh") { Task { await store.load() } }
                    Button(store.pending.isEmpty ? "Sign out" : "Sign out (unsynced sets will be lost)", role: .destructive) {
                        Task { await store.signOut() }
                    }
                } footer: {
                    if let email = store.email { Text(email) }
                }
            }
            .navigationTitle("GYM")
            .navigationDestination(for: Exercise.self) { LogSetView(exercise: $0) }
            .overlay { if store.loading && store.exercises.isEmpty { ProgressView() } }
            .refreshable { await store.load() }
        }
    }
}

private struct ExerciseRow: View {
    @Environment(Store.self) private var store
    let exercise: Exercise

    var body: some View {
        let today = store.todaySets(exercise).count
        let next = store.suggestion(exercise).weight
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).font(.headline).lineLimit(2)
            Group {
                if today > 0 {
                    Text("\(today) of \(exercise.targetSets) sets today").foregroundStyle(.green)
                } else if let next {
                    Text("Next \(formatWeight(next)) \(exercise.unit) · \(exercise.targetSets)×\(exercise.targetReps)")
                } else {
                    Text("\(exercise.targetSets)×\(exercise.targetReps) · not started")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
