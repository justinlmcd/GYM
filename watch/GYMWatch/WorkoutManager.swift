import Foundation
import HealthKit
import SwiftUI

// Runs a real Apple Workout while you train: heart rate and calories live on the watch,
// and the finished workout saved to Apple Health so it counts toward your Activity rings.
// Needs the HealthKit capability on the watch target; without it, starting says so and the timers work as before.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    private let health = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var running = false
    private(set) var isCardio = false
    private(set) var label = ""
    private(set) var startDate: Date?
    private(set) var heartRate: Double = 0
    private(set) var calories: Double = 0
    private(set) var meters: Double = 0 // distance the watch measured (running, walking, cycling)
    var lastSummary: String?
    var error: String?

    func startStrength(_ name: String) async {
        await start(.traditionalStrengthTraining, label: name, cardio: false)
    }

    func startCardio(_ kind: CardioKind) async {
        await start(kind.activityType, label: kind.label, cardio: true)
    }

    private func start(_ activity: HKWorkoutActivityType, label: String, cardio: Bool) async {
        guard !running else { return }
        error = nil
        lastSummary = nil
        guard HKHealthStore.isHealthDataAvailable() else { error = "Apple Health isn't available on this watch."; return }
        do {
            try await health.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType(),
                       HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)])
            let config = HKWorkoutConfiguration()
            config.activityType = activity
            config.locationType = .indoor
            let session = try HKWorkoutSession(healthStore: health, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            self.session = session
            self.builder = builder
            self.label = label
            isCardio = cardio
            startDate = now
            heartRate = 0
            calories = 0
            meters = 0
            running = true
        } catch {
            self.error = "Couldn't start an Apple Workout: \(error.localizedDescription)"
        }
    }

    // Ends the workout, saves it to Apple Health, and returns how long it ran, the calories it burned
    // and the distance it measured (0 when it measured none).
    @discardableResult
    func end() async -> (minutes: Double, calories: Double, km: Double)? {
        guard running, let session, let builder, let startDate else { return nil }
        let now = Date()
        session.end()
        do {
            try await builder.endCollection(at: now)
            _ = try await builder.finishWorkout()
        } catch {
            self.error = "The workout ended but couldn't be saved to Apple Health: \(error.localizedDescription)"
        }
        let minutes = now.timeIntervalSince(startDate) / 60
        let result = (minutes: minutes, calories: calories, km: meters / 1000)
        lastSummary = "\(label) saved to Apple Health · \(Int(minutes.rounded())) min · \(Int(calories.rounded())) kcal"
        self.session = nil
        self.builder = nil
        self.startDate = nil
        running = false
        return result
    }

    fileprivate func update(heartRate: Double?, calories: Double?, meters: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let calories { self.calories = calories }
        if let meters { self.meters = meters }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate, HKWorkoutSessionDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var bpm: Double?, kcal: Double?, meters: Double?
        if collectedTypes.contains(HKQuantityType(.heartRate)) {
            bpm = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        }
        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)) {
            kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        for type in [HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling)] where collectedTypes.contains(type) {
            if let m = workoutBuilder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) { meters = max(meters ?? 0, m) }
        }
        Task { @MainActor in self.update(heartRate: bpm, calories: kcal, meters: meters) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.error = "The Apple Workout stopped: \(message)" }
    }
}

extension CardioKind {
    // The Apple Workout each of GYM's cardio types records as.
    var activityType: HKWorkoutActivityType {
        switch self {
        case .treadmill: return .running
        case .stairmaster: return .stairClimbing
        case .bike: return .cycling
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .other: return .other
        }
    }
}

// The live line during a workout: time, heart rate and calories.
struct LiveWorkoutBar: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.running, let start = workout.startDate {
            HStack(spacing: 8) {
                Text(start, style: .timer).monospacedDigit().font(.headline)
                Spacer(minLength: 2)
                Label("\(Int(workout.heartRate))", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(Int(workout.heartRate)) beats per minute")
                Text("\(Int(workout.calories)) kcal").foregroundStyle(.orange)
            }
            .font(.footnote.monospacedDigit())
        }
    }
}

// Start or end an Apple strength workout, for GYM's screen and a saved workout's screen.
struct StrengthWorkoutControl: View {
    @Environment(WorkoutManager.self) private var workout
    let name: String

    var body: some View {
        if workout.running {
            LiveWorkoutBar()
            if !workout.isCardio {
                Button(role: .destructive) {
                    Task { await workout.end() }
                } label: {
                    Label("End workout", systemImage: "stop.fill")
                }
            }
        } else {
            Button {
                Task { await workout.startStrength(name) }
            } label: {
                Label("Start workout", systemImage: "figure.strengthtraining.traditional")
            }
            .tint(.green)
        }
        if let summary = workout.lastSummary, !workout.running {
            Text(summary).font(.footnote).foregroundStyle(.green)
        }
        if let error = workout.error {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }
}
