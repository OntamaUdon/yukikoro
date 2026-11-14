import XCTest

final class GameLogicTests: XCTestCase {
    // MARK: 歩数の台帳

    func testFirstSyncCountsNothingAndStartsFromZero() {
        var state = GameState()
        let gained = state.apply(daily: ["2026-11-12": 8_000, "2026-11-13": 6_000, "2026-11-14": 1_200], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 0, "はじめて開いたときまでに歩いた分は数えない")
        XCTAssertEqual(state.totalSteps, 0)
        XCTAssertEqual(state.walkedSteps(on: "2026-11-14"), 0, "今日は 0 歩からはじまる")
        XCTAssertTrue(state.initialized)
        // そこから歩いた分だけが数えられる
        let later = state.apply(daily: ["2026-11-12": 8_000, "2026-11-13": 6_000, "2026-11-14": 1_700], todayKey: "2026-11-14")
        XCTAssertEqual(later, 500)
        XCTAssertEqual(state.walkedSteps(on: "2026-11-14"), 500)
        XCTAssertEqual(state.totalSteps, 500)
    }

    func testRepeatedSyncDoesNotDoubleCount() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        let first = state.apply(daily: ["2026-11-14": 2_000], todayKey: "2026-11-14")
        XCTAssertEqual(first, 1_000)
        let again = state.apply(daily: ["2026-11-14": 2_000], todayKey: "2026-11-14")
        XCTAssertEqual(again, 0)
        XCTAssertEqual(state.totalSteps, 1_000)
    }

    func testOnlyTheDifferenceIsAdded() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        state.apply(daily: ["2026-11-14": 2_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 2_750], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 750)
        XCTAssertEqual(state.totalSteps, 1_750)
    }

    func testDecreasingStepsAreIgnored() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 2_000], todayKey: "2026-11-14")
        state.apply(daily: ["2026-11-14": 3_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 2_500], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 0)
        XCTAssertEqual(state.totalSteps, 1_000)
        // 戻らず、その後に増えた分だけが加算される
        let later = state.apply(daily: ["2026-11-14": 3_300], todayKey: "2026-11-14")
        XCTAssertEqual(later, 300)
    }

    func testNewDayCountsFromZero() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 4_000], todayKey: "2026-11-14")
        state.apply(daily: ["2026-11-14": 5_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 5_000, "2026-11-15": 900], todayKey: "2026-11-15")
        XCTAssertEqual(gained, 900, "次の日は、0 歩から全部数える")
        XCTAssertEqual(state.totalSteps, 1_900)
        XCTAssertEqual(state.walkedSteps(on: "2026-11-15"), 900)
    }

    func testStepsWalkedWhileAppWasClosedAreCredited() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        // 3日開かなかった後の同期。直近7日の窓に入っている日は加算される
        let gained = state.apply(
            daily: ["2026-11-14": 3_000, "2026-11-15": 7_000, "2026-11-16": 5_000, "2026-11-17": 100],
            todayKey: "2026-11-17"
        )
        XCTAssertEqual(gained, 2_000 + 7_000 + 5_000 + 100)
    }

    func testEmptyDailyDoesNothing() {
        var state = GameState()
        XCTAssertEqual(state.apply(daily: [:], todayKey: "2026-11-14"), 0)
        XCTAssertFalse(state.initialized)
    }

    func testPruneKeepsRecentDays() {
        var state = GameState()
        var daily: [String: Int] = [:]
        for i in 1...60 {
            daily[String(format: "2026-01-%02d", min(i, 28)) + "-\(i)"] = i
        }
        state.apply(daily: daily, todayKey: "x")
        XCTAssertLessThanOrEqual(state.credited.count, 40)
    }

    // MARK: 保存

    func testStorageSaveAndLoad() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yukikoro-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = GameState()
        state.onboarded = true
        state.addBonus(steps: 777)
        XCTAssertTrue(GameStorage.save(state, to: url))
        let loaded = GameStorage.load(from: url)
        XCTAssertEqual(loaded.totalSteps, 777)
        XCTAssertEqual(loaded.mass, state.mass, accuracy: state.mass * 1e-12)
        XCTAssertTrue(loaded.onboarded)
    }

    func testCodableRoundTrip() throws {
        var state = GameState()
        state.addBonus(steps: 4_000)
        state.onboarded = true
        state.owned = ["kid": 3, "plank": 1]
        state.spent = 321
        state.pack = 0.25
        state.seenMass = 12.5
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameState.self, from: try encoder.encode(state))
        XCTAssertEqual(decoded.totalSteps, 4_000)
        XCTAssertEqual(decoded.owned, ["kid": 3, "plank": 1])
        XCTAssertEqual(decoded.spent, 321)
        XCTAssertEqual(decoded.pack, 0.25, accuracy: 1e-12)
        XCTAssertEqual(decoded.seenMass ?? 0, 12.5, accuracy: 1e-12)
        XCTAssertEqual(decoded.mass, state.mass, accuracy: state.mass * 1e-12)
        XCTAssertTrue(decoded.onboarded)
    }

    func testOldSavesKeepOnlyTheirSteps() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 以前の版（歩数だけで雪玉の大きさが決まっていた）は、雪玉は最初からにして、歩数だけ引き継ぐ
        let json = "{\"version\": 3, \"onboarded\": true, \"rollingSteps\": 900, \"totalSteps\": 5000}"
        let state = try decoder.decode(GameState.self, from: Data(json.utf8))
        XCTAssertTrue(state.onboarded)
        XCTAssertEqual(state.totalSteps, 5_000)
        XCTAssertEqual(state.points, 5_000, "引き継いだ歩数は、そのまま買い物に使える")
        XCTAssertEqual(state.radius, 0.01, accuracy: 1e-6)
        let minimal = try decoder.decode(GameState.self, from: Data("{}".utf8))
        XCTAssertEqual(minimal.totalSteps, 0)
    }

    // MARK: 雪玉の物理

    func testBallStartsAtOneCentimeterRadius() {
        XCTAssertEqual(GameState().radius, 0.01, accuracy: 1e-9)
        XCTAssertEqual(GameState().diameter, 0.02, accuracy: 1e-9)
    }

    /// Python の試算（tools の参考実装と同じ式）と合うこと
    func testAdvanceMatchesReferenceSimulation() {
        let bare = PushTeam(force: 60, reach: 0.7, lift: 0)
        let m0 = SnowPhysics.initialMass()
        let references: [(Int, Double)] = [(1, 3.323815e-02), (10, 6.521451e-01), (100, 1.080648e+01), (1_000, 3.975285e+01)]
        for (steps, expected) in references {
            let m = SnowPhysics.advance(mass: m0, pack: 0, team: bare, steps: steps).mass
            XCTAssertEqual(m, expected, accuracy: expected * 0.02, "steps=\(steps)")
        }
        let strong = Shop.team(owned: ["kid": 12, "big": 2, "plank": 1, "crawler": 1, "heavy": 1, "gravity": 18])
        XCTAssertEqual(strong.force, 6_315_300, accuracy: 1)
        XCTAssertEqual(strong.lift, 0.6, accuracy: 1e-12)
        let a = SnowPhysics.advance(mass: 1e6, pack: 0, team: strong, steps: 10).mass
        XCTAssertEqual(a, 8.706893e+07, accuracy: 8.706893e+07 * 0.02)
        let b = SnowPhysics.advance(mass: 1e9, pack: 0, team: strong, steps: 1_000).mass
        XCTAssertEqual(b, 2.306812e+10, accuracy: 2.306812e+10 * 0.02)
    }

    func testRadiusCompressesAndShrinksWhenVeryHeavy() {
        XCTAssertEqual(SnowPhysics.radius(mass: 1, pack: 0), 0.09266805, accuracy: 1e-6)
        XCTAssertEqual(SnowPhysics.radius(mass: 1e27, pack: 0), 8.776496e7, accuracy: 8.776496e7 * 0.01)
        // 木星くらいの重さを超えると、自重で縮み始める
        XCTAssertLessThan(SnowPhysics.radius(mass: 1e30, pack: 0), SnowPhysics.radius(mass: 1e27, pack: 0))
        XCTAssertLessThan(SnowPhysics.radius(mass: 1e32, pack: 0), SnowPhysics.radius(mass: 1e30, pack: 0))
        // 重いほど平均の密度は上がる
        XCTAssertGreaterThan(SnowPhysics.meanDensity(mass: 1e30, pack: 0), SnowPhysics.meanDensity(mass: 1e20, pack: 0))
    }

    func testBlackHoleThreshold() {
        XCTAssertEqual(SnowPhysics.schwarzschildRadius(mass: 1.989e30), 2_954, accuracy: 20)
        XCTAssertFalse(SnowPhysics.isBlackHole(mass: 5e32, pack: 0))
        XCTAssertTrue(SnowPhysics.isBlackHole(mass: 1e33, pack: 0))
        XCTAssertFalse(SnowPhysics.isBlackHole(mass: 1e20, pack: 1))
        XCTAssertFalse(SnowPhysics.isBlackHole(mass: SnowPhysics.initialMass(), pack: 0))
    }

    func testPushingGetsSlowerWithWeightButNeverStops() {
        let team = Shop.team(owned: ["kid": 10])
        var previous = Double.infinity
        for exponent in 0...12 {
            let d = SnowPhysics.pushDistance(mass: pow(10, Double(exponent)), team: team)
            XCTAssertGreaterThan(d, 0, "止まりはしない（mass=1e\(exponent)）")
            XCTAssertLessThanOrEqual(d, previous)
            previous = d
        }
        // 軽いうちは、ほぼ1歩ぶん転がる
        XCTAssertGreaterThan(SnowPhysics.easiness(mass: 1, team: team), 0.99)
        // 押す力の限界を大きく超えると、止まっているように見えるほど遅い
        XCTAssertLessThan(SnowPhysics.easiness(mass: 1e6, team: team), 1e-6)
    }

    func testGravityDeviceRemovesTheLimit() {
        let team = PushTeam(force: 0, reach: 100, lift: 0.6)
        // 重さに比例する力は、どんなに重くても追いつく
        XCTAssertGreaterThan(SnowPhysics.easiness(mass: 1e6, team: team), 0.9)
        XCTAssertGreaterThan(SnowPhysics.easiness(mass: 1e18, team: team), 0.9)
    }

    func testMassAlwaysIncreasesWithSteps() {
        let team = Shop.team(owned: ["kid": 5])
        var m = SnowPhysics.initialMass()
        for _ in 0..<2_000 {
            let next = SnowPhysics.step(mass: m, pack: 0, team: team)
            XCTAssertGreaterThanOrEqual(next, m)
            m = next
        }
        XCTAssertGreaterThan(m, SnowPhysics.initialMass() * 100)
    }

    func testSelfGravityGathersSnowAcceleratingly() {
        // 押す力がゼロでも、重い雪玉は重力で雪を引き寄せて重くなる（上限は1歩に0.1%）
        let none = PushTeam(force: 0, reach: 0, lift: 0)
        let big = SnowPhysics.step(mass: 1e20, pack: 0, team: none)
        XCTAssertEqual(big / 1e20, 1.001, accuracy: 1e-9)
        // 軽ければ、ほとんど何も起きない
        let small = SnowPhysics.step(mass: 1e6, pack: 0, team: none)
        XCTAssertEqual(small / 1e6, 1, accuracy: 1e-9)
        // 重くなるほど増える割合が大きい（加速度的）
        let a = SnowPhysics.step(mass: 1e13, pack: 0, team: none) / 1e13 - 1
        let b = SnowPhysics.step(mass: 1e14, pack: 0, team: none) / 1e14 - 1
        XCTAssertGreaterThan(b, a * 5)
    }

    func testReachesBlackHoleAndStopsThere() {
        var state = GameState()
        state.mass = 9e32
        state.stage = 20
        state.addBonus(steps: 200_000)
        XCTAssertTrue(state.blackHole)
        let frozen = state.mass
        state.addBonus(steps: 1_000)
        XCTAssertEqual(state.mass, frozen, "ブラックホールになったあとは変わらない")
        XCTAssertGreaterThan(state.totalSteps, 200_000)
        let fresh = state.restarted()
        XCTAssertFalse(fresh.blackHole)
        XCTAssertEqual(fresh.radius, 0.01, accuracy: 1e-9)
    }

    func testRestartKeepsTheStepLedger() {
        var state = GameState()
        state.onboarded = true
        state.apply(daily: ["2026-11-14": 3_000], todayKey: "2026-11-14")
        let fresh = state.restarted()
        XCTAssertTrue(fresh.onboarded)
        XCTAssertTrue(fresh.initialized)
        XCTAssertEqual(fresh.creditedSteps(on: "2026-11-14"), 3_000)
        XCTAssertEqual(fresh.totalSteps, 0)
        // 同じ日の歩数をまた数えない
        var again = fresh
        XCTAssertEqual(again.apply(daily: ["2026-11-14": 3_000], todayKey: "2026-11-14"), 0)
    }

    // MARK: 木の道

    func testLaneWidthsAndCaps() {
        XCTAssertEqual(Lane.width(stage: 0), 3, accuracy: 1e-12)
        XCTAssertEqual(Lane.width(stage: 2), 75, accuracy: 1e-9)
        XCTAssertEqual(Lane.treeScale(stage: 1), 5, accuracy: 1e-12)
        XCTAssertEqual(Lane.reward(stage: 0), 600)
        XCTAssertEqual(Lane.reward(stage: 1), 4_800)
        // 半径が道の幅の半分になる重さ（密度 300 の球）
        XCTAssertEqual(Lane.capMass(stage: 0, pack: 0), 4_241.15, accuracy: 4)
        XCTAssertEqual(Lane.capMass(stage: 1, pack: 0), 530_143.8, accuracy: 530_143.8 * 0.01)
        // 固めた雪玉は同じ半径でも重いので、ぶつかる重さが大きい
        XCTAssertEqual(Lane.capMass(stage: 0, pack: 1), 7_068.6, accuracy: 70)
        // とても広い道には、ぶつからない
        XCTAssertTrue(Lane.capMass(stage: 20, pack: 0).isInfinite)
    }

    func testToppleNeedsEnoughForce() {
        let cap = Lane.capMass(stage: 0, pack: 0)
        XCTAssertEqual(Lane.toppleForce(capMass: cap), 14_962, accuracy: 20)
        XCTAssertTrue(Lane.canTopple(capMass: cap, team: PushTeam(force: 15_300, reach: 1.5, lift: 0)))
        XCTAssertFalse(Lane.canTopple(capMass: cap, team: PushTeam(force: 14_000, reach: 1.5, lift: 0)))
        // 重力そうちの力は重さに比例するので、どの大きさの木にも届く
        let huge = Lane.capMass(stage: 10, pack: 0)
        XCTAssertTrue(Lane.canTopple(capMass: huge, team: PushTeam(force: 0, reach: 100, lift: 0.6)))
        XCTAssertFalse(Lane.canTopple(capMass: huge, team: Shop.team(owned: ["kid": 50, "big": 50])))
    }

    func testWeakTeamStopsAtTheTrees() {
        let weak = Shop.team(owned: ["kid": 12, "big": 2])
        let result = SnowPhysics.advance(mass: 4_240.9, pack: 0, team: weak, steps: 10, stage: 0)
        XCTAssertEqual(result.mass, 4_240.917826, accuracy: 0.02)
        XCTAssertEqual(result.stage, 0)
        // 何歩進めても、木の道の幅より大きくならない
        let long = SnowPhysics.advance(mass: 4_240.9, pack: 0, team: weak, steps: 5_000, stage: 0)
        XCTAssertLessThanOrEqual(long.mass, Lane.capMass(stage: 0, pack: 0) * 1.000001)
        XCTAssertEqual(long.stage, 0)
        XCTAssertEqual(long.materials, 0)
    }

    func testStrongTeamFellsTheTreesAndGetsMaterials() {
        let team = Shop.team(owned: ["kid": 12, "big": 2, "plank": 1])
        let result = SnowPhysics.advance(mass: 4_240, pack: 0, team: team, steps: 100, stage: 0)
        XCTAssertEqual(result.stage, 1, "木が倒れて、次の道に進む")
        XCTAssertEqual(result.materials, 600)
        XCTAssertEqual(result.mass, 4_293.93, accuracy: 4_293.93 * 0.02)
    }

    func testGravityTeamFellsBiggerTrees() {
        let team = Shop.team(owned: ["kid": 20, "big": 14, "plank": 1, "crawler": 1, "heavy": 1, "gravity": 12])
        let result = SnowPhysics.advance(mass: 1e8, pack: 0, team: team, steps: 300, stage: 2)
        XCTAssertEqual(result.stage, 3)
        XCTAssertEqual(result.materials, 38_400)
        XCTAssertEqual(result.mass, 1.89767e8, accuracy: 1.89767e8 * 0.03)
    }

    func testBlockedStateAndMaterialsInGameState() {
        var state = GameState()
        state.mass = state.laneCapMass
        XCTAssertTrue(state.isBlockedByTrees, "素手では木に負ける")
        XCTAssertEqual(state.toppleForceNeeded ?? 0, 14_962, accuracy: 20)
        state.owned = ["kid": 12, "big": 2, "plank": 1]
        XCTAssertFalse(state.isBlockedByTrees)
        state.addBonus(steps: 100)
        XCTAssertEqual(state.stage, 1)
        XCTAssertEqual(state.materials, 600)
        XCTAssertEqual(state.laneWidth, 15, accuracy: 1e-9)
    }

    func testMachinesNeedMaterials() {
        var state = GameState()
        state.totalSteps = 1_000_000
        state.peakDiameter = 2
        let plank = Shop.item("plank")!
        XCTAssertFalse(state.canBuy(plank), "資材がないと買えない")
        state.materials = 5
        XCTAssertTrue(state.buy(plank))
        XCTAssertEqual(state.materials, 0)
        XCTAssertEqual(state.materialPrice(plank), 6, "2つ目は少し高い")
    }

    func testSavesFromBeforeTreesKeepTheirProgress() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 木の道ができる前の保存（重さ 1e6 kg）は、通り過ぎた道を倒したことにする
        let json = "{\"version\": 4, \"onboarded\": true, \"mass\": 1e6, \"pack\": 0, \"totalSteps\": 100}"
        let state = try decoder.decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(state.stage, 2)
        XCTAssertEqual(state.mass, 1e6, accuracy: 1)
    }

    // MARK: 今日のがんばり

    func testTodayGrowthCountsOnlyToday() {
        var state = GameState()
        state.owned = ["kid": 5]
        state.apply(daily: ["2026-11-14": 0], todayKey: "2026-11-14")
        state.apply(daily: ["2026-11-14": 3_000], todayKey: "2026-11-14")
        let first = state.todayGrowth
        XCTAssertGreaterThan(first, 0.1, "今日歩いた分だけ、直径がふえる")
        // 次の日になると、その日の最初から数え直す
        state.apply(daily: ["2026-11-14": 3_000, "2026-11-15": 10], todayKey: "2026-11-15")
        XCTAssertLessThan(state.todayGrowth, first)
        XCTAssertGreaterThanOrEqual(state.todayGrowth, 0)
    }

    func testDailyGoalFraction() {
        XCTAssertEqual(DailyGoal.fraction(steps: 4_000), 0.5, accuracy: 1e-12)
        XCTAssertEqual(DailyGoal.fraction(steps: 0), 0)
        XCTAssertGreaterThan(DailyGoal.fraction(steps: 12_000), 1)
    }

    // MARK: 固める（タップ）

    func testTappingPacksTheSnowTighter() {
        var state = GameState()
        state.mass = 100
        let r0 = state.radius, d0 = state.density
        state.tapPack()
        XCTAssertEqual(state.mass, 100, "重さは変わらない")
        XCTAssertLessThan(state.radius, r0, "半径がほんの少し縮む")
        XCTAssertGreaterThan(state.radius, r0 * 0.995, "1回では、ほんの少しだけ")
        XCTAssertGreaterThan(state.density, d0, "密度が上がる")
        // 何回押しても、固められる限界がある（手で固める限界は 500 kg/m³）
        for _ in 0..<5_000 { state.tapPack() }
        XCTAssertEqual(state.density, SnowPhysics.packedBallDensity, accuracy: 1)
        XCTAssertGreaterThan(state.radius, r0 * 0.8)
    }

    // MARK: 買い物

    func testPricesGrowWithEachPurchase() {
        let kid = Shop.item("kid")!
        XCTAssertEqual(Shop.price(kid, owned: 0), 100)
        XCTAssertEqual(Shop.price(kid, owned: 1), 112)
        XCTAssertEqual(Shop.price(kid, owned: 2), 125)
    }

    func testBuyingSpendsStepsAndAddsForce() {
        var state = GameState()
        state.addBonus(steps: 250)
        let kid = Shop.item("kid")!
        XCTAssertEqual(state.points, 250)
        XCTAssertTrue(state.buy(kid))
        XCTAssertEqual(state.points, 150)
        XCTAssertTrue(state.buy(kid))
        XCTAssertEqual(state.points, 38)
        XCTAssertFalse(state.buy(kid), "足りないときは買えない")
        XCTAssertEqual(state.ownedCount("kid"), 2)
        XCTAssertEqual(state.team.force, SnowPhysics.bareHandForce + 2 * kid.force, accuracy: 1e-9)
        XCTAssertEqual(state.totalSteps, 250, "買い物をしても、雪玉は小さくならない")
    }

    func testItemsUnlockWhenTheBallIsBigEnough() {
        var state = GameState()
        let gravity = Shop.item("gravity")!
        XCTAssertTrue(state.isUnlocked(Shop.item("kid")!))
        XCTAssertFalse(state.isUnlocked(Shop.item("plank")!))
        XCTAssertFalse(state.isUnlocked(gravity))
        state.totalSteps = 10_000_000
        state.materials = 10_000
        XCTAssertFalse(state.buy(Shop.item("plank")!), "まだ解放されていない")
        state.peakDiameter = 15
        XCTAssertTrue(state.isUnlocked(gravity))
        XCTAssertTrue(state.buy(gravity))
        XCTAssertEqual(state.materials, 10_000 - 250, "資材も使う")
    }

    func testTeamFromOwnedItems() {
        let none = Shop.team(owned: [:])
        XCTAssertEqual(none.force, 60)
        XCTAssertEqual(none.reach, 0.7, accuracy: 1e-12)
        XCTAssertEqual(none.lift, 0)
        let machines = Shop.team(owned: ["kid": 3, "plank": 2])
        XCTAssertEqual(machines.force, 60 + 3 * 120 + 2 * 12_000, accuracy: 1e-9)
        XCTAssertEqual(machines.reach, 1.5, accuracy: 1e-12, "強い道具ほど1歩で遠くまで転がる")
        let gravity = Shop.team(owned: ["gravity": 5])
        XCTAssertEqual(gravity.lift, 0.2, accuracy: 1e-12)
        XCTAssertEqual(gravity.reach, 100 * pow(1.8, 5), accuracy: 1e-6)
        XCTAssertEqual(Shop.team(owned: ["gravity": 100]).lift, Shop.maxLift, accuracy: 1e-12)
    }

    func testDailyWalkingKeepsGrowingTheBallWithAGoodTeam() {
        var state = GameState()
        state.owned = ["kid": 10, "big": 3]
        let before = state.mass
        state.apply(daily: ["2026-11-14": 0], todayKey: "2026-11-14")
        state.apply(daily: ["2026-11-14": 7_000], todayKey: "2026-11-14")
        XCTAssertGreaterThan(state.mass, before * 100)
        XCTAssertGreaterThan(state.peakDiameter, state.diameter - 1e-9)
    }

    // MARK: 大きさの比べ方（目印）と表示

    func testReferencesAreOrderedAndNextIsFound() {
        let heights = ScaleReference.all.map(\.height)
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(ScaleReference.next(after: 0.02)?.name, "はっぱ")
        XCTAssertEqual(ScaleReference.next(after: 1.0)?.name, "ひと")
        XCTAssertEqual(ScaleReference.next(after: 1e7)?.name, "ちきゅう")
        XCTAssertNil(ScaleReference.next(after: 1e12))
    }

    func testLengthLabels() {
        XCTAssertEqual(formatLength(meters: 0.58), "約58cm")
        XCTAssertEqual(formatLength(meters: 0.02), "約2cm")
        XCTAssertEqual(formatLength(meters: 1.24), "約1.2m")
        XCTAssertEqual(formatLength(meters: 2_500), "約2.50km")
        XCTAssertEqual(formatLength(meters: 12_742_000), "約12,742km")
        XCTAssertEqual(formatLength(meters: 1.4e9), "約140万km")
    }

    func testMassLabels() {
        XCTAssertEqual(formatMass(kg: 0.0126), "約13g")
        XCTAssertEqual(formatMass(kg: 2.5), "約2.5kg")
        XCTAssertEqual(formatMass(kg: 150), "約150kg")
        XCTAssertEqual(formatMass(kg: 2_500), "約2.5t")
        XCTAssertEqual(formatMass(kg: 1.2e12), "約1.2×10¹²kg")
    }

    func testForceLabels() {
        XCTAssertEqual(formatForce(120), "120N")
        XCTAssertEqual(formatForce(15_300), "15.3kN")
        XCTAssertEqual(formatForce(6_000_000), "6.0MN")
        XCTAssertEqual(formatForce(2e10), "2.0×10¹⁰N")
    }

    func testSnowShapeIsAStableBumpyCircle() {
        let s = SnowShape.pristine(seed: 11)
        XCTAssertEqual(s.radii.count, SnowShape.pointCount)
        XCTAssertGreaterThan(s.radii.min() ?? 0, 0.9)
        XCTAssertLessThan(s.radii.max() ?? 2, 1.1)
        XCTAssertEqual(s, SnowShape.pristine(seed: 11))
    }
}
