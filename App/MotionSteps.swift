import Foundation
import CoreMotion

/// ヘルスケアが使えない／歩数が取れないときの代替（直近7日分まで取得できる）。
enum MotionSteps {
    static func dailySteps(days: Int) async -> [String: Int]? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let status = CMPedometer.authorizationStatus()
        if status == .denied || status == .restricted { return nil }

        let pedometer = CMPedometer()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var output: [String: Int] = [:]

        for offset in 0..<min(days, 7) {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let end: Date
            if offset == 0 {
                end = Date()
            } else {
                end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            }
            let steps: Int? = await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
                pedometer.queryPedometerData(from: start, to: end) { data, _ in
                    continuation.resume(returning: data?.numberOfSteps.intValue)
                }
            }
            if let steps {
                output[DayKey.key(for: start)] = steps
            }
        }
        return output.isEmpty ? nil : output
    }
}
