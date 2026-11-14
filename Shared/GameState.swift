import Foundation

enum DayKey {
    /// "2026-11-14" 形式の日付キー（端末のカレンダー基準）
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// ゲームの全状態。UI から独立していて、単体テストできる。
struct GameState: Codable, Equatable {
    var version: Int = 3
    var onboarded: Bool = false
    /// 初回の歩数同期（過去日のベースライン記録）が済んだか
    var initialized: Bool = false
    /// 雪玉の歩数。上限はなく、歩いた分だけ増え続ける。
    var rollingSteps: Int = 0
    /// これまでに雪玉に加算した歩数の合計
    var totalSteps: Int = 0
    /// 日付ごとに「すでに加算した歩数」。差分だけ足すので二重加算も取りこぼしも起きない。
    var credited: [String: Int] = [:]
    var createdAt: Date = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, initialized, rollingSteps, reserveSteps, totalSteps, credited, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        // 以前は上限を超えた歩数を「持ち越し」にしていたので、いまの雪玉に足して引き継ぐ
        let carried = try c.decodeIfPresent(Int.self, forKey: .reserveSteps) ?? 0
        rollingSteps = (try c.decodeIfPresent(Int.self, forKey: .rollingSteps) ?? 0) + carried
        totalSteps = try c.decodeIfPresent(Int.self, forKey: .totalSteps) ?? 0
        credited = try c.decodeIfPresent([String: Int].self, forKey: .credited) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(onboarded, forKey: .onboarded)
        try c.encode(initialized, forKey: .initialized)
        try c.encode(rollingSteps, forKey: .rollingSteps)
        try c.encode(totalSteps, forKey: .totalSteps)
        try c.encode(credited, forKey: .credited)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: 歩数の加算

    /// 日別の歩数合計を受け取り、まだ加算していない分だけ雪玉に足す。加算した歩数を返す。
    /// - 初回は過去日をベースラインとして記録し、当日分から加算する。
    /// - 歩数が減った日（ヘルスケア側の修正など）は無視する。
    @discardableResult
    mutating func apply(daily: [String: Int], todayKey: String) -> Int {
        guard !daily.isEmpty else { return 0 }
        if !initialized {
            for (key, value) in daily where key != todayKey {
                credited[key] = value
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
        addSteps(gained)
        prune()
        return gained
    }

    /// テストやデバッグ用に歩数を直接足す
    mutating func addBonus(steps: Int) {
        guard steps > 0 else { return }
        addSteps(steps)
    }

    private mutating func addSteps(_ steps: Int) {
        rollingSteps += steps
        totalSteps += steps
    }

    private mutating func prune() {
        guard credited.count > 40 else { return }
        for key in credited.keys.sorted().dropLast(40) {
            credited[key] = nil
        }
    }

    func creditedSteps(on key: String) -> Int { credited[key] ?? 0 }

    // MARK: 雪玉の大きさ

    /// 雪玉の半径（メートル）
    var radius: Double { BallScale.radius(steps: rollingSteps) }

    /// 雪玉の直径（メートル）
    var diameter: Double { 2 * radius }
}
