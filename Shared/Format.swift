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
/// 現実には、雪の深さの上限や押せる重さの限界で頭打ちになるので、
/// 上限 R_max に向けてなめらかに頭打ちにする（ソフトミニマム）。
enum BallScale {
    /// 指数 q（β = 0.8 のとき 2.2）。2 に近いほど接地幅が半径に比例、3 に近いほど接地幅が一定。
    static let q = 2.2
    /// 歩数 0 のときの半径（場面の単位）
    static let r0 = 0.28
    /// 頭打ちの半径
    static let maxRadius = 1.35
    /// 係数。S/M/L/XL の4段階（500・3,000・8,000・15,000歩）の見た目の差が偏らないよう決めた値
    static let k = 1.416e-4
    /// 頭打ちの鋭さ
    static let sharpness = 4.0

    /// 頭打ち前の半径
    static func rawRadius(steps: Int) -> Double {
        let s = max(0, Double(steps))
        return pow(pow(r0, q) + k * s, 1 / q)
    }

    /// 半径（場面の単位）
    static func radius(steps: Int) -> Double {
        let raw = rawRadius(steps: steps)
        return pow(pow(raw, -sharpness) + pow(maxRadius, -sharpness), -1 / sharpness)
    }

    /// 大きさの割合（0〜1）。ウィジェットなどの表示用。
    static func fraction(_ steps: Int) -> Double {
        let low = radius(steps: 0)
        return min(1, max(0, (radius(steps: steps) - low) / (maxRadius - low)))
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
