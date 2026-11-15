import Foundation

/// メモリ上の置き場。画面の確認、試験（ひとりで動かす）用。CloudKit 版と同じ決まりで動く。
actor InMemoryTowerRepository: TowerRepository {
    private struct Stored {
        var location: GeoPoint
        var periodId: String
        var prefecture: Int
        var createdAt: Date
        var balls: [Ball]
    }

    private var towersByID: [String: Stored] = [:]
    private var betaSeqValue = 1
    private var reports: [(towerID: String, periodId: String)] = []
    private let me: String

    init(me: String = "me-local") {
        self.me = me
    }

    func ownerHash() async throws -> String { me }

    func fetchConfig() async -> TowerConfig { .standard }

    func betaSeq() async throws -> Int { betaSeqValue }

    func advanceBetaSeq() async throws -> Int {
        betaSeqValue += 1
        return betaSeqValue
    }

    private func build(_ id: String, _ stored: Stored, config: TowerConfig) -> Tower {
        var tower = TowerRules.tower(id: id, location: stored.location, periodId: stored.periodId,
                                     prefecture: stored.prefecture, createdAt: stored.createdAt,
                                     balls: stored.balls, config: config)
        tower.reportCount = reports.filter { $0.towerID == id }.count
        return tower
    }

    func towers(near: GeoPoint, radius: Double, periodId: String, config: TowerConfig) async throws -> [Tower] {
        towersByID
            .filter { $0.value.periodId == periodId && $0.value.location.distance(to: near) <= radius }
            .map { build($0.key, $0.value, config: config) }
            .filter { !$0.balls.isEmpty }
    }

    func tower(id: String, config: TowerConfig) async throws -> Tower? {
        towersByID[id].map { build(id, $0, config: config) }
    }

    func placeBase(location: GeoPoint, prefecture: Int, periodId: String, ball: Ball, config: TowerConfig) async throws -> Tower {
        towersByID[ball.towerID] = Stored(location: location, periodId: periodId, prefecture: prefecture,
                                          createdAt: Date(), balls: [ball])
        return build(ball.towerID, towersByID[ball.towerID]!, config: config)
    }

    func stack(ball: Ball, config: TowerConfig) async throws -> StackOutcome {
        guard var stored = towersByID[ball.towerID] else { throw RepositoryError.notFound }
        stored.balls.append(ball)
        towersByID[ball.towerID] = stored
        let tower = build(ball.towerID, stored, config: config)
        return tower.balls.contains { $0.id == ball.id } ? .accepted(tower) : .rejected(tower)
    }

    func topTowers(periodId: String, prefecture: Int?, limit: Int, config: TowerConfig) async throws -> [Tower] {
        let all = towersByID
            .filter { $0.value.periodId == periodId }
            .map { build($0.key, $0.value, config: config) }
            .filter { !$0.balls.isEmpty }
        return Ranking.top(all, prefecture: prefecture, limit: limit)
    }

    func myBalls(ownerHash: String, limit: Int) async throws -> [Ball] {
        let mine = towersByID.values.flatMap { $0.balls }.filter { $0.ownerHash == ownerHash }
        return Array(mine.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func report(towerID: String, periodId: String, reason: Int) async throws {
        reports.append((towerID, periodId))
    }

    func reportCounts(periodId: String) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for r in reports where r.periodId == periodId { counts[r.towerID, default: 0] += 1 }
        return counts
    }

    // MARK: 画面確認用の見本

    /// 現在地のまわりに、見本の塔をいくつか置く（画面確認・ひとりでの試験用）。
    func seedDemo(around center: GeoPoint, periodId: String, config: TowerConfig = .standard, now: Date = Date()) {
        // メートルを緯度・経度の差にする
        func offset(_ north: Double, _ east: Double) -> GeoPoint {
            GeoPoint(lat: center.lat + north / 111_320,
                     lon: center.lon + east / (111_320 * cos(center.lat * .pi / 180)))
        }
        struct Plan { var north: Double; var east: Double; var diameters: [Double] }
        let plans = [
            Plan(north: 70, east: 40, diameters: [1.1, 0.85, 0.66, 0.5, 0.38, 0.28]),
            Plan(north: -120, east: 90, diameters: [0.7, 0.5, 0.36]),
            Plan(north: 150, east: -110, diameters: [1.6, 1.2, 0.95, 0.7]),
            Plan(north: -40, east: -150, diameters: [0.45]),
            Plan(north: 230, east: 60, diameters: [0.9, 0.7, 0.5, 0.38, 0.28, 0.2, 0.15, 0.11]),
        ]
        let owners = ["demo-a", "demo-b", "demo-c"]
        let nicks = ["のんびりのくま", "ぴかぴかのうさぎ", "ゆっくりのふくろう"]
        for (n, plan) in plans.enumerated() {
            let towerID = "demo-tower-\(n)"
            var balls: [Ball] = []
            var height = 0.0
            for (i, d) in plan.diameters.enumerated() {
                let k = (n + i) % owners.count
                height += d
                balls.append(Ball(id: "demo-ball-\(n)-\(i)", towerID: towerID, index: i, diameter: d, cumHeight: height,
                                  ownerHash: owners[k], nick: nicks[k], look: 0,
                                  createdAt: now.addingTimeInterval(-Double(1_000 - i * 10 - n)),
                                  periodId: periodId, prefecture: 13))
            }
            towersByID[towerID] = Stored(location: offset(plan.north, plan.east), periodId: periodId, prefecture: 13,
                                         createdAt: now.addingTimeInterval(-2_000), balls: balls)
        }
    }
}
