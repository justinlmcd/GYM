import SwiftUI
import WatchKit

// Log one exercise: tap weight or reps, turn the Digital Crown, press Log set.
// Swipe a set left to delete it.
struct LogSetView: View {
    @Environment(Store.self) private var store
    let exercise: Exercise

    private enum Field { case weight, reps }
    @FocusState private var focus: Field?
    @State private var weight: Double = 0
    @State private var reps: Double = 8
    @State private var seeded = false

    var body: some View {
        let sets = store.todaySets(exercise)
        let suggestion = store.suggestion(exercise)
        List {
            Section {
                HStack(spacing: 6) {
                    Dial(value: formatWeight(weight), unit: exercise.unit, active: focus == .weight)
                        .focusable()
                        .focused($focus, equals: .weight)
                        .digitalCrownRotation($weight, from: 0, through: 2000, by: exercise.step,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onTapGesture { focus = .weight }
                    Dial(value: String(Int(reps)), unit: "reps", active: focus == .reps)
                        .focusable()
                        .focused($focus, equals: .reps)
                        .digitalCrownRotation($reps, from: 0, through: 100, by: 1,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onTapGesture { focus = .reps }
                }
                .listRowBackground(Color.clear)

                Button {
                    store.log(exercise, weight: weight, reps: Int(reps))
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Text("Log set \(sets.count + 1)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            } footer: {
                Text(suggestion.why)
            }

            if !sets.isEmpty {
                Section {
                    ForEach(sets.reversed()) { set in
                        SetRow(set: set, unit: exercise.unit,
                               waiting: store.pending.contains { $0.id == set.id },
                               hit: set.reps >= exercise.targetReps)
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await store.delete(set) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("Today · \(sets.count)/\(exercise.targetSets)")
                        Spacer()
                        if let last = store.lastLoggedAt {
                            Text(last, style: .timer).monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .onAppear {
            guard !seeded else { return }
            seeded = true
            // Start from your last set today, else GYM's suggested weight and the target reps.
            if let last = sets.last {
                weight = last.weight
                reps = Double(last.reps)
            } else {
                weight = suggestion.weight ?? 0
                reps = Double(exercise.targetReps)
            }
            focus = .weight
        }
    }
}

private struct Dial: View {
    let value: String
    let unit: String
    let active: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(active ? 0.15 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.orange : .clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Turn the Digital Crown to change")
    }
}

private struct SetRow: View {
    let set: LoggedSet
    let unit: String
    let waiting: Bool
    let hit: Bool

    var body: some View {
        HStack {
            Text("Set \(set.setNo)").foregroundStyle(.secondary)
            Spacer()
            Text("\(formatWeight(set.weight)) × \(set.reps)")
                .monospacedDigit()
                .foregroundStyle(hit ? Color.green : Color.primary)
            if waiting {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Waiting to sync")
            }
        }
    }
}
