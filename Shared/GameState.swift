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
    var version: Int = 4
    var onboarded: Bool = false
    /// 初回の歩数同期（過去日のベースライン記録）が済んだか
    var initialized: Bool = false
    /// 雪玉の重さ（kg）
    var mass: Double = SnowPhysics.initialMass()
    /// どれだけ固めたか（0 = ふわふわ、1 = いちばん固い）
    var pack: Double = 0
    /// 持っているもの（買い物の id → 数）
    var owned: [String: Int] = [:]
    /// 買い物に使った歩数
    var spent: Int = 0
    /// 倒した木の道の数（いま雪玉がいる道の番号）
    var stage: Int = 0
    /// 持っている資材（木を倒すと手に入る）
    var materials: Int = 0
    /// これまでに加算した歩数の合計
    var totalSteps: Int = 0
    /// 日付ごとに「すでに加算した歩数」。差分だけ足すので二重加算も取りこぼしも起きない。
    var credited: [String: Int] = [:]
    /// アプリをはじめて開いたとき、すでに歩いていた歩数（日付ごと）。これは数えない。
    var baseline: [String: Int] = [:]
    /// これまでで一番大きかったときの直径（メートル）。買い物の解放に使う。
    var peakDiameter: Double = 2 * SnowPhysics.initialRadius
    /// 今日の最初の雪玉の重さ（今日ふえた分を見せるため）
    var dayKey: String = ""
    var dayStartMass: Double = SnowPhysics.initialMass()
    /// 最後に画面で見せた重さと固さ（開いたときの変化のアニメーション用）
    var seenMass: Double? = nil
    var seenPack: Double? = nil
    /// ブラックホールになったか
    var blackHole: Bool = false
    var createdAt: Date = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, initialized, mass, pack, owned, spent, stage, materials, totalSteps, credited, baseline
        case peakDiameter, seenMass, seenPack, dayKey, dayStartMass, blackHole, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 以前の版（歩数だけで大きさが決まっていた）の保存データは、雪玉は最初からにして、歩数だけ引き継ぐ
        let savedVersion = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        totalSteps = try c.decodeIfPresent(Int.self, forKey: .totalSteps) ?? 0
        credited = try c.decodeIfPresent([String: Int].self, forKey: .credited) ?? [:]
        baseline = try c.decodeIfPresent([String: Int].self, forKey: .baseline) ?? [:]
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        if savedVersion >= 4 {
            version = savedVersion
            mass = try c.decodeIfPresent(Double.self, forKey: .mass) ?? SnowPhysics.initialMass()
            pack = try c.decodeIfPresent(Double.self, forKey: .pack) ?? 0
            owned = try c.decodeIfPresent([String: Int].self, forKey: .owned) ?? [:]
            spent = try c.decodeIfPresent(Int.self, forKey: .spent) ?? 0
            materials = try c.decodeIfPresent(Int.self, forKey: .materials) ?? 0
            if let savedStage = try c.decodeIfPresent(Int.self, forKey: .stage) {
                stage = savedStage
            } else {
                // 木の道ができる前の保存データ: いまの重さまでの道は、倒したことにする
                var k = 0
                while Lane.capMass(stage: k, pack: pack) < mass { k += 1 }
                stage = k
            }
            peakDiameter = try c.decodeIfPresent(Double.self, forKey: .peakDiameter) ?? 2 * SnowPhysics.initialRadius
            dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? ""
            dayStartMass = try c.decodeIfPresent(Double.self, forKey: .dayStartMass) ?? mass
            seenMass = try c.decodeIfPresent(Double.self, forKey: .seenMass)
            seenPack = try c.decodeIfPresent(Double.self, forKey: .seenPack)
            blackHole = try c.decodeIfPresent(Bool.self, forKey: .blackHole) ?? false
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(onboarded, forKey: .onboarded)
        try c.encode(initialized, forKey: .initialized)
        try c.encode(mass, forKey: .mass)
        try c.encode(pack, forKey: .pack)
        try c.encode(owned, forKey: .owned)
        try c.encode(spent, forKey: .spent)
        try c.encode(stage, forKey: .stage)
        try c.encode(materials, forKey: .materials)
        try c.encode(totalSteps, forKey: .totalSteps)
        try c.encode(credited, forKey: .credited)
        try c.encode(baseline, forKey: .baseline)
        try c.encode(peakDiameter, forKey: .peakDiameter)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(dayStartMass, forKey: .dayStartMass)
        try c.encodeIfPresent(seenMass, forKey: .seenMass)
        try c.encodeIfPresent(seenPack, forKey: .seenPack)
        try c.encode(blackHole, forKey: .blackHole)
        try c.encode(createdAt, forKey: .createdAt)
    }

    // MARK: 歩数の加算

    /// 日別の歩数合計を受け取り、まだ加算していない分だけ足す。加算した歩数を返す。
    /// - 初回は、その時点までに歩いていた歩数（今日の分も）をベースラインとして記録し、数えない。以降に歩いた分から加算する。
    /// - 歩数が減った日（ヘルスケア側の修正など）は無視する。
    @discardableResult
    mutating func apply(daily: [String: Int], todayKey: String) -> Int {
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
        rollDay(todayKey)
        addSteps(gained)
        prune()
        return gained
    }

    /// テストやデバッグ用に歩数を直接足す
    mutating func addBonus(steps: Int) {
        guard steps > 0 else { return }
        rollDay(DayKey.key(for: Date()))
        addSteps(steps)
    }

    /// 日が変わったら、その日の最初の雪玉の重さを覚える
    private mutating func rollDay(_ key: String) {
        guard dayKey != key else { return }
        dayKey = key
        dayStartMass = mass
    }

    /// 今日、雪玉の直径がふえた長さ（メートル）
    var todayGrowth: Double {
        max(0, diameter - 2 * SnowPhysics.radius(mass: dayStartMass, pack: pack))
    }

    private mutating func addSteps(_ steps: Int) {
        guard steps > 0 else { return }
        totalSteps += steps
        guard !blackHole else { return }
        let result = SnowPhysics.advance(mass: mass, pack: pack, team: team, steps: steps, stage: stage)
        mass = result.mass
        blackHole = result.blackHole
        stage = result.stage
        materials += result.materials
        peakDiameter = max(peakDiameter, diameter)
    }

    private mutating func prune() {
        guard credited.count > 40 else { return }
        for key in credited.keys.sorted().dropLast(40) {
            credited[key] = nil
            baseline[key] = nil
        }
    }

    func creditedSteps(on key: String) -> Int { credited[key] ?? 0 }

    /// アプリをはじめて開いてから、その日に歩いた歩数
    func walkedSteps(on key: String) -> Int { max(0, (credited[key] ?? 0) - (baseline[key] ?? 0)) }

    // MARK: 雪玉

    var team: PushTeam { Shop.team(owned: owned) }

    /// 雪玉の半径（メートル）
    var radius: Double { SnowPhysics.radius(mass: mass, pack: pack) }

    /// 雪玉の直径（メートル）
    var diameter: Double { 2 * radius }

    /// 平均の密度（kg/m³）
    var density: Double { SnowPhysics.meanDensity(mass: mass, pack: pack) }

    /// 最後に見せた雪玉の半径（なければ、いまの半径）
    var seenRadius: Double {
        SnowPhysics.radius(mass: seenMass ?? mass, pack: seenPack ?? pack)
    }

    mutating func markSeen() {
        seenMass = mass
        seenPack = pack
    }

    /// 雪玉をタップして、ぎゅっと固める
    mutating func tapPack() {
        guard !blackHole else { return }
        pack = SnowPhysics.tappedPack(pack)
        if SnowPhysics.isBlackHole(mass: mass, pack: pack) { blackHole = true }
    }

    // MARK: 木の道

    /// いまの道の幅（メートル）
    var laneWidth: Double { Lane.width(stage: stage) }

    /// いまの道の木に、ちょうどぶつかる重さ
    var laneCapMass: Double { Lane.capMass(stage: stage, pack: pack) }

    /// 木に雪玉がぶつかって、押す力が足りずに止まっているか
    var isBlockedByTrees: Bool {
        let cap = laneCapMass
        return cap.isFinite && mass >= cap * 0.999 && !Lane.canTopple(capMass: cap, team: team)
    }

    /// 木を倒すのに要る力（ニュートン）。道がなければ nil。
    var toppleForceNeeded: Double? {
        let cap = laneCapMass
        return cap.isFinite ? Lane.toppleForce(capMass: cap) : nil
    }

    // MARK: 買い物

    /// 使える歩数
    var points: Int { max(0, totalSteps - spent) }

    func ownedCount(_ id: String) -> Int { owned[id] ?? 0 }

    func isUnlocked(_ item: ShopItem) -> Bool {
        peakDiameter >= item.unlockDiameter || ownedCount(item.id) > 0
    }

    func price(_ item: ShopItem) -> Int { Shop.price(item, owned: ownedCount(item.id)) }

    func materialPrice(_ item: ShopItem) -> Int { Shop.materials(item, owned: ownedCount(item.id)) }

    func canBuy(_ item: ShopItem) -> Bool {
        !blackHole && isUnlocked(item) && points >= price(item) && materials >= materialPrice(item)
    }

    @discardableResult
    mutating func buy(_ item: ShopItem) -> Bool {
        guard canBuy(item) else { return false }
        spent += price(item)
        materials -= materialPrice(item)
        owned[item.id, default: 0] += 1
        return true
    }

    /// ブラックホールになったあと、新しい雪玉ではじめから（歩数の記録は残す）
    func restarted() -> GameState {
        var fresh = GameState()
        fresh.onboarded = onboarded
        fresh.initialized = initialized
        fresh.credited = credited
        fresh.baseline = baseline
        return fresh
    }
}
