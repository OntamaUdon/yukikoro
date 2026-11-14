import Foundation
import HealthKit

/// ヘルスケアから日別の歩数を読む。
enum HealthSteps {
    private static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async {
        guard isAvailable else { return }
        let type = HKQuantityType(.stepCount)
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
        } catch {
            // 許可されなくても動作は続ける（歩数が増えないだけ）
        }
    }

    /// 今日を含む直近 `days` 日の歩数合計。キーは DayKey 形式。取得できなければ空。
    static func dailySteps(days: Int) async -> [String: Int] {
        guard isAvailable, days > 0 else { return [:] }
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else { return [:] }

        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return await withCheckedContinuation { (continuation: CheckedContinuation<[String: Int], Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfToday,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, _ in
                var output: [String: Int] = [:]
                results?.enumerateStatistics(from: start, to: now) { statistics, _ in
                    let value = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    output[DayKey.key(for: statistics.startDate)] = Int(value)
                }
                continuation.resume(returning: output)
            }
            store.execute(query)
        }
    }
}
