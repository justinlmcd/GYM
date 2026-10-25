import SwiftUI

// A workout from GYM: its exercises in order, each with today's sets.
// The first one you haven't finished is marked as up next.
struct WorkoutView: View {
    @Environment(Store.self) private var store
    let workout: Workout

    var body: some View {
        let list = store.exercises(in: workout)
        let done = list.filter { store.isDone($0) }.count
        let next = list.first { !store.isDone($0) }
        List {
            Section {
                ForEach(list) { ex in
                    NavigationLink(value: WorkoutStep(workout: workout, exerciseId: ex.id)) {
                        WorkoutRow(exercise: ex, upNext: ex.id == next?.id)
                    }
                }
            } header: {
                Text(list.isEmpty ? "No exercises" : done == list.count ? "Workout done" : "\(done) of \(list.count) done")
            } footer: {
                if list.count < workout.exerciseIds.count {
                    Text("Some exercises in this workout were deleted or archived in GYM.")
                } else if list.isEmpty {
                    Text("Add exercises to this workout in GYM.")
                }
            }
        }
        .navigationTitle(workout.name)
    }
}

private struct WorkoutRow: View {
    @Environment(Store.self) private var store
    let exercise: Exercise
    let upNext: Bool

    var body: some View {
        let count = store.todaySets(exercise).count
        let done = count >= exercise.targetSets
        let weight = store.suggestion(exercise).weight
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : upNext ? "play.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : upNext ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.headline).lineLimit(2)
                Text(detail(count: count, done: done, weight: weight))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : upNext ? "Up next" : "")
    }

    private func detail(count: Int, done: Bool, weight: Double?) -> String {
        if done { return "\(count) sets done" }
        let sets = "\(count)/\(exercise.targetSets) sets"
        guard let weight else { return sets }
        return "\(sets) · \(formatWeight(weight)) \(exercise.unit)"
    }
}
