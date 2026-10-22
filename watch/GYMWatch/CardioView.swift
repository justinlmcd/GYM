import SwiftUI
import WatchKit

// Log cardio: pick the type, run the timer or dial in minutes, add calories and speed
// from the machine if you want, press Log cardio. Swipe a session left to delete it.
struct CardioView: View {
    @Environment(Store.self) private var store

    private enum Field { case minutes, calories, speed }
    @FocusState private var focus: Field?
    @State private var kind: CardioKind = .treadmill
    @State private var minutes: Double = 20
    @State private var calories: Double = 0
    @State private var speed: Double = 0
    @State private var unit = CardioKind.treadmill.defaultUnit

    // Treadmill and bike speeds take decimals; levels and step or stroke rates are whole numbers.
    private var speedStep: Double { unit == "mph" || unit == "km/h" ? 0.1 : 1 }

    var body: some View {
        List {
            if store.cardioMissing {
                Text("Cardio isn't set up yet. Run cardio.sql in Supabase once, then refresh.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Section {
                Picker("Type", selection: $kind) {
                    ForEach(CardioKind.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: kind) { _, new in
                    unit = new.defaultUnit
                    speed = 0
                }

                if let started = store.cardioStartedAt {
                    Button {
                        minutes = max(1, (Date().timeIntervalSince(started) / 60).rounded())
                        store.setCardioTimer(nil)
                        WKInterfaceDevice.current().play(.stop)
                    } label: {
                        HStack {
                            Text(started, style: .timer)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .monospacedDigit()
                            Spacer()
                            Text("Stop").bold()
                        }
                    }
                    .tint(.red)
                } else {
                    Button {
                        store.setCardioTimer(Date())
                        WKInterfaceDevice.current().play(.start)
                    } label: {
                        Label("Start timer", systemImage: "stopwatch")
                    }
                }
            }

            Section {
                HStack(spacing: 6) {
                    Dial(value: String(Int(minutes)), unit: "min", active: focus == .minutes)
                        .focusable()
                        .focused($focus, equals: .minutes)
                        .digitalCrownRotation($minutes, from: 1, through: 600, by: 1,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onTapGesture { focus = .minutes }
                    Dial(value: calories > 0 ? String(Int(calories)) : "–", unit: "kcal", active: focus == .calories)
                        .focusable()
                        .focused($focus, equals: .calories)
                        .digitalCrownRotation($calories, from: 0, through: 3000, by: 5,
                                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onTapGesture { focus = .calories }
                }
                .listRowBackground(Color.clear)

                HStack(spacing: 6) {
                    Dial(value: speed > 0 ? (speedStep < 1 ? String(format: "%.1f", speed) : String(Int(speed))) : "–",
                         unit: "speed", active: focus == .speed)
                        .focusable()
                        .focused($focus, equals: .speed)
                        .digitalCrownRotation($speed, from: 0, through: 300, by: speedStep,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                        .onTapGesture { focus = .speed }
                    Button {
                        let units = CardioKind.units
                        unit = units[((units.firstIndex(of: unit) ?? 0) + 1) % units.count]
                        speed = 0
                    } label: {
                        VStack(spacing: 0) {
                            Text(unit).font(.headline)
                            Text("change").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Speed unit \(unit). Change")
                }
                .listRowBackground(Color.clear)

                Button {
                    store.logCardio(kind: kind, minutes: Int(minutes), speed: speed,
                                    speedUnit: unit, calories: Int(calories))
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Text("Log cardio")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .disabled(store.cardioMissing)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Calories and speed are optional. Leave them at – to skip.")
            }

            let today = store.todayCardio
            if !today.isEmpty {
                Section("Today") {
                    ForEach(today.reversed()) { session in
                        CardioRow(session: session, waiting: store.pendingCardio.contains { $0.id == session.id })
                            .swipeActions {
                                Button(role: .destructive) {
                                    Task { await store.delete(session) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Cardio")
    }
}

private struct CardioRow: View {
    let session: CardioSession
    let waiting: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label)
                Text(details).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if waiting {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Waiting to sync")
            }
        }
    }

    private var details: String {
        var parts = ["\(formatWeight(session.minutes)) min"]
        if let c = session.calories { parts.append("\(formatWeight(c)) kcal") }
        if let s = session.speed { parts.append("\(formatWeight(s)) \(session.speedUnit)") }
        return parts.joined(separator: " · ")
    }
}
