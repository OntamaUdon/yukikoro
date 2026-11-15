import Foundation

/// 自分の状態（端末の中にだけ保存）。歩数の台帳と、持っている雪玉、ポイント、1 日の回数。
struct PlayerState: Codable, Equatable {
    var version = 1
    var onboarded = false
    /// 初回の歩数同期（過去日のベースライン記録）が済んだか
    var initialized = false
    /// 日付ごとに「すでに加算した歩数」。差分だけ足すので二重加算も取りこぼしも起きない。
    var credited: [String: Int] = [:]
    /// アプリをはじめて開いたとき、すでに歩いていた歩数（日付ごと）。これは数えない。
    var baseline: [String: Int] = [:]
    /// はじめて開いてから、歩いた歩数の合計
    var totalSteps = 0
    /// 最後におく・積んだときの `totalSteps`。持っている雪玉の歩数 = `totalSteps` − この値。
    var stepsAtLastUse = 0
    var nickAdjective = 0
    var nickAnimal = 0
    var points = 0
    var pointsToday = 0
    var pointsDay = ""
    /// 今日、おく・積んだ回数
    var usedToday = 0
    var usedDay = ""
    /// 上に積まれて、ポイントをもらった雪玉の id
    var rewardedBalls: [String] = []
    /// 完成して、ポイントをもらった塔の id
    var rewardedTowers: [String] = []
    var placedCount = 0
    var stackedCount = 0
    /// 最後に殿堂を見た期間
    var seenHallPeriod = ""
    var createdAt = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, initialized, credited, baseline, totalSteps, stepsAtLastUse
        case nickAdjective, nickAnimal, points, pointsToday, pointsDay, usedToday, usedDay
        case rewardedBalls, rewardedTowers, placedCount, stackedCount, seenHallPeriod, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerState()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? d.onboarded
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? d.initialized
        credited = try c.decodeIfPresent([String: Int].self, forKey: .credited) ?? d.credited
        baseline = try c.decodeIfPresent([String: Int].self, forKey: .baseline) ?? d.baseline
        totalSteps = try c.decodeIfPresent(Int.self, forKey: .totalSteps) ?? d.totalSteps
        stepsAtLastUse = try c.decodeIfPresent(Int.self, forKey: .stepsAtLastUse) ?? d.stepsAtLastUse
        nickAdjective = try c.decodeIfPresent(Int.self, forKey: .nickAdjective) ?? d.nickAdjective
        nickAnimal = try c.decodeIfPresent(Int.self, forKey: .nickAnimal) ?? d.nickAnimal
        points = try c.decodeIfPresent(Int.self, forKey: .points) ?? d.points
        pointsToday = try c.decodeIfPresent(Int.self, forKey: .pointsToday) ?? d.pointsToday
        pointsDay = try c.decodeIfPresent(String.self, forKey: .pointsDay) ?? d.pointsDay
        usedToday = try c.decodeIfPresent(Int.self, forKey: .usedToday) ?? d.usedToday
        usedDay = try c.decodeIfPresent(String.self, forKey: .usedDay) ?? d.usedDay
        rewardedBalls = try c.decodeIfPresent([String].self, forKey: .rewardedBalls) ?? d.rewardedBalls
        rewardedTowers = try c.decodeIfPresent([String].self, forKey: .rewardedTowers) ?? d.rewardedTowers
        placedCount = try c.decodeIfPresent(Int.self, forKey: .placedCount) ?? d.placedCount
        stackedCount = try c.decodeIfPresent(Int.self, forKey: .stackedCount) ?? d.stackedCount
        seenHallPeriod = try c.decodeIfPresent(String.self, forKey: .seenHallPeriod) ?? d.seenHallPeriod
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? d.createdAt
    }

    // MARK: 歩数の加算

    /// 日別の歩数合計を受け取り、まだ加算していない分だけ足す。加算した歩数を返す。
    /// - 初回は、その時点までに歩いていた歩数（今日の分も）をベースラインとして記録し、数えない。以降に歩いた分から加算する。
    /// - 歩数が減った日（ヘルスケア側の修正など）は無視する。
    @discardableResult
    mutating func apply(daily: [String: Int]) -> Int {
        guard !daily.isEmpty else { return 0 }
        if !initialized {
            for (key, value) in daily {
                credited[key] = value
                baseline[key] = value
            }
            initialized = true
        }
        var gained = 0
        for (key, value) in daily {
            let previous = credited[key] ?? 0
            if value > previous {
                gained += value - previous
                credited[key] = value
            }
        }
        totalSteps += gained
        prune()
        return gained
    }

    /// テスト用に歩数を直接足す
    mutating func addDebugSteps(_ steps: Int) {
        guard steps > 0 else { return }
        totalSteps += steps
    }

    private mutating func prune() {
        guard credited.count > 40 else { return }
        for key in credited.keys.sorted().dropLast(40) {
            credited[key] = nil
            baseline[key] = nil
        }
    }

    /// アプリをはじめて開いてから、その日に歩いた歩数
    func walkedSteps(on key: String) -> Int { max(0, (credited[key] ?? 0) - (baseline[key] ?? 0)) }

    // MARK: 持っている雪玉

    /// 持っている雪玉の歩数
    var carriedSteps: Int { max(0, totalSteps - stepsAtLastUse) }

    func carriedDiameter(config: TowerConfig = .standard) -> Double {
        BallSize.diameter(steps: carriedSteps, config: config)
    }

    /// けずって小さくする（大きくは戻せない）。けずった歩数は戻らない。
    mutating func shave(to diameter: Double, config: TowerConfig = .standard) {
        let target = max(0, min(diameter, carriedDiameter(config: config)))
        stepsAtLastUse = totalSteps - BallSize.steps(forDiameter: target, config: config)
    }

    /// おいた・積んだあと: 持っている雪玉は、ゼロから育て直し
    mutating func markUsed(dayKey: String) {
        rollDay(dayKey)
        stepsAtLastUse = totalSteps
        usedToday += 1
    }

    /// 日が変わったら、1 日の回数・ポイントをリセット
    mutating func rollDay(_ key: String) {
        if usedDay != key {
            usedDay = key
            usedToday = 0
        }
        if pointsDay != key {
            pointsDay = key
            pointsToday = 0
        }
    }

    /// ポイントを足す（1 日の上限まで）。足した数を返す。
    @discardableResult
    mutating func addPoints(_ amount: Int, dayKey: String, dailyCap: Int) -> Int {
        rollDay(dayKey)
        let room = max(0, dailyCap - pointsToday)
        let added = max(0, min(amount, room))
        points += added
        pointsToday += added
        return added
    }

    var nickname: String { Nickname.make(adjective: nickAdjective, animal: nickAnimal) }
}
