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
    var version: Int = 1
    var onboarded: Bool = false
    /// 初回の歩数同期（過去日のベースライン記録）が済んだか
    var initialized: Bool = false
    /// 今転がしている雪玉の歩数
    var rollingSteps: Int = 0
    /// これまでに雪玉に加算した歩数の合計
    var totalSteps: Int = 0
    /// 日付ごとに「すでに加算した歩数」。差分だけ足すので二重加算も取りこぼしも起きない。
    var credited: [String: Int] = [:]
    var snowmen: [Snowman] = []
    var createdAt: Date = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, initialized, rollingSteps, totalSteps, credited, snowmen, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        rollingSteps = try c.decodeIfPresent(Int.self, forKey: .rollingSteps) ?? 0
        totalSteps = try c.decodeIfPresent(Int.self, forKey: .totalSteps) ?? 0
        credited = try c.decodeIfPresent([String: Int].self, forKey: .credited) ?? [:]
        snowmen = try c.decodeIfPresent([Snowman].self, forKey: .snowmen) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
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
        rollingSteps += gained
        totalSteps += gained
        prune()
        return gained
    }

    /// テストやデバッグ用に歩数を直接足す
    mutating func addBonus(steps: Int) {
        guard steps > 0 else { return }
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

    // MARK: 雪だるまの完成

    var canComplete: Bool { rollingSteps >= SizeTier.minimumSteps }

    var currentTier: SizeTier? { SizeTier.tier(forSteps: rollingSteps) }

    var nextTier: SizeTier? { SizeTier.allCases.first { $0.minSteps > rollingSteps } }

    mutating func complete<G: RandomNumberGenerator>(using g: inout G, now: Date = Date()) -> CompletionResult? {
        guard let tier = currentTier else { return nil }
        let snowman = SnowmanFactory.make(tier: tier, steps: rollingSteps, date: now, using: &g)
        let isNew = !hasMade(species: snowman.species, tier: snowman.tier)
        snowmen.append(snowman)
        rollingSteps = 0
        return CompletionResult(snowman: snowman, isNewKind: isNew)
    }

    mutating func complete(now: Date = Date()) -> CompletionResult? {
        var g = SystemRandomNumberGenerator()
        return complete(using: &g, now: now)
    }

    // MARK: 図鑑

    func hasMade(species: Species, tier: SizeTier) -> Bool {
        snowmen.contains { $0.species == species && $0.tier == tier }
    }

    func latest(species: Species, tier: SizeTier) -> Snowman? {
        snowmen
            .filter { $0.species == species && $0.tier == tier }
            .max { $0.madeAt < $1.madeAt }
    }

    var discoveredKindCount: Int {
        Set(snowmen.map { $0.kindKey }).count
    }

    /// 図鑑のマス数（種類×出現できるサイズ）
    static var totalKindCount: Int {
        Species.allCases.reduce(0) { sum, species in
            sum + SizeTier.allCases.filter { $0 >= species.rarity.minTier }.count
        }
    }
}
