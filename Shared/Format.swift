import Foundation

/// 歩数の表示用フォーマット（3桁区切り）
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// 大きさの表示（1m 未満は cm、それ以上は m）
func formatLength(meters: Double) -> String {
    if meters < 1 { return "\(Int((meters * 100).rounded()))cm" }
    if meters < 100 { return String(format: "%.2fm", meters) }
    return String(format: "%.0fm", meters)
}

/// 距離の表示（メートル）
func formatDistance(meters: Double) -> String {
    if meters < 1_000 { return "\(Int(meters.rounded()))m" }
    return String(format: "%.1fkm", meters / 1_000)
}
