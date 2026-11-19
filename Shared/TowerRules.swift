import Foundation

/// 塔のルールの数値。CloudKit の `Config` で、アプリを更新せずに変えられる。読めないときは `standard`。
struct TowerConfig: Codable, Equatable {
    /// 直径(m) = この値 × 歩数^べき指数。1 万歩で 6m（実寸で地図や AR に出す）
    var diameterCoefficient = 0.06
    /// 歩数に対する、大きさの伸び方。1/3 は、体積が歩数に比例（伸びがゆるやか）。1 は、直径が歩数に比例（線形）。
    /// 0.5 は、その中間（面積が歩数に比例）
    var diameterExponent = 0.5
    /// 積む雪玉の直径は、いまの一番上の直径のこの倍以下
    var stackRatio = 0.8
    /// これより小さい雪玉は、おけない・積めない（m）
    var minBall = 1.0
    /// 土台にできる最小の大きさ（m）
    var minBase = 3.0
    /// 自分の位置から、塔の保存座標まで、この距離以内なら積める（m）
    var stackRadius = 50.0
    /// 完成していない塔が、この距離以内にあるときは、新しい土台をおけない（m）
    var baseSpacing = 50.0
    /// 位置を丸める格子の大きさ（m）
    var cellSize = 50.0
    /// 1 日に、おく・積める回数
    var dailyLimit = 20
    /// 位置の誤差が、これより大きいときは、おけない・積めない（m）
    var maxAccuracy = 50.0
    /// これより速く動いているときは、おけない・積めない（m/秒。車や電車を避ける）
    var maxSpeed = 4.0
    /// 通報がこの数以上ある塔は、見せない
    var reportHideCount = 3
    /// 自分の雪玉の上に積まれたとき、使った歩数をこの数で割ったポイント
    var coveredDivisor = 20
    /// 塔が完成したとき、使った歩数をこの数で割ったポイント
    var completionDivisor = 10
    /// 1 日にもらえるポイントの上限
    var dailyPointCap = 2_000
    /// 週の順位のごほうび（県 1 位、全国 1 位）
    var prefectureBonus = 1_000
    var nationalBonus = 5_000

    static let standard = TowerConfig()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TowerConfig()
        diameterCoefficient = try c.decodeIfPresent(Double.self, forKey: .diameterCoefficient) ?? d.diameterCoefficient
        diameterExponent = try c.decodeIfPresent(Double.self, forKey: .diameterExponent) ?? d.diameterExponent
        stackRatio = try c.decodeIfPresent(Double.self, forKey: .stackRatio) ?? d.stackRatio
        minBall = try c.decodeIfPresent(Double.self, forKey: .minBall) ?? d.minBall
        minBase = try c.decodeIfPresent(Double.self, forKey: .minBase) ?? d.minBase
        stackRadius = try c.decodeIfPresent(Double.self, forKey: .stackRadius) ?? d.stackRadius
        baseSpacing = try c.decodeIfPresent(Double.self, forKey: .baseSpacing) ?? d.baseSpacing
        cellSize = try c.decodeIfPresent(Double.self, forKey: .cellSize) ?? d.cellSize
        dailyLimit = try c.decodeIfPresent(Int.self, forKey: .dailyLimit) ?? d.dailyLimit
        maxAccuracy = try c.decodeIfPresent(Double.self, forKey: .maxAccuracy) ?? d.maxAccuracy
        maxSpeed = try c.decodeIfPresent(Double.self, forKey: .maxSpeed) ?? d.maxSpeed
        reportHideCount = try c.decodeIfPresent(Int.self, forKey: .reportHideCount) ?? d.reportHideCount
        coveredDivisor = try c.decodeIfPresent(Int.self, forKey: .coveredDivisor) ?? d.coveredDivisor
        completionDivisor = try c.decodeIfPresent(Int.self, forKey: .completionDivisor) ?? d.completionDivisor
        dailyPointCap = try c.decodeIfPresent(Int.self, forKey: .dailyPointCap) ?? d.dailyPointCap
        prefectureBonus = try c.decodeIfPresent(Int.self, forKey: .prefectureBonus) ?? d.prefectureBonus
        nationalBonus = try c.decodeIfPresent(Int.self, forKey: .nationalBonus) ?? d.nationalBonus
    }
}

/// 雪玉の大きさ。直径が、歩数の「べき指数」乗に比例する（標準は 0.5 乗）。
enum BallSize {
    static func diameter(steps: Int, config: TowerConfig = .standard) -> Double {
        config.diameterCoefficient * pow(Double(max(0, steps)), config.diameterExponent)
    }

    /// その大きさになる歩数（四捨五入）
    static func steps(forDiameter diameter: Double, config: TowerConfig = .standard) -> Int {
        guard diameter > 0 else { return 0 }
        return Int(pow(diameter / config.diameterCoefficient, 1 / config.diameterExponent).rounded())
    }
}

/// 塔に積まれた雪玉 1 つ。積んだ人が作り、あとから書きかえない。
struct Ball: Codable, Equatable, Identifiable {
    /// CloudKit の recordName
    var id: String
    var towerID: String
    /// 塔の中での順番（0 = 土台）
    var index: Int
    /// 直径（メートル）
    var diameter: Double
    /// この雪玉までを積んだときの塔の高さ（積んだ人の申告。順位に出すときは計算し直して確かめる）
    var cumHeight: Double
    var ownerHash: String
    /// 決まった言葉の組み合わせの名前
    var nick: String
    /// 飾り（仮）
    var look: Int
    var createdAt: Date
    var periodId: String
    var prefecture: Int
}

/// 塔。`balls` は、ルールを満たした有効な雪玉だけ（`TowerRules.validBalls` を通したもの）。
struct Tower: Equatable, Identifiable {
    var id: String
    /// 保存座標（土台をおいた場所と同じ格子の中の、ランダムな点）
    var location: GeoPoint
    var periodId: String
    var prefecture: Int
    var createdAt: Date
    var balls: [Ball]
    var reportCount = 0

    /// 高さ（雪玉の直径の合計）
    var height: Double { balls.reduce(0) { $0 + $1.diameter } }
    var top: Ball? { balls.last }
    var base: Ball? { balls.first }
    var lastBallAt: Date { balls.last?.createdAt ?? createdAt }

    /// 積んだ人たちの名前（重複なし、積んだ順）
    var nicks: [String] {
        var seen = Set<String>()
        return balls.compactMap { seen.insert($0.nick).inserted ? $0.nick : nil }
    }

    /// 次に積める雪玉の、最大の直径（完成していれば nil）
    func maxNextDiameter(config: TowerConfig = .standard) -> Double? {
        guard let top, !isClosed(config: config) else { return nil }
        return top.diameter * config.stackRatio
    }

    /// これ以上積めない（一番上が小さくなりすぎた）
    func isClosed(config: TowerConfig = .standard) -> Bool {
        guard let top else { return false }
        return top.diameter * config.stackRatio < config.minBall - TowerRules.epsilon
    }
}

/// 位置の質（ごまかしや、車での移動を避ける）
enum LocationIssue: Equatable {
    case unavailable
    case inaccurate
    case tooFast
    case spoofed
}

enum StackIssue: Equatable {
    /// 期間がちがう（週が終わった塔）
    case frozen
    case closed
    /// 一番上が自分の雪玉
    case ownTop
    case tooBig(max: Double)
    case tooSmall(min: Double)
    case tooFar(distance: Double)
    case dailyLimit
    case location(LocationIssue)
}

enum PlaceIssue: Equatable {
    case tooSmall(min: Double)
    case nearTower
    case dailyLimit
    case outsideJapan
    case unknownPrefecture
    case location(LocationIssue)
}

enum TowerRules {
    /// 大きさの比べるときの、ほんの少しの余裕（0.1 mm）
    static let epsilon = 1e-4

    /// 有効な雪玉の列を決める。`index` 順に並べ、先頭から、決まりを満たすものだけを取る。
    /// 同じ `index` が複数あれば、早く作られたほう（同時なら id が小さいほう）だけ有効。
    static func validBalls(_ raw: [Ball], config: TowerConfig = .standard) -> (valid: [Ball], rejected: [Ball]) {
        let sorted = raw.sorted { ($0.index, $0.createdAt, $0.id) < ($1.index, $1.createdAt, $1.id) }
        var valid: [Ball] = []
        var rejected: [Ball] = []
        for ball in sorted {
            if ball.index != valid.count {
                rejected.append(ball)
                continue
            }
            if ball.index == 0 {
                if ball.diameter + epsilon >= config.minBase { valid.append(ball) } else { rejected.append(ball) }
                continue
            }
            let top = valid[valid.count - 1]
            let fits = ball.diameter + epsilon >= config.minBall
                && ball.diameter <= top.diameter * config.stackRatio + epsilon
                && ball.ownerHash != top.ownerHash
            if fits { valid.append(ball) } else { rejected.append(ball) }
        }
        return (valid, rejected)
    }

    /// 雪玉の記録から塔を作る（有効なものだけ残す）
    static func tower(id: String, location: GeoPoint, periodId: String, prefecture: Int, createdAt: Date,
                      balls: [Ball], config: TowerConfig = .standard) -> Tower {
        Tower(id: id, location: location, periodId: periodId, prefecture: prefecture, createdAt: createdAt,
              balls: validBalls(balls, config: config).valid)
    }

    /// 塔に積めない理由（積めるなら nil）
    static func stackIssue(tower: Tower, carried: Double, owner: String, distance: Double?, usedToday: Int,
                           currentPeriod: String, config: TowerConfig = .standard) -> StackIssue? {
        if tower.periodId != currentPeriod { return .frozen }
        if tower.isClosed(config: config) { return .closed }
        if let top = tower.top, top.ownerHash == owner { return .ownTop }
        if let max = tower.maxNextDiameter(config: config), carried > max + epsilon { return .tooBig(max: max) }
        if carried + epsilon < config.minBall { return .tooSmall(min: config.minBall) }
        if let distance, distance > config.stackRadius { return .tooFar(distance: distance) }
        if distance == nil { return .location(.unavailable) }
        if usedToday >= config.dailyLimit { return .dailyLimit }
        return nil
    }

    /// 土台をおけない理由（おけるなら nil）。`towers` は、近くの塔。
    static func placeIssue(carried: Double, me: GeoPoint, towers: [Tower], currentPeriod: String, usedToday: Int,
                           config: TowerConfig = .standard) -> PlaceIssue? {
        if carried + epsilon < config.minBase { return .tooSmall(min: config.minBase) }
        let blocked = towers.contains {
            $0.periodId == currentPeriod && !$0.isClosed(config: config) && $0.location.distance(to: me) <= config.baseSpacing
        }
        if blocked { return .nearTower }
        if usedToday >= config.dailyLimit { return .dailyLimit }
        return nil
    }

    /// 位置が使えるか（ごまかし・車での移動・誤差）
    static func locationIssue(horizontalAccuracy: Double?, speed: Double?, simulated: Bool, accessory: Bool,
                              config: TowerConfig = .standard) -> LocationIssue? {
        guard let horizontalAccuracy, horizontalAccuracy >= 0 else { return .unavailable }
        if simulated || accessory { return .spoofed }
        if horizontalAccuracy > config.maxAccuracy { return .inaccurate }
        if let speed, speed >= 0, speed > config.maxSpeed { return .tooFast }
        return nil
    }

    /// 新しい雪玉の記録を作る
    static func makeBall(towerID: String, index: Int, diameter: Double, previousHeight: Double, ownerHash: String,
                         nick: String, look: Int = 0, now: Date, periodId: String, prefecture: Int) -> Ball {
        Ball(id: UUID().uuidString, towerID: towerID, index: index, diameter: diameter,
             cumHeight: previousHeight + diameter, ownerHash: ownerHash, nick: nick, look: look,
             createdAt: now, periodId: periodId, prefecture: prefecture)
    }
}

/// ポイント（飾りに使う）
enum PointRules {
    static func coveredReward(diameter: Double, config: TowerConfig = .standard) -> Int {
        BallSize.steps(forDiameter: diameter, config: config) / max(1, config.coveredDivisor)
    }

    static func completionReward(diameter: Double, config: TowerConfig = .standard) -> Int {
        BallSize.steps(forDiameter: diameter, config: config) / max(1, config.completionDivisor)
    }
}

/// 順位
enum Ranking {
    /// 高さが高い順。同じなら、最後の雪玉が早いほう、さらに同じなら id 順。
    static func sorted(_ towers: [Tower]) -> [Tower] {
        towers.sorted {
            if abs($0.height - $1.height) > 1e-9 { return $0.height > $1.height }
            if $0.lastBallAt != $1.lastBallAt { return $0.lastBallAt < $1.lastBallAt }
            return $0.id < $1.id
        }
    }

    static func top(_ towers: [Tower], prefecture: Int?, limit: Int) -> [Tower] {
        let filtered = prefecture.map { code in towers.filter { $0.prefecture == code } } ?? towers
        return Array(sorted(filtered).prefix(limit))
    }
}
