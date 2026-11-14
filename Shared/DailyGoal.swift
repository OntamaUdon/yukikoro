import Foundation

/// 1日の歩数の目標
enum DailyGoal {
    static let steps = 8_000

    /// 目標に対する割合（0〜1 を超えてもよい）
    static func fraction(steps walked: Int) -> Double {
        Double(max(0, walked)) / Double(steps)
    }
}
