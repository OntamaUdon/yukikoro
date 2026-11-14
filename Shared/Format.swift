import Foundation
import CoreGraphics

enum BallScale {
    /// 歩数に対する雪玉の大きさ（0〜1）。2万歩で最大。
    static func fraction(_ steps: Int) -> Double {
        min(1, max(0, (Double(steps) / 20_000).squareRoot()))
    }
}

/// 歩数の表示用フォーマット（3桁区切り）
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
