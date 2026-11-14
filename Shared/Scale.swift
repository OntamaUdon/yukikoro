import Foundation
import CoreGraphics

/// 大きさを比べるための目印（人・木・山など）
struct ScaleReference: Equatable {
    let name: String
    /// 高さ（メートル）
    let height: Double
    /// 絵（SF Symbols）
    let symbol: String

    static let all: [ScaleReference] = [
        ScaleReference(name: "はっぱ", height: 0.06, symbol: "leaf.fill"),
        ScaleReference(name: "ボール", height: 0.22, symbol: "soccerball"),
        ScaleReference(name: "ねこ", height: 0.30, symbol: "cat.fill"),
        ScaleReference(name: "ひと", height: 1.7, symbol: "figure.stand"),
        ScaleReference(name: "き", height: 8, symbol: "tree.fill"),
        ScaleReference(name: "ビル", height: 40, symbol: "building.2.fill"),
        ScaleReference(name: "たかいビル", height: 100, symbol: "building.fill"),
        ScaleReference(name: "タワー", height: 333, symbol: "antenna.radiowaves.left.and.right"),
        ScaleReference(name: "くも", height: 1_000, symbol: "cloud.fill"),
        ScaleReference(name: "やま", height: 3_776, symbol: "mountain.2.fill"),
        ScaleReference(name: "ひこうき", height: 10_000, symbol: "airplane"),
    ]

    /// 直径がこれより大きくなる、次の目印
    static func next(after diameter: Double) -> ScaleReference? {
        all.first { $0.height > diameter }
    }
}

/// 場面の縮尺（1メートルが何点か）。
/// 小さいうちは雪玉が育つのがそのまま見え、画面いっぱいになったら、雪玉は同じ大きさのまま、まわりの目印が小さくなっていく（引いて見せる）。
enum StageScale {
    /// 画面の幅に対する、雪玉の最大の直径
    static let maxBallFraction: CGFloat = 0.62
    /// この直径（メートル）で、雪玉が最大の大きさになる
    static let fullSizeDiameter: Double = 0.5

    static func pixelsPerMeter(diameter: Double, width: CGFloat) -> CGFloat {
        let ballMax = width * maxBallFraction
        let atFull = ballMax / CGFloat(fullSizeDiameter)
        return min(atFull, ballMax / CGFloat(max(diameter, 1e-9)))
    }

    /// 目印の見え方（0〜1）。小さすぎても、大きすぎても、うすくなって消える。`limitPixels` は、雪玉が最大のときの幅。
    static func opacity(forHeightPixels px: CGFloat, limitPixels: CGFloat) -> Double {
        func smooth(_ x: CGFloat, _ a: CGFloat, _ b: CGFloat) -> Double {
            let t = min(1, max(0, (x - a) / (b - a)))
            return Double(t * t * (3 - 2 * t))
        }
        let rising = smooth(px, 16, 32)
        let falling = 1 - smooth(px, limitPixels * 0.50, limitPixels * 0.66)
        return min(rising, falling)
    }
}
