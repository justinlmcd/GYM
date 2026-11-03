import Foundation
import HealthKit

// SLEEP: your nights from Apple Health, uploaded to the sleep_nights table without logging anything.
// The watch records sleep when Sleep tracking is on (Health app → Sleep); this reads the last week of it
// whenever today's numbers load, including the morning background refresh, and uploads any night that's new or changed.

// One night, keyed by the morning you woke up.
nonisolated struct NightSummary: Hashable {
    let night: String
    let bedtime: Date
    let wake: Date
    let asleepMin: Int
    let awakeMin: Int
    let coreMin: Int?
    let deepMin: Int?
    let remMin: Int?
    let restingHR: Double?
}

nonisolated enum SleepReader {
    private static let health = HKHealthStore()

    // Asks once to read Sleep and resting heart rate. Apple never says whether reading was refused;
    // a refusal just returns no nights.
    static func requestAccess() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await health.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate)])
            return true
        } catch {
            return false
        }
    }

    static func nights(days: Int = 8) async throws -> [NightSummary] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let range = HKQuery.predicateForSamples(withStart: start, end: Date())
        let samples = try await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
            sortDescriptors: [SortDescriptor(\.startDate)]).result(for: health)
        let heart = (try? await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate), predicate: range)],
            sortDescriptors: [SortDescriptor(\.startDate)]).result(for: health)) ?? []
        var resting: [String: Double] = [:]
        for s in heart { resting[Day.string(s.endDate)] = s.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }

        // A night belongs to the morning it ends on; sleep ending after 6pm counts toward the next morning.
        let byNight = Dictionary(grouping: samples) { Day.string($0.endDate.addingTimeInterval(6 * 3600)) }
        let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                      HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        return byNight.compactMap { night, all in
            let asleep = all.filter { asleepValues.contains($0.value) }
            let asleepMin = minutes(asleep)
            guard asleepMin >= 30, let wake = asleep.map(\.endDate).max(), let bed = all.map(\.startDate).min() else { return nil }
            let stage = { (v: HKCategoryValueSleepAnalysis) in all.filter { $0.value == v.rawValue } }
            let hasStages = all.contains { [HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains($0.value) }
            return NightSummary(
                night: night, bedtime: bed, wake: wake, asleepMin: asleepMin, awakeMin: minutes(stage(.awake)),
                coreMin: hasStages ? minutes(stage(.asleepCore)) : nil,
                deepMin: hasStages ? minutes(stage(.asleepDeep)) : nil,
                remMin: hasStages ? minutes(stage(.asleepREM)) : nil,
                restingHR: resting[night])
        }.sorted { $0.night < $1.night }
    }

    // Minutes covered by the samples, counting overlaps once (the iPhone and the watch can both record the same night).
    private static func minutes(_ samples: [HKCategorySample]) -> Int {
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for s in samples.sorted(by: { $0.startDate < $1.startDate }) {
            if let c = current, s.startDate <= c.end {
                current = (c.start, max(c.end, s.endDate))
            } else {
                if let c = current { total += c.end.timeIntervalSince(c.start) }
                current = (s.startDate, s.endDate)
            }
        }
        if let c = current { total += c.end.timeIntervalSince(c.start) }
        return Int((total / 60).rounded())
    }
}

extension Store {
    private static let sleepSentKey = "sleepSent"

    // Uploads the last week of nights that are new or changed since they were last sent.
    func syncSleep() async {
        guard signedIn, await SleepReader.requestAccess(), let nights = try? await SleepReader.nights() else { return }
        var sent = UserDefaults.standard.dictionary(forKey: Self.sleepSentKey) as? [String: String] ?? [:]
        let iso = ISO8601DateFormatter()
        var queued = false
        for n in nights {
            let mark = "\(n.asleepMin)|\(n.awakeMin)|\(n.coreMin ?? -1)|\(n.deepMin ?? -1)|\(n.remMin ?? -1)|\(Int(n.restingHR ?? 0))|\(Int(n.bedtime.timeIntervalSince1970))|\(Int(n.wake.timeIntervalSince1970))"
            guard sent[n.night] != mark else { continue }
            var fields: [String: Any] = [
                "night": n.night, "bedtime": iso.string(from: n.bedtime), "wake_time": iso.string(from: n.wake),
                "asleep_min": n.asleepMin, "awake_min": n.awakeMin, "source": "watch", "updated_at": iso.string(from: Date()),
            ]
            if let v = n.coreMin { fields["core_min"] = v }
            if let v = n.deepMin { fields["deep_min"] = v }
            if let v = n.remMin { fields["rem_min"] = v }
            if let v = n.restingHR { fields["resting_hr"] = (v * 10).rounded() / 10 }
            queue("sleep_nights", fields, onConflict: "user_id,night", upload: false)
            sent[n.night] = mark
            queued = true
        }
        // Remember only the last few weeks.
        let cutoff = Day.daysAgo(30)
        UserDefaults.standard.set(sent.filter { $0.key >= cutoff }, forKey: Self.sleepSentKey)
        if queued { await flush() }
    }
}
