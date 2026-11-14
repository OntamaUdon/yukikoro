import Foundation
import CoreGraphics

/// 歩数の表示用フォーマット（3桁区切り）
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// 長さの表示（1m未満は cm、それ以上は m、km、万km）
func formatLength(meters: Double) -> String {
    if meters < 1 { return "約\(Int((meters * 100).rounded()))cm" }
    if meters < 1_000 { return String(format: "約%.1fm", meters) }
    if meters < 10_000 { return String(format: "約%.2fkm", meters / 1_000) }
    if meters < 1e9 { return "約\(formatSteps(Int((meters / 1_000).rounded())))km" }
    return "約\(formatSteps(Int((meters / 1e7).rounded())))万km"
}

private func superscript(_ n: Int) -> String {
    let digits: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"]
    return String(String(n).map { digits[$0] ?? $0 })
}

/// 重さの表示（g・kg・t、とても重いときは 10 のべき乗）
func formatMass(kg: Double) -> String {
    if kg < 1 { return "約\(String(format: "%.0f", kg * 1_000))g" }
    if kg < 10 { return String(format: "約%.1fkg", kg) }
    if kg < 1_000 { return "約\(Int(kg.rounded()))kg" }
    if kg < 1e5 { return String(format: "約%.1ft", kg / 1_000) }
    if kg < 1e7 { return "約" + formatSteps(Int((kg / 1_000).rounded())) + "t" }
    let exponent = Int(floor(log10(kg)))
    let mantissa = kg / pow(10, Double(exponent))
    return String(format: "約%.1f×10", mantissa) + superscript(exponent) + "kg"
}

/// 力の表示（N・kN・MN、とても大きいときは 10 のべき乗）
func formatForce(_ newtons: Double) -> String {
    if newtons < 1_000 { return String(format: "%.0fN", newtons) }
    if newtons < 1e6 { return String(format: "%.1fkN", newtons / 1_000) }
    if newtons < 1e9 { return String(format: "%.1fMN", newtons / 1e6) }
    let exponent = Int(floor(log10(newtons)))
    let mantissa = newtons / pow(10, Double(exponent))
    return String(format: "%.1f×10", mantissa) + superscript(exponent) + "N"
}
