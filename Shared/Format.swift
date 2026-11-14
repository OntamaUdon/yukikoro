import Foundation
import CoreGraphics

/// 雪玉の大きさ（歩数 → 半径）の物理モデル。
///
/// 転がすと通り道の雪が付着する。付着する体積は dV = (接地幅 w) × (拾う厚み h) × (距離 ds)。
/// 重い雪玉ほど深く沈んで接地幅が広がるので、同じ距離で付く雪の量は雪玉が大きいほど増える。
/// 接地幅が r^β に比例するとすると、r^q ∝ s（q = 3 − β）となり、半径は次の形になる:
///
///     r(s) = (r0^q + k·s)^(1/q)     （q = 2〜3。q が小さいほど後半の伸びが強い）
///
/// 収束する上限（漸近線）は無く、半径は距離^0.4 で伸び、体積は距離よりも速く増える。
/// 上限は設けていないので、歩いた分だけ、どこまでも大きくなる。
enum BallScale {
    /// 指数 q（β = 0.5 のとき 2.5。接地幅が √r に比例する想定）
    static let q = 2.5
    /// 歩数 0 のときの半径（メートル。1cm）
    static let r0 = 0.01
    /// 係数。S/M/L/XL の4段階（500・3,000・8,000・15,000歩）の見た目の差が偏らないよう決めた値
    static let k = 1.329e-4

    /// 半径（メートル）。上限はなく、歩くほどどこまでも大きくなる。
    static func radius(steps: Int) -> Double {
        let s = Double(max(0, steps))
        return pow(pow(r0, q) + k * s, 1 / q)
    }

    /// 直径がこの長さ（メートル）になる歩数
    static func steps(forDiameter d: Double) -> Int {
        let r = d / 2
        guard r > r0 else { return 0 }
        return Int(((pow(r, q) - pow(r0, q)) / k).rounded(.up))
    }

    /// 直径（メートル）。形の最大幅で測る。
    static func diameter(steps: Int, extent: Float) -> Double {
        2 * radius(steps: steps) * Double(extent)
    }

    /// 体積（半径³に比例。比較用）
    static func volume(radius r: Double) -> Double { 4.0 / 3.0 * Double.pi * r * r * r }
}

/// 歩数の表示用フォーマット（3桁区切り）
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// 長さの表示（1m未満は cm、それ以上は m）
func formatLength(meters: Double) -> String {
    if meters < 1 { return "約\(Int((meters * 100).rounded()))cm" }
    if meters < 1_000 { return String(format: "約%.1fm", meters) }
    return String(format: "約%.2fkm", meters / 1_000)
}
