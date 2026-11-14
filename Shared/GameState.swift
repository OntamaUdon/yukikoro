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
    var version: Int = 2
    var onboarded: Bool = false
    /// 初回の歩数同期（過去日のベースライン記録）が済んだか
    var initialized: Bool = false
    /// 今転がしている雪玉の歩数（達成上限 `Snow.maxSteps` まで）
    var rollingSteps: Int = 0
    /// 今転がしている雪玉の形と色。歩数が増えると、この形のまま厚さ一定で一回り大きくなる。
    var rollingShape: SnowShape = .pristine(seed: 11)
    /// 達成上限を超えて余った歩数。ゆきだまにしたあと、次の雪玉に持ち越す。
    var reserveSteps: Int = 0
    /// これまでに雪玉に加算した歩数の合計
    var totalSteps: Int = 0
    /// 日付ごとに「すでに加算した歩数」。差分だけ足すので二重加算も取りこぼしも起きない。
    var credited: [String: Int] = [:]
    /// 作品に使えるゆきだま（まだ置いていないもの）
    var stock: [SnowPiece] = []
    var artworks: [Artwork] = []
    var createdAt: Date = Date()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, onboarded, initialized, rollingSteps, rollingShape, reserveSteps, totalSteps, credited, stock, artworks, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        initialized = try c.decodeIfPresent(Bool.self, forKey: .initialized) ?? false
        rollingSteps = try c.decodeIfPresent(Int.self, forKey: .rollingSteps) ?? 0
        rollingShape = (try? c.decodeIfPresent(SnowShape.self, forKey: .rollingShape)) ?? .pristine(seed: 11)
        reserveSteps = try c.decodeIfPresent(Int.self, forKey: .reserveSteps) ?? 0
        totalSteps = try c.decodeIfPresent(Int.self, forKey: .totalSteps) ?? 0
        credited = try c.decodeIfPresent([String: Int].self, forKey: .credited) ?? [:]
        stock = (try? c.decodeIfPresent([SnowPiece].self, forKey: .stock)) ?? []
        artworks = (try? c.decodeIfPresent([Artwork].self, forKey: .artworks)) ?? []
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
        addToBall(gained)
        prune()
        return gained
    }

    /// テストやデバッグ用に歩数を直接足す
    mutating func addBonus(steps: Int) {
        guard steps > 0 else { return }
        addToBall(steps)
    }

    /// 雪玉に歩数を足す。達成上限を超えた分は持ち越しに回す。
    private mutating func addToBall(_ steps: Int) {
        let room = max(0, Snow.maxSteps - rollingSteps)
        let toBall = min(steps, room)
        let before = Float(BallScale.radius(steps: rollingSteps))
        rollingSteps += toBall
        rollingShape.grow(fromRadius: before, toRadius: Float(BallScale.radius(steps: rollingSteps)))
        reserveSteps += steps - toBall
        totalSteps += steps
    }

    private mutating func prune() {
        guard credited.count > 40 else { return }
        for key in credited.keys.sorted().dropLast(40) {
            credited[key] = nil
        }
    }

    func creditedSteps(on key: String) -> Int { credited[key] ?? 0 }

    // MARK: ゆきだまにする

    var canComplete: Bool { rollingSteps >= Snow.minimumSteps }

    /// 達成上限（最大サイズ）に到達しているか
    var isAtCap: Bool { rollingSteps >= Snow.maxSteps }

    /// 転がしている雪玉をゆきだまにして、手元（ストック）に入れる。
    mutating func makePiece<G: RandomNumberGenerator>(using g: inout G, now: Date = Date()) -> SnowPiece? {
        guard canComplete else { return nil }
        let seed = UInt32(truncatingIfNeeded: g.next())
        let piece = SnowPiece(id: UUID(), steps: rollingSteps, madeAt: now, shape: rollingShape)
        stock.append(piece)
        // 達成上限を超えて持ち越していた歩数があれば、次の雪玉に回す
        let carried = min(reserveSteps, Snow.maxSteps)
        rollingSteps = carried
        rollingShape = .pristine(seed: UInt32(truncatingIfNeeded: g.next()))
        reserveSteps -= carried
        return piece
    }

    mutating func makePiece(now: Date = Date()) -> SnowPiece? {
        var g = SystemRandomNumberGenerator()
        return makePiece(using: &g, now: now)
    }

    /// 転がしている雪玉の形を更新する（成形したとき）
    mutating func updateRolling(shape: SnowShape) { rollingShape = shape }

    /// 転がしている雪玉の直径（メートル）
    var rollingDiameter: Double { BallScale.diameter(steps: rollingSteps, extent: rollingShape.maxExtent) }

    // MARK: ストックと作品

    mutating func updateStock(id: UUID, shape: SnowShape) {
        guard let i = stock.firstIndex(where: { $0.id == id }) else { return }
        stock[i].shape = shape
    }

    /// ストックからゆきだまを取り出す（作品に置くとき）
    mutating func takeFromStock(id: UUID) -> SnowPiece? {
        guard let i = stock.firstIndex(where: { $0.id == id }) else { return nil }
        return stock.remove(at: i)
    }

    mutating func returnToStock(_ piece: SnowPiece) {
        guard !stock.contains(where: { $0.id == piece.id }) else { return }
        stock.append(piece)
    }

    mutating func newArtwork(now: Date = Date()) -> Artwork {
        let artwork = Artwork(name: "作品\(artworks.count + 1)", createdAt: now, updatedAt: now)
        artworks.append(artwork)
        return artwork
    }

    mutating func saveArtwork(_ artwork: Artwork) {
        if let i = artworks.firstIndex(where: { $0.id == artwork.id }) {
            artworks[i] = artwork
        } else {
            artworks.append(artwork)
        }
    }

    /// 作品を消す。使っていたゆきだまはストックに戻る。
    mutating func deleteArtwork(id: UUID) {
        guard let i = artworks.firstIndex(where: { $0.id == id }) else { return }
        for p in artworks[i].placements { returnToStock(p.piece) }
        artworks.remove(at: i)
    }

    /// 手元とすべての作品にあるゆきだまの数
    var totalPieceCount: Int { stock.count + artworks.reduce(0) { $0 + $1.placements.count } }
}
