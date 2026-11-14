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
/// 式そのものには収束する上限（漸近線）は無く、半径は距離^0.4 で伸び、体積は距離よりも速く増える。
/// ゲームとしては「達成上限」（`SizeTier.maxSteps` = 30,000歩）で最大サイズに到達して止まる。
/// 画面からはみ出さないよう、大きくなったらカメラ側（雪玉を置く距離）を引いて見せる。
enum BallScale {
    /// 指数 q（β = 0.5 のとき 2.5。接地幅が √r に比例する想定）
    static let q = 2.5
    /// 歩数 0 のときの半径（場面の単位）
    static let r0 = 0.28
    /// 係数。S/M/L/XL の4段階（500・3,000・8,000・15,000歩）の見た目の差が偏らないよう決めた値
    static let k = 1.329e-4

    /// 半径（場面の単位）。達成上限（`SizeTier.maxSteps`）の歩数で最大になり、以降は変わらない。
    static func radius(steps: Int) -> Double {
        let s = Double(min(max(0, steps), SizeTier.maxSteps))
        return pow(pow(r0, q) + k * s, 1 / q)
    }

    /// 大きさの割合（0〜1 未満）。
    static func fraction(_ steps: Int) -> Double {
        1 - exp(-(radius(steps: steps) - r0) / 1.0)
    }

    /// 体積（半径³に比例。比較用）
    static func volume(radius r: Double) -> Double { 4.0 / 3.0 * Double.pi * r * r * r }

    /// 画面の幅に対する雪玉の見かけの半径（0〜1）。大きくなるほどゆっくり増えて 0.85 に近づく。
    /// 横画角 42° のとき、距離 d での画面の半幅は d × tan(21°) ≒ 0.384 d。
    static func apparentFraction(radius r: Double, baseDistance: Double) -> Double {
        let natural = r / (baseDistance * 0.384)
        let softLimit = 0.71
        if natural <= softLimit { return natural }
        return softLimit + 0.14 * (1 - exp(-(natural - softLimit) / 0.25))
    }

    /// 雪玉を置く距離。半径が大きいほど遠くへ置いて、画面からはみ出さないようにする。
    static func distance(radius r: Double, baseDistance: Double) -> Double {
        r / (0.384 * apparentFraction(radius: r, baseDistance: baseDistance))
    }
}

/// 歩数の表示用フォーマット（3桁区切り）
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
