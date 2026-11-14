import XCTest

final class GameLogicTests: XCTestCase {
    // MARK: サイズ段階

    func testTierThresholds() {
        XCTAssertNil(SizeTier.tier(forSteps: 0))
        XCTAssertNil(SizeTier.tier(forSteps: 499))
        XCTAssertEqual(SizeTier.tier(forSteps: 500), .s)
        XCTAssertEqual(SizeTier.tier(forSteps: 2_999), .s)
        XCTAssertEqual(SizeTier.tier(forSteps: 3_000), .m)
        XCTAssertEqual(SizeTier.tier(forSteps: 8_000), .l)
        XCTAssertEqual(SizeTier.tier(forSteps: 15_000), .xl)
        XCTAssertEqual(SizeTier.tier(forSteps: 99_999), .xl)
    }

    func testCollectionTotal() {
        // ふつう3種×4 + めずらしい3種×3 + レア2種×2 + とくべつ2種×1
        XCTAssertEqual(GameState.totalKindCount, 12 + 9 + 4 + 2)
    }

    // MARK: 歩数の台帳

    func testFirstSyncCreditsOnlyToday() {
        var state = GameState()
        let gained = state.apply(daily: ["2026-11-12": 8_000, "2026-11-13": 6_000, "2026-11-14": 1_200], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 1_200)
        XCTAssertEqual(state.rollingSteps, 1_200)
        XCTAssertTrue(state.initialized)
    }

    func testRepeatedSyncDoesNotDoubleCount() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        let again = state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        XCTAssertEqual(again, 0)
        XCTAssertEqual(state.rollingSteps, 1_000)
    }

    func testOnlyTheDifferenceIsAdded() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 1_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 1_750], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 750)
        XCTAssertEqual(state.rollingSteps, 1_750)
        XCTAssertEqual(state.totalSteps, 1_750)
    }

    func testDecreasingStepsAreIgnored() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 2_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 1_500], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 0)
        XCTAssertEqual(state.rollingSteps, 2_000)
        // 戻らず、その後に増えた分だけが加算される
        let later = state.apply(daily: ["2026-11-14": 2_300], todayKey: "2026-11-14")
        XCTAssertEqual(later, 300)
    }

    func testNewDayCountsFromZero() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 4_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 4_000, "2026-11-15": 900], todayKey: "2026-11-15")
        XCTAssertEqual(gained, 900)
        XCTAssertEqual(state.rollingSteps, 4_900)
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

    // MARK: 完成

    func testCannotCompleteBelowMinimum() {
        var state = GameState()
        state.addBonus(steps: 499)
        var rng = SplitMix64(seed: 1)
        XCTAssertNil(state.complete(using: &rng))
        XCTAssertEqual(state.rollingSteps, 499)
    }

    func testCompleteResetsAndRecords() {
        var state = GameState()
        state.addBonus(steps: 3_400)
        var rng = SplitMix64(seed: 7)
        let result = state.complete(using: &rng)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.snowman.tier, .m)
        XCTAssertEqual(result?.snowman.steps, 3_400)
        XCTAssertEqual(result?.isNewKind, true)
        XCTAssertEqual(state.rollingSteps, 0)
        XCTAssertEqual(state.snowmen.count, 1)
        XCTAssertEqual(state.totalSteps, 3_400)
    }

    func testSecondOfSameKindIsNotNew() {
        var state = GameState()
        state.snowmen = [Snowman(id: UUID(), species: .plain, tier: .s, steps: 600, madeAt: Date(), decorations: [])]
        XCTAssertTrue(state.hasMade(species: .plain, tier: .s))
        XCTAssertFalse(state.hasMade(species: .plain, tier: .m))
        XCTAssertEqual(state.discoveredKindCount, 1)
    }

    // MARK: 種類と飾りの抽選

    func testSmallSnowmenAreAlwaysCommon() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<500 {
            let species = SnowmanFactory.pickSpecies(tier: .s, using: &rng)
            XCTAssertEqual(species.rarity, .common)
        }
    }

    func testSpecialSpeciesOnlyAtXL() {
        var rng = SplitMix64(seed: 99)
        var seenSpecialAtXL = false
        for _ in 0..<2_000 {
            for tier in [SizeTier.s, .m, .l] {
                XCTAssertNotEqual(SnowmanFactory.pickSpecies(tier: tier, using: &rng).rarity, .special)
            }
            if SnowmanFactory.pickSpecies(tier: .xl, using: &rng).rarity == .special { seenSpecialAtXL = true }
        }
        XCTAssertTrue(seenSpecialAtXL)
    }

    func testRareAppearsFromL() {
        var rng = SplitMix64(seed: 5)
        for _ in 0..<1_000 {
            XCTAssertNotEqual(SnowmanFactory.pickSpecies(tier: .m, using: &rng).rarity, .rare)
        }
    }

    func testDecorationsRespectSpeciesAndCount() {
        var rng = SplitMix64(seed: 2026)
        for species in Species.allCases {
            for tier in SizeTier.allCases {
                for _ in 0..<50 {
                    let decorations = SnowmanFactory.pickDecorations(species: species, tier: tier, using: &rng)
                    let slots = decorations.map { $0.kind.slot }
                    XCTAssertEqual(Set(slots).count, slots.count, "同じ枠に2つ付かない")
                    XCTAssertTrue(decorations.allSatisfy { species.allows($0.kind) })
                    XCTAssertTrue(decorations.allSatisfy { $0.hue >= 0 && $0.hue < Decoration.hueCount })
                    XCTAssertLessThanOrEqual(decorations.count, SnowmanFactory.decorationCountRange(for: tier).upperBound)
                    XCTAssertGreaterThanOrEqual(decorations.count, 1)
                }
            }
        }
    }

    func testSeededFactoryIsDeterministic() {
        var a = SplitMix64(seed: 1234)
        var b = SplitMix64(seed: 1234)
        let date = Date(timeIntervalSince1970: 0)
        let x = SnowmanFactory.make(tier: .l, steps: 9_000, date: date, using: &a)
        let y = SnowmanFactory.make(tier: .l, steps: 9_000, date: date, using: &b)
        XCTAssertEqual(x.species, y.species)
        XCTAssertEqual(x.decorations, y.decorations)
    }

    func testNames() {
        let s = Snowman(id: UUID(), species: .usagi, tier: .l, steps: 9_000, madeAt: Date(), decorations: [])
        XCTAssertEqual(s.name, "おおきなゆきうさぎ")
        let k = Snowman(id: UUID(), species: .plain, tier: .xl, steps: 20_000, madeAt: Date(), decorations: [])
        XCTAssertEqual(k.name, "ばかでかい雪だるま")
    }

    // MARK: 保存

    func testCodableRoundTripAndOldFiles() throws {
        var state = GameState()
        state.addBonus(steps: 4_000)
        var rng = SplitMix64(seed: 3)
        _ = state.complete(using: &rng)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(state)
        let decoded = try decoder.decode(GameState.self, from: data)
        XCTAssertEqual(decoded.snowmen.count, 1)
        XCTAssertEqual(decoded.totalSteps, 4_000)

        // 将来の項目が足りない古いファイルでも読める
        let minimal = Data("{\"rollingSteps\": 123}".utf8)
        let old = try decoder.decode(GameState.self, from: minimal)
        XCTAssertEqual(old.rollingSteps, 123)
        XCTAssertTrue(old.snowmen.isEmpty)
    }

    func testStorageSaveAndLoad() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("yukikoro-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = GameState()
        state.onboarded = true
        state.addBonus(steps: 777)
        XCTAssertTrue(GameStorage.save(state, to: url))
        let loaded = GameStorage.load(from: url)
        XCTAssertEqual(loaded.rollingSteps, 777)
        XCTAssertTrue(loaded.onboarded)
    }

    // MARK: 雪玉の成長モデル

    func testBallRadiusIsMonotonicAndBounded() {
        var previous = BallScale.radius(steps: 0)
        XCTAssertEqual(previous, BallScale.r0, accuracy: 0.002)
        for steps in stride(from: 100, through: 100_000, by: 100) {
            let r = BallScale.radius(steps: steps)
            XCTAssertGreaterThan(r, previous, "歩数が増えたら必ず大きくなる")
            XCTAssertLessThan(r, BallScale.maxRadius, "上限を超えない")
            previous = r
        }
        XCTAssertEqual(BallScale.fraction(0), 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(BallScale.fraction(1_000_000), 1)
        XCTAssertGreaterThan(BallScale.fraction(1_000_000), 0.99)
    }

    func testBallGrowthSlowsDownInRadius() {
        // 半径の増え方は後半ほど小さくなる（べき乗 + 頭打ち）
        let early = BallScale.radius(steps: 3_000) - BallScale.radius(steps: 500)
        let late = BallScale.radius(steps: 15_000) - BallScale.radius(steps: 12_500)
        XCTAssertGreaterThan(early / 2_500, late / 2_500)
    }

    func testVolumeGrowsFasterThanDistance() {
        // 重くなるほど同じ距離で付く雪が増える: 距離が2倍なら体積は2倍より大きい（頭打ち前）
        for s in [500, 1_000, 2_000, 4_000] {
            let v1 = BallScale.volume(radius: BallScale.rawRadius(steps: s)) - BallScale.volume(radius: BallScale.r0)
            let v2 = BallScale.volume(radius: BallScale.rawRadius(steps: 2 * s)) - BallScale.volume(radius: BallScale.r0)
            XCTAssertGreaterThan(v2 / v1, 2.0, "s=\(s)")
        }
    }

    func testTierRadiiAreReasonablySpaced() {
        let radii = SizeTier.allCases.map { BallScale.radius(steps: $0.minSteps) }
        for i in 1..<radii.count { XCTAssertGreaterThan(radii[i], radii[i - 1] + 0.1) }
        XCTAssertLessThan(radii.last ?? 0, BallScale.maxRadius)
    }
}
