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
                if !store.workouts.isEmpty {
                    Section("Workouts") {
                        ForEach(store.workouts) { w in
                            NavigationLink(value: w) { WorkoutLinkRow(workout: w) }
                        }
                    }
                }
                Section {
                    NavigationLink { CardioView() } label: { CardioLinkRow() }
                    ForEach(ordered) { ex in
                        NavigationLink(value: ex) { ExerciseRow(exercise: ex) }
                    }
                } header: {
                    if !store.workouts.isEmpty { Text("Exercises") }
                }
                Section {
                    Button("Refresh") { Task { await store.load() } }
                    Button(store.pending.isEmpty && store.pendingCardio.isEmpty ? "Sign out" : "Sign out (unsynced logs will be lost)", role: .destructive) {
                        Task { await store.signOut() }
                    }
                } footer: {
                    if let email = store.email { Text(email) }
                }
            }
            .navigationTitle("GYM")
            .navigationDestination(for: Exercise.self) { LogSetView(exercise: $0) }
            .navigationDestination(for: Workout.self) { WorkoutView(workout: $0) }
            .navigationDestination(for: WorkoutStep.self) { step in
                if let ex = store.exercises.first(where: { $0.id == step.exerciseId }) {
                    LogSetView(exercise: ex, workout: step.workout)
                }
            }
            .overlay { if store.loading && store.exercises.isEmpty { ProgressView() } }
            .refreshable { await store.load() }
        }
    }
}

private struct WorkoutLinkRow: View {
    @Environment(Store.self) private var store
    let workout: Workout

    var body: some View {
        let list = store.exercises(in: workout)
        let done = list.filter { store.isDone($0) }.count
        VStack(alignment: .leading, spacing: 2) {
            Label(workout.name, systemImage: "list.bullet.clipboard").font(.headline).lineLimit(2)
            Group {
                if !list.isEmpty && done == list.count {
                    Text("Done today").foregroundStyle(.green)
                } else if done > 0 {
                    Text("\(done) of \(list.count) done today").foregroundStyle(.orange)
                } else {
                    Text("\(list.count) exercise\(list.count == 1 ? "" : "s")")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

private struct CardioLinkRow: View {
    @Environment(Store.self) private var store

    var body: some View {
        let today = store.todayCardio
        VStack(alignment: .leading, spacing: 2) {
            Label("Cardio", systemImage: "figure.run").font(.headline)
            Group {
                if store.cardioStartedAt != nil {
                    Text("Timer running").foregroundStyle(.orange)
                } else if let last = today.last {
                    Text("\(last.label) · \(formatWeight(today.reduce(0) { $0 + $1.minutes })) min today").foregroundStyle(.green)
                } else {
                    Text("Treadmill, bike, stairs and more")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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
