import Foundation

/// 雪玉を押すチームの力
struct PushTeam: Equatable {
    /// 押す力（ニュートン）
    var force: Double
    /// 1歩で転がる距離（メートル）
    var reach: Double
    /// 重さに比例する力の割合（重力そうち。雪玉の重さ × この割合だけ、勝手に転がる向きの力がはたらく）
    var lift: Double
}

/// 雪玉の物理モデル。
///
/// 1歩ごとに、チームが雪玉を `d` メートル転がす。雪玉は通り道の雪（溝）を拾って重くなる。
///
/// - 抵抗: 柔らかい雪で転がす抵抗は重さに比例する。`F_res = μ·M·g`
/// - 押す力: `F_max = チームの力 + 重力そうちの力(∝ M)`
/// - 1歩で転がる距離: `d = L / (1 + (F_res / F_max)^p)`。重くなるほど急にゆっくりになるが、止まりはしない（上限なし）。
/// - 拾う雪: `dM = η·ρ雪·S(r)·d`。S(r) は、深さ `t`（雪が玉にくっつく厚さの限界）まで沈んだ溝の断面積。
/// - 重力で集める雪: ボンディ降着 `dM = 4πG²ρ/v³ · M² · Δt`（1歩ごとに、重いほど加速度的に増える）。
/// - 圧縮: 重くなると自重で密度が上がる。雪玉の密度 300〜500 kg/m³（固めるほど高い）→ 重すぎると電子の縮退圧（白色矮星）で半径が縮む。
/// - 半径がシュワルツシルト半径 `2GM/c²` より小さくなったら、ブラックホール。
enum SnowPhysics {
    static let gravity = 9.8
    /// 柔らかい雪を転がす抵抗の係数
    static let rollingResistance = 0.3
    /// 溝の雪がくっつく割合
    static let pickupRate = 0.8
    /// 降り積もったままの雪の密度（kg/m³）
    static let looseSnowDensity = 100.0
    /// 1回転で雪がくっつく厚さの限界（メートル）
    static let adhesionDepth = 0.02
    /// 押す力が足りなくなったときの落ち込み方（大きいほど急）
    static let softness = 4.0
    /// 雪玉の密度（ゆるい／いちばん固めたとき）
    static let looseBallDensity = 300.0
    static let packedBallDensity = 500.0
    /// 1歩にかかる時間（秒）
    static let stepSeconds = 0.7
    static let bigG = 6.674e-11
    static let lightSpeed = 2.998e8
    /// ボンディ降着の係数（相対速度1m/s、まわりの雪の密度100kg/m³、1歩ぶん）
    static let accretionRate = 4 * Double.pi * bigG * bigG * 100 * stepSeconds
    /// 1歩で重力が集める雪の上限（雪玉の重さに対する割合）
    static let accretionCap = 0.001
    /// 縮退圧で決まる半径（r · M^(1/3)）
    static let degenerateScale = 1.32e17
    static let blend = 4.0
    /// 最初の半径（メートル）
    static let initialRadius = 0.01
    /// 最初から持っている力（自分の手）
    static let bareHandForce = 60.0

    // MARK: 大きさ

    static func density(pack: Double) -> Double {
        looseBallDensity + (packedBallDensity - looseBallDensity) * min(1, max(0, pack))
    }

    static func initialMass(pack: Double = 0) -> Double {
        4.0 / 3.0 * Double.pi * pow(initialRadius, 3) * density(pack: pack)
    }

    /// 重さ（kg）から半径（メートル）。軽いうちは密度一定の球、重くなると縮退圧で縮む。
    static func radius(mass: Double, pack: Double) -> Double {
        let m = max(mass, 1e-9)
        let incompressible = cbrt(3 * m / (4 * Double.pi * density(pack: pack)))
        let degenerate = degenerateScale / cbrt(m)
        return pow(pow(incompressible, -blend) + pow(degenerate, -blend), -1 / blend)
    }

    static func schwarzschildRadius(mass: Double) -> Double { 2 * bigG * mass / (lightSpeed * lightSpeed) }

    static func isBlackHole(mass: Double, pack: Double) -> Bool {
        radius(mass: mass, pack: pack) <= schwarzschildRadius(mass: mass)
    }

    /// 平均の密度（kg/m³）
    static func meanDensity(mass: Double, pack: Double) -> Double {
        let r = radius(mass: mass, pack: pack)
        return mass / (4.0 / 3.0 * Double.pi * r * r * r)
    }

    // MARK: 転がす

    /// 半径 r の球が、深さ min(t, r) まで沈んだときの溝の断面積（m²）
    static func groove(radius r: Double) -> Double {
        let d = min(adhesionDepth, r)
        let ratio = d / r
        if ratio < 1e-4 {
            return 4 * 2.0.squareRoot() / 3 * r.squareRoot() * pow(d, 1.5)
        }
        return r * r * acos(1 - ratio) - (r - d) * max(0, 2 * r * d - d * d).squareRoot()
    }

    /// いまの重さで、1歩に転がる距離（メートル）
    static func pushDistance(mass: Double, team: PushTeam) -> Double {
        let resistance = rollingResistance * gravity * mass
        let available = team.force + team.lift * mass * gravity
        guard available > 0 else { return 0 }
        let ratio = resistance / available
        return team.reach / (1 + pow(ratio, softness))
    }

    /// 押す力の余裕（1 = 軽く転がる、0 に近いほど押せない）
    static func easiness(mass: Double, team: PushTeam) -> Double {
        guard team.reach > 0 else { return 0 }
        return pushDistance(mass: mass, team: team) / team.reach
    }

    /// 1歩ぶん進める
    static func step(mass: Double, pack: Double, team: PushTeam) -> Double {
        var m = mass
        var left = 1.0
        var guardCount = 0
        while left > 1e-12 && guardCount < 200 {
            guardCount += 1
            let r = radius(mass: m, pack: pack)
            let d = pushDistance(mass: m, team: team)
            let rate = pickupRate * looseSnowDensity * groove(radius: r) * d
            if rate <= 0 || !rate.isFinite { break }
            let fraction = min(left, 0.05 * m / rate)
            m += rate * fraction
            left -= fraction
        }
        m += min(accretionRate * m * m, accretionCap * m)
        return m
    }

    /// 歩数ぶん進める。ブラックホールになったらそこで止める。
    static func advance(mass: Double, pack: Double, team: PushTeam, steps: Int) -> (mass: Double, blackHole: Bool) {
        var m = mass
        guard steps > 0 else { return (m, isBlackHole(mass: m, pack: pack)) }
        for _ in 0..<steps {
            m = step(mass: m, pack: pack, team: team)
            if isBlackHole(mass: m, pack: pack) { return (m, true) }
        }
        return (m, false)
    }

    /// 固める 1 回ぶん（残りの 0.4% ずつ。半径がほんの少し縮む）
    static func tappedPack(_ pack: Double) -> Double {
        pack + (1 - pack) * 0.004
    }
}
