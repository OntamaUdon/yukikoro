import XCTest

final class TowerRulesTests: XCTestCase {
    private let config = TowerConfig.compact
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ball(_ index: Int, _ diameter: Double, owner: String, id: String? = nil, at seconds: Double = 0,
                      tower: String = "T") -> Ball {
        Ball(id: id ?? "b\(index)-\(owner)", towerID: tower, index: index, diameter: diameter, cumHeight: 0,
             ownerHash: owner, nick: "ふわふわのペンギン", look: 0, createdAt: t0.addingTimeInterval(seconds),
             periodId: "2026-W47", prefecture: 13)
    }

    private func tower(_ balls: [Ball], period: String = "2026-W47", at point: GeoPoint = GeoPoint(lat: 35.0, lon: 139.0)) -> Tower {
        TowerRules.tower(id: "T", location: point, periodId: period, prefecture: 13, createdAt: t0, balls: balls, config: config)
    }

    // MARK: 大きさ

    func testDiameterFromSteps() {
        XCTAssertEqual(BallSize.diameter(steps: 0, config: config), 0)
        XCTAssertEqual(BallSize.diameter(steps: 1_000, config: config), 0.29, accuracy: 1e-9)
        XCTAssertEqual(BallSize.diameter(steps: 41_000, config: config), 0.9998, accuracy: 0.001)
        XCTAssertEqual(BallSize.diameter(steps: 1_000_000, config: config), 2.9, accuracy: 1e-9)
        // 最小の雪玉は約 41 歩、土台の最小は約 1,100 歩
        XCTAssertEqual(BallSize.steps(forDiameter: 0.10, config: config), 41)
        XCTAssertEqual(BallSize.steps(forDiameter: 0.30, config: config), 1_107)
        XCTAssertGreaterThanOrEqual(BallSize.diameter(steps: 41, config: config) + TowerRules.epsilon, 0.10)
    }

    /// 標準の大きさ: 1 万歩で約 6m。実寸で地図や AR に出す
    func testStandardSizeIsLifeSize() {
        XCTAssertEqual(BallSize.diameter(steps: 10_000), 6.0, accuracy: 1e-9)
        XCTAssertEqual(BallSize.diameter(steps: 100_000), 18.97, accuracy: 0.01)
        XCTAssertEqual(BallSize.steps(forDiameter: 3.0), 2_500)
        XCTAssertEqual(BallSize.steps(forDiameter: 1.0), 278)
        XCTAssertGreaterThanOrEqual(BallSize.diameter(steps: 278) + TowerRules.epsilon, TowerConfig.standard.minBall)
        // 線形にしたいときは、指数を 1 にするだけ
        var linear = TowerConfig()
        linear.diameterExponent = 1
        linear.diameterCoefficient = 0.0006
        XCTAssertEqual(BallSize.diameter(steps: 10_000, config: linear), 6.0, accuracy: 1e-9)
        XCTAssertEqual(BallSize.steps(forDiameter: 6.0, config: linear), 10_000)
        XCTAssertEqual(TowerConfig.standard.minBase, 3.0)
    }

    // MARK: 位置の格子

    func testDistance() {
        let a = GeoPoint(lat: 0, lon: 0)
        let b = GeoPoint(lat: 0.001, lon: 0)
        XCTAssertEqual(a.distance(to: b), 111.2, accuracy: 0.5)
        XCTAssertEqual(a.distance(to: a), 0, accuracy: 1e-9)
    }

    func testRandomPointStaysInTheSameCell() {
        var generator = SplitMix64(seed: 42)
        for point in [GeoPoint(lat: 35.6812, lon: 139.7671), GeoPoint(lat: 43.0621, lon: 141.3544), GeoPoint(lat: 26.2124, lon: 127.6809)] {
            let cell = GeoGrid.cell(of: point)
            for _ in 0..<200 {
                let random = GeoGrid.randomPoint(inCellOf: point, using: &generator)
                let other = GeoGrid.cell(of: random)
                XCTAssertEqual(other.row, cell.row)
                XCTAssertEqual(other.column, cell.column)
                // 格子の対角線（約 71 m）より遠くにはならない
                XCTAssertLessThan(point.distance(to: random), 75)
            }
        }
    }

    func testRandomPointIsNotAlwaysTheSamePoint() {
        var generator = SplitMix64(seed: 1)
        let p = GeoPoint(lat: 35.0, lon: 139.0)
        let a = GeoGrid.randomPoint(inCellOf: p, using: &generator)
        let b = GeoGrid.randomPoint(inCellOf: p, using: &generator)
        XCTAssertNotEqual(a, b)
    }

    func testGridCellSizeIsAboutFiftyMeters() {
        let p = GeoPoint(lat: 35.0, lon: 139.0)
        let step = GeoGrid.latitudeStep(size: 50)
        XCTAssertEqual(GeoPoint(lat: p.lat, lon: p.lon).distance(to: GeoPoint(lat: p.lat + step, lon: p.lon)), 50, accuracy: 1)
        let row = GeoGrid.cell(of: p).row
        let lonStep = GeoGrid.longitudeStep(row: row, size: 50)
        XCTAssertEqual(p.distance(to: GeoPoint(lat: p.lat, lon: p.lon + lonStep)), 50, accuracy: 1)
    }

    // MARK: 有効な雪玉の列

    func testValidChain() {
        let balls = [ball(0, 1.0, owner: "A"), ball(1, 0.8, owner: "B"), ball(2, 0.5, owner: "A"), ball(3, 0.2, owner: "C")]
        let result = TowerRules.validBalls(balls, config: config)
        XCTAssertEqual(result.valid.count, 4)
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testChainBreaksOnRatio() {
        let balls = [ball(0, 1.0, owner: "A"), ball(1, 0.85, owner: "B"), ball(2, 0.5, owner: "C")]
        let result = TowerRules.validBalls(balls, config: config)
        XCTAssertEqual(result.valid.map(\.index), [0])
        XCTAssertEqual(result.rejected.count, 2, "条件を破った雪玉のあとは、順番が合わなくなって、無効")
    }

    func testSameOwnerCannotStackOnOwnBall() {
        let balls = [ball(0, 1.0, owner: "A"), ball(1, 0.5, owner: "A")]
        XCTAssertEqual(TowerRules.validBalls(balls, config: config).valid.count, 1)
        // 間に他の人がいれば、同じ人が何度でも参加できる
        let alternating = [ball(0, 1.0, owner: "A"), ball(1, 0.7, owner: "B"), ball(2, 0.4, owner: "A")]
        XCTAssertEqual(TowerRules.validBalls(alternating, config: config).valid.count, 3)
    }

    func testDuplicateIndexKeepsTheEarlierOne() {
        let early = ball(1, 0.5, owner: "B", id: "early", at: 1)
        let late = ball(1, 0.6, owner: "C", id: "late", at: 2)
        let result = TowerRules.validBalls([ball(0, 1.0, owner: "A"), late, early], config: config)
        XCTAssertEqual(result.valid.map(\.id), ["b0-A", "early"])
        XCTAssertEqual(result.rejected.map(\.id), ["late"])
        // 同時刻なら、id が小さいほう
        let x = ball(1, 0.5, owner: "B", id: "a-first", at: 5)
        let y = ball(1, 0.5, owner: "C", id: "b-second", at: 5)
        XCTAssertEqual(TowerRules.validBalls([ball(0, 1.0, owner: "A"), y, x], config: config).valid.last?.id, "a-first")
    }

    func testBaseMustBeBigEnoughAndBallsMustNotBeTooSmall() {
        XCTAssertTrue(TowerRules.validBalls([ball(0, 0.2, owner: "A")], config: config).valid.isEmpty)
        XCTAssertEqual(TowerRules.validBalls([ball(0, 0.3, owner: "A")], config: config).valid.count, 1)
        let tiny = [ball(0, 0.5, owner: "A"), ball(1, 0.05, owner: "B")]
        XCTAssertEqual(TowerRules.validBalls(tiny, config: config).valid.count, 1)
    }

    func testHeightAndClosing() {
        var balls = [ball(0, 1.0, owner: "A")]
        var d = 1.0
        var owner = "A"
        for i in 1..<11 {
            d *= 0.8
            owner = i % 2 == 0 ? "A" : "B"
            balls.append(ball(i, d, owner: owner))
        }
        let t = tower(balls)
        XCTAssertEqual(t.balls.count, 11)
        // 毎回ちょうど 0.8 倍で 11 個積むと、高さは約 4.57 m
        XCTAssertEqual(t.height, 4.57, accuracy: 0.01)
        XCTAssertTrue(t.isClosed(config: config), "一番上が 12.5 cm より小さくなったら完成")
        XCTAssertNil(t.maxNextDiameter(config: config))
        let open = tower(Array(balls.prefix(10)))
        XCTAssertFalse(open.isClosed(config: config))
        XCTAssertEqual(open.maxNextDiameter(config: config) ?? 0, open.top!.diameter * 0.8, accuracy: 1e-9)
    }

    func testNicksAreUniqueInOrder() {
        var b0 = ball(0, 1.0, owner: "A"); b0.nick = "ふわふわのペンギン"
        var b1 = ball(1, 0.7, owner: "B"); b1.nick = "のんびりのくま"
        var b2 = ball(2, 0.4, owner: "A"); b2.nick = "ふわふわのペンギン"
        XCTAssertEqual(tower([b0, b1, b2]).nicks, ["ふわふわのペンギン", "のんびりのくま"])
    }

    // MARK: 積む・おく

    func testStackIssues() {
        let t = tower([ball(0, 1.0, owner: "A"), ball(1, 0.6, owner: "B")])
        func issue(carried: Double, owner: String = "C", distance: Double? = 10, used: Int = 0, period: String = "2026-W47") -> StackIssue? {
            TowerRules.stackIssue(tower: t, carried: carried, owner: owner, distance: distance, usedToday: used, currentPeriod: period, config: config)
        }
        XCTAssertNil(issue(carried: 0.4))
        if case .tooBig(let max)? = issue(carried: 0.5) {
            XCTAssertEqual(max, 0.48, accuracy: 1e-9)
        } else {
            XCTFail("大きすぎる")
        }
        XCTAssertEqual(issue(carried: 0.05), .tooSmall(min: 0.10))
        XCTAssertEqual(issue(carried: 0.4, owner: "B"), .ownTop)
        XCTAssertNil(issue(carried: 0.4, owner: "A"), "土台の持ち主でも、一番上が他人なら積める")
        XCTAssertEqual(issue(carried: 0.4, distance: 51), .tooFar(distance: 51))
        XCTAssertNil(issue(carried: 0.4, distance: 50))
        XCTAssertEqual(issue(carried: 0.4, distance: nil), .location(.unavailable))
        XCTAssertEqual(issue(carried: 0.4, used: 20), .dailyLimit)
        XCTAssertEqual(issue(carried: 0.4, period: "2026-W48"), .frozen)
    }

    func testClosedTowerCannotBeStacked() {
        var balls = [ball(0, 1.0, owner: "A")]
        var d = 1.0
        for i in 1..<11 {
            d *= 0.8
            balls.append(ball(i, d, owner: i % 2 == 0 ? "A" : "B"))
        }
        let t = tower(balls)
        XCTAssertEqual(TowerRules.stackIssue(tower: t, carried: 0.1, owner: "C", distance: 1, usedToday: 0, currentPeriod: "2026-W47", config: config), .closed)
    }

    func testPlaceIssues() {
        let me = GeoPoint(lat: 35.0, lon: 139.0)
        let nearby = tower([ball(0, 1.0, owner: "A")], at: GeoPoint(lat: 35.0003, lon: 139.0))   // 約 33 m
        let far = tower([ball(0, 1.0, owner: "A")], at: GeoPoint(lat: 35.001, lon: 139.0))       // 約 111 m
        func issue(_ carried: Double, _ towers: [Tower], used: Int = 0) -> PlaceIssue? {
            TowerRules.placeIssue(carried: carried, me: me, towers: towers, currentPeriod: "2026-W47", usedToday: used, config: config)
        }
        XCTAssertNil(issue(0.5, []))
        XCTAssertNil(issue(0.5, [far]))
        XCTAssertEqual(issue(0.5, [nearby]), .nearTower)
        XCTAssertEqual(issue(0.2, []), .tooSmall(min: 0.30))
        XCTAssertEqual(issue(0.5, [], used: 20), .dailyLimit)
        // 完成した塔や、前の週の塔は、場所をふさがない
        let oldWeek = tower([ball(0, 1.0, owner: "A")], period: "2026-W46", at: GeoPoint(lat: 35.0003, lon: 139.0))
        XCTAssertNil(issue(0.5, [oldWeek]))
    }

    func testLocationQuality() {
        XCTAssertNil(TowerRules.locationIssue(horizontalAccuracy: 10, speed: 1, simulated: false, accessory: false))
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: nil, speed: 1, simulated: false, accessory: false), .unavailable)
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: -1, speed: 1, simulated: false, accessory: false), .unavailable)
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: 80, speed: 1, simulated: false, accessory: false), .inaccurate)
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: 10, speed: 9, simulated: false, accessory: false), .tooFast)
        XCTAssertNil(TowerRules.locationIssue(horizontalAccuracy: 10, speed: -1, simulated: false, accessory: false), "速度が分からないときは、止めない")
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: 10, speed: 1, simulated: true, accessory: false), .spoofed)
        XCTAssertEqual(TowerRules.locationIssue(horizontalAccuracy: 10, speed: 1, simulated: false, accessory: true), .spoofed)
    }

    func testMakeBallAccumulatesHeight() {
        let b = TowerRules.makeBall(towerID: "T", index: 2, diameter: 0.4, previousHeight: 1.8, ownerHash: "A", nick: "x",
                                    now: t0, periodId: "2026-W47", prefecture: 13)
        XCTAssertEqual(b.cumHeight, 2.2, accuracy: 1e-9)
        XCTAssertFalse(b.id.isEmpty)
    }

    // MARK: ポイントと順位

    func testPoints() {
        XCTAssertEqual(PointRules.coveredReward(diameter: BallSize.diameter(steps: 2_000)), 100)
        XCTAssertEqual(PointRules.completionReward(diameter: BallSize.diameter(steps: 2_000)), 200)
    }

    func testRankingByHeightThenEarlier() {
        let low = tower([ball(0, 0.5, owner: "A", tower: "low")])
        var tall = tower([ball(0, 1.0, owner: "A", tower: "tall")])
        tall.id = "tall"
        var low2 = low
        low2.id = "low2"
        var mid = tower([ball(0, 0.5, owner: "B", at: -100)])
        mid.id = "mid"
        let ranked = Ranking.sorted([low, tall, mid, low2])
        XCTAssertEqual(ranked.first?.id, "tall")
        XCTAssertEqual(ranked.dropFirst().first?.id, "mid", "同じ高さなら、最後の雪玉が早いほうが上")
        var tokyo = tall; tokyo.prefecture = 13
        var osaka = low; osaka.prefecture = 27; osaka.id = "osaka"
        XCTAssertEqual(Ranking.top([tokyo, osaka], prefecture: 27, limit: 5).map(\.id), ["osaka"])
        XCTAssertEqual(Ranking.top([tokyo, osaka], prefecture: nil, limit: 1).map(\.id), ["tall"])
    }

    // MARK: 期間

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testWeekIdUsesTokyoTime() {
        XCTAssertEqual(PeriodClock.weekId(for: date("2026-11-16T00:00:00+09:00")), "2026-W47")
        XCTAssertEqual(PeriodClock.weekId(for: date("2026-11-15T23:59:59+09:00")), "2026-W46")
        XCTAssertEqual(PeriodClock.weekId(for: date("2026-11-22T23:59:59+09:00")), "2026-W47")
        // 日本時間の月曜 0 時は、UTC ではまだ日曜
        XCTAssertEqual(PeriodClock.weekId(for: date("2026-11-15T15:00:00Z")), "2026-W47")
        XCTAssertEqual(PeriodClock.weekId(for: date("2027-01-01T12:00:00+09:00")), "2026-W53")
    }

    func testPeriodIdsForBetaAndProduction() {
        let now = date("2026-11-18T12:00:00+09:00")
        XCTAssertEqual(PeriodClock.periodId(now: now, betaSeq: nil), "2026-W47")
        XCTAssertEqual(PeriodClock.periodId(now: now, betaSeq: 3), "beta-3")
        XCTAssertEqual(PeriodClock.previousPeriodId(now: now, betaSeq: nil), "2026-W46")
        XCTAssertEqual(PeriodClock.previousPeriodId(now: now, betaSeq: 3), "beta-2")
        XCTAssertNil(PeriodClock.previousPeriodId(now: now, betaSeq: 1))
        XCTAssertEqual(PeriodClock.weekEnd(for: now), date("2026-11-23T00:00:00+09:00"))
    }

    // MARK: 名前・都道府県

    func testNicknameIsMadeFromFixedWords() {
        XCTAssertEqual(Nickname.make(adjective: 0, animal: 0), "ふわふわのペンギン")
        XCTAssertEqual(Nickname.make(adjective: 20, animal: 21), "ふわふわのうさぎ", "番号は、一覧の長さでひとまわりする")
        XCTAssertEqual(Nickname.make(adjective: -1, animal: -1), "ぱたぱたのくじら")
        var g = SplitMix64(seed: 7)
        let r = Nickname.random(using: &g)
        XCTAssertTrue((0..<Nickname.adjectives.count).contains(r.adjective))
    }

    func testPrefectureCodes() {
        XCTAssertEqual(Prefecture.names.count, 47)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "東京都"), 13)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "北海道"), 1)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "大阪府"), 27)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "京都府"), 26)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "沖縄県"), 47)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "東京"), 13)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "Tokyo"), 13)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "Osaka Prefecture"), 27)
        XCTAssertEqual(Prefecture.code(fromAdministrativeArea: "Hokkaido"), 1)
        XCTAssertNil(Prefecture.code(fromAdministrativeArea: nil))
        XCTAssertNil(Prefecture.code(fromAdministrativeArea: "California"))
        XCTAssertEqual(Prefecture.name(code: 13), "東京都")
        XCTAssertEqual(Prefecture.name(code: 0), "—")
    }

    // MARK: 設定データ

    func testConfigDecodesMissingKeysWithDefaults() throws {
        let json = #"{"stackRatio": 0.7, "dailyLimit": 5}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(TowerConfig.self, from: json)
        XCTAssertEqual(config.stackRatio, 0.7)
        XCTAssertEqual(config.dailyLimit, 5)
        XCTAssertEqual(config.minBase, 3.0)
        XCTAssertEqual(try JSONDecoder().decode(TowerConfig.self, from: "{}".data(using: .utf8)!), TowerConfig.standard)
    }

    // MARK: 自分の状態

    func testStepLedgerIgnoresStepsBeforeFirstOpen() {
        var p = PlayerState()
        XCTAssertEqual(p.apply(daily: ["2026-11-16": 3_000]), 0, "はじめて開いたときまでの歩数は数えない")
        XCTAssertEqual(p.totalSteps, 0)
        XCTAssertEqual(p.apply(daily: ["2026-11-16": 3_500]), 500)
        XCTAssertEqual(p.totalSteps, 500)
        XCTAssertEqual(p.walkedSteps(on: "2026-11-16"), 500)
        // 二重に数えない・減った歩数は無視
        XCTAssertEqual(p.apply(daily: ["2026-11-16": 3_500]), 0)
        XCTAssertEqual(p.apply(daily: ["2026-11-16": 3_000]), 0)
        XCTAssertEqual(p.totalSteps, 500)
        // 新しい日は、そこから数える
        XCTAssertEqual(p.apply(daily: ["2026-11-17": 800, "2026-11-16": 3_500]), 800)
    }

    func testCarriedBallGrowsAndResetsWhenUsed() {
        var p = PlayerState()
        p.addDebugSteps(1_000)
        XCTAssertEqual(p.carriedSteps, 1_000)
        XCTAssertEqual(p.carriedDiameter(config: config), 0.29, accuracy: 1e-9)
        p.markUsed(dayKey: "2026-11-16")
        XCTAssertEqual(p.carriedSteps, 0)
        XCTAssertEqual(p.usedToday, 1)
        p.addDebugSteps(500)
        XCTAssertEqual(p.carriedSteps, 500)
        p.markUsed(dayKey: "2026-11-16")
        XCTAssertEqual(p.usedToday, 2)
        p.markUsed(dayKey: "2026-11-17")
        XCTAssertEqual(p.usedToday, 1, "日が変わったら、数え直し")
    }

    func testShaveOnlyMakesTheBallSmaller() {
        var p = PlayerState()
        p.addDebugSteps(5_000)
        let before = p.carriedDiameter(config: config)
        p.shave(to: 0.30, config: config)
        XCTAssertEqual(p.carriedDiameter(config: config), 0.30, accuracy: 0.002)
        XCTAssertLessThan(p.carriedDiameter(config: config), before)
        p.shave(to: 1.0, config: config)
        XCTAssertEqual(p.carriedDiameter(config: config), 0.30, accuracy: 0.002, "大きくは戻せない")
        p.addDebugSteps(100)
        XCTAssertGreaterThan(p.carriedDiameter(config: config), 0.30, "けずったあとも、歩けば育つ")
    }

    func testDailyPointCap() {
        var p = PlayerState()
        XCTAssertEqual(p.addPoints(1_500, dayKey: "d1", dailyCap: 2_000), 1_500)
        XCTAssertEqual(p.addPoints(1_500, dayKey: "d1", dailyCap: 2_000), 500)
        XCTAssertEqual(p.points, 2_000)
        XCTAssertEqual(p.addPoints(100, dayKey: "d2", dailyCap: 2_000), 100, "日が変われば、また入る")
    }

    func testPlayerStateRoundTrip() throws {
        var p = PlayerState()
        p.apply(daily: ["2026-11-16": 100])
        p.nickAdjective = 3
        p.rewardedBalls = ["x"]
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(PlayerState.self, from: data)
        XCTAssertEqual(back, p)
        let empty = try JSONDecoder().decode(PlayerState.self, from: "{}".data(using: .utf8)!)
        XCTAssertFalse(empty.onboarded)
        XCTAssertEqual(empty.totalSteps, 0)
        XCTAssertEqual(empty.points, 0)
    }
}

// 試験用の「小さい雪玉」の設定（古い大きさ）。ルールの数式が、大きさに関係なく正しいことを確かめる。
extension TowerConfig {
    static let compact: TowerConfig = {
        var c = TowerConfig()
        c.diameterCoefficient = 0.029
        c.diameterExponent = 1.0 / 3.0
        c.minBall = 0.10
        c.minBase = 0.30
        return c
    }()
}
