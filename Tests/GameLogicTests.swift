import XCTest

final class GameLogicTests: XCTestCase {
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

    // MARK: 保存

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

    func testBallStartsAtOneCentimeterRadiusAndNeverStopsGrowing() {
        XCTAssertEqual(BallScale.radius(steps: 0), 0.01, accuracy: 1e-12, "0歩は半径1cm")
        var previous = BallScale.radius(steps: 0)
        for steps in [1, 10, 100, 1_000, 10_000, 30_000, 100_000, 1_000_000, 100_000_000, 10_000_000_000] {
            let r = BallScale.radius(steps: steps)
            XCTAssertGreaterThan(r, previous, "歩けば必ず大きくなる（上限はない）")
            previous = r
        }
        // 3万歩を超えても、まだ伸びている
        XCTAssertGreaterThan(BallScale.radius(steps: 60_000) - BallScale.radius(steps: 30_000), 0.1)
    }

    func testStepsForDiameterIsTheInverseOfTheRadius() {
        for d in [0.05, 0.3, 1.7, 8, 40, 3_776] {
            let steps = BallScale.steps(forDiameter: d)
            XCTAssertGreaterThanOrEqual(BallScale.diameter(steps: steps, extent: 1), d - 1e-9, "d=\(d)")
            if steps > 0 {
                XCTAssertLessThan(BallScale.diameter(steps: steps - 1, extent: 1), d, "d=\(d) ぎりぎり")
            }
        }
        XCTAssertEqual(BallScale.steps(forDiameter: 0.01), 0, "最初から超えている大きさは0歩")
    }

    func testBallGrowthSlowsDownInRadius() {
        // 半径の増え方は後半ほど小さくなる（べき乗）
        let early = BallScale.radius(steps: 3_000) - BallScale.radius(steps: 500)
        let late = BallScale.radius(steps: 30_000) - BallScale.radius(steps: 27_500)
        XCTAssertGreaterThan(early / 2_500, late / 2_500)
    }

    func testVolumeGrowsFasterThanDistance() {
        // 重くなるほど同じ距離で付く雪が増える: 距離が2倍なら体積は2倍より大きい（上限の手前まで）
        for s in [500, 1_000, 2_000, 4_000, 8_000, 15_000] {
            let v1 = BallScale.volume(radius: BallScale.radius(steps: s)) - BallScale.volume(radius: BallScale.r0)
            let v2 = BallScale.volume(radius: BallScale.radius(steps: 2 * s)) - BallScale.volume(radius: BallScale.r0)
            XCTAssertGreaterThan(v2 / v1, 2.0, "s=\(s)")
        }
    }

    // MARK: 上限なし

    func testStepsAreNeverCapped() {
        var state = GameState()
        state.addBonus(steps: 30_000)
        state.addBonus(steps: 5_000)
        XCTAssertEqual(state.rollingSteps, 35_000)
        XCTAssertEqual(state.totalSteps, 35_000)
        state.addBonus(steps: 2_000_000)
        XCTAssertEqual(state.rollingSteps, 2_035_000)
        XCTAssertGreaterThan(state.diameter, 10)
    }

    func testSyncedStepsKeepGrowingTheBall() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 29_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 32_000], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 3_000)
        XCTAssertEqual(state.rollingSteps, 32_000)
    }

    func testOldSavesStillLoadAndKeepTheirSteps() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // 以前の保存データ（持ち越し・ゆきだま・作品つき）は、歩数だけ引き継ぐ
        let json = "{\"rollingSteps\": 900, \"reserveSteps\": 100, \"totalSteps\": 5000, \"stock\": [], \"artworks\": []}"
        let state = try decoder.decode(GameState.self, from: Data(json.utf8))
        XCTAssertEqual(state.rollingSteps, 1_000, "持ち越しは雪玉に足される")
        XCTAssertEqual(state.totalSteps, 5_000)
        let minimal = try decoder.decode(GameState.self, from: Data("{\"rollingSteps\": 123}".utf8))
        XCTAssertEqual(minimal.rollingSteps, 123)
    }

    func testCodableRoundTrip() throws {
        var state = GameState()
        state.addBonus(steps: 4_000)
        state.onboarded = true
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameState.self, from: try encoder.encode(state))
        XCTAssertEqual(decoded.rollingSteps, 4_000)
        XCTAssertEqual(decoded.totalSteps, 4_000)
        XCTAssertTrue(decoded.onboarded)
    }

    // MARK: 大きさの比べ方（目印）

    func testReferencesAreOrderedAndNextIsFound() {
        let heights = ScaleReference.all.map(\.height)
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(ScaleReference.next(after: 0.02)?.name, "はっぱ")
        XCTAssertEqual(ScaleReference.next(after: 1.0)?.name, "ひと")
        XCTAssertNil(ScaleReference.next(after: 100_000))
    }

    func testStageScaleGrowsWithTheBallThenZoomsOut() {
        let width: CGFloat = 390
        let full = width * StageScale.maxBallFraction
        // 小さいうちは、決まった縮尺で雪玉が育つ
        let a = StageScale.pixelsPerMeter(diameter: 0.02, width: width)
        let b = StageScale.pixelsPerMeter(diameter: 0.2, width: width)
        XCTAssertEqual(a, b, accuracy: 1e-6)
        XCTAssertEqual(0.2 * a, 0.2 * b, accuracy: 1e-6)
        // 画面いっぱいになったあとは、雪玉の見た目の大きさは変わらず、縮尺が小さくなる
        for d in [0.5, 1, 10, 1_000, 100_000] {
            let s = StageScale.pixelsPerMeter(diameter: d, width: width)
            XCTAssertEqual(CGFloat(d) * s, full, accuracy: 0.01, "d=\(d)")
        }
        XCTAssertLessThan(StageScale.pixelsPerMeter(diameter: 100, width: width), StageScale.pixelsPerMeter(diameter: 1, width: width))
    }

    func testReferenceOpacityFadesWhenTooSmallOrTooBig() {
        let limit: CGFloat = 240
        XCTAssertEqual(StageScale.opacity(forHeightPixels: 4, limitPixels: limit), 0, accuracy: 1e-9)
        XCTAssertEqual(StageScale.opacity(forHeightPixels: 80, limitPixels: limit), 1, accuracy: 1e-9)
        XCTAssertEqual(StageScale.opacity(forHeightPixels: 200, limitPixels: limit), 0, accuracy: 1e-9)
        let mid = StageScale.opacity(forHeightPixels: 24, limitPixels: limit)
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, 1)
    }

    func testSomeReferenceIsAlwaysVisible() {
        // どの大きさの雪玉でも、見える目印が1つはある（大きさの比べがいがなくならない）
        let width: CGFloat = 390
        let limit = width * StageScale.maxBallFraction
        var d = 0.02
        while d < 9_000 {
            let s = StageScale.pixelsPerMeter(diameter: d, width: width)
            let best = ScaleReference.all.map { StageScale.opacity(forHeightPixels: CGFloat($0.height) * s, limitPixels: limit) }.max() ?? 0
            XCTAssertGreaterThan(best, 0.3, "d=\(d)")
            d *= 1.05
        }
    }

    func testDiameterLabels() {
        XCTAssertEqual(formatLength(meters: 0.58), "約58cm")
        XCTAssertEqual(formatLength(meters: 0.02), "約2cm")
        XCTAssertEqual(formatLength(meters: 1.24), "約1.2m")
        XCTAssertEqual(formatLength(meters: 2_500), "約2.50km")
    }

    func testSnowShapeIsAStableBumpyCircle() {
        let s = SnowShape.pristine(seed: 11)
        XCTAssertEqual(s.radii.count, SnowShape.pointCount)
        XCTAssertGreaterThan(s.radii.min() ?? 0, 0.9)
        XCTAssertLessThan(s.radii.max() ?? 2, 1.1)
        XCTAssertEqual(s, SnowShape.pristine(seed: 11))
    }
}
