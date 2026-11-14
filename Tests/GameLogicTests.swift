import XCTest
import simd

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

    func testBallRadiusGrowsUntilAchievementCap() {
        var previous = BallScale.radius(steps: 0)
        XCTAssertEqual(previous, BallScale.r0, accuracy: 0.0001)
        for steps in stride(from: 500, through: Snow.maxSteps, by: 500) {
            let r = BallScale.radius(steps: steps)
            XCTAssertGreaterThan(r, previous, "上限までは歩数が増えたら必ず大きくなる")
            previous = r
        }
        // 達成上限を超えたら、それ以上は大きくならない
        XCTAssertEqual(BallScale.radius(steps: Snow.maxSteps * 10), BallScale.radius(steps: Snow.maxSteps), accuracy: 1e-12)
        // 収束する漸近線ではなく、上限の直前まで伸びている（頭打ちで潰れていない）
        XCTAssertGreaterThan(BallScale.radius(steps: Snow.maxSteps) - BallScale.radius(steps: Snow.maxSteps - 2_500), 0.04)
        XCTAssertEqual(BallScale.fraction(0), 0, accuracy: 0.0001)
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

    func testBallStaysOnScreenAndKeepsGrowingVisually() {
        let base = 4.4
        var previous = 0.0
        for steps in [0, 500, 3_000, 8_000, 15_000, 22_000, Snow.maxSteps] {
            let r = BallScale.radius(steps: steps)
            let apparent = BallScale.apparentFraction(radius: r, baseDistance: base)
            XCTAssertLessThan(apparent, 0.86, "画面の幅に収まる")
            XCTAssertGreaterThan(apparent, previous, "見かけも大きくなり続ける")
            let d = BallScale.distance(radius: r, baseDistance: base)
            XCTAssertEqual(r / (d * 0.384), apparent, accuracy: 0.0001)
            previous = apparent
        }
    }

    // MARK: 達成上限と持ち越し

    func testSyncedStepsFillTheBallBeforeReserve() {
        var state = GameState()
        state.apply(daily: ["2026-11-14": 29_000], todayKey: "2026-11-14")
        let gained = state.apply(daily: ["2026-11-14": 32_000], todayKey: "2026-11-14")
        XCTAssertEqual(gained, 3_000)
        XCTAssertEqual(state.rollingSteps, Snow.maxSteps)
        XCTAssertEqual(state.reserveSteps, 2_000)
    }

    func testOldSaveWithoutReserveStillLoads() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(GameState.self, from: Data("{\"rollingSteps\": 900}".utf8))
        XCTAssertEqual(state.reserveSteps, 0)
        XCTAssertEqual(state.rollingSteps, 900)
    }

    // MARK: ゆきだま

    func testCannotMakePieceBelowMinimum() {
        var state = GameState()
        state.addBonus(steps: Snow.minimumSteps - 1)
        var rng = SplitMix64(seed: 1)
        XCTAssertNil(state.makePiece(using: &rng))
        XCTAssertTrue(state.stock.isEmpty)
        XCTAssertEqual(state.rollingSteps, Snow.minimumSteps - 1)
    }

    func testMakePieceMovesRollingBallToStock() {
        var state = GameState()
        state.addBonus(steps: 3_400)
        var rng = SplitMix64(seed: 7)
        let piece = state.makePiece(using: &rng)
        XCTAssertEqual(piece?.steps, 3_400)
        XCTAssertEqual(state.stock.count, 1)
        XCTAssertEqual(state.rollingSteps, 0)
        XCTAssertEqual(state.totalSteps, 3_400)
    }

    func testStepsBeyondCapAreCarriedToNextBall() {
        var state = GameState()
        state.addBonus(steps: Snow.maxSteps + 5_000)
        XCTAssertEqual(state.rollingSteps, Snow.maxSteps)
        XCTAssertEqual(state.reserveSteps, 5_000)
        XCTAssertTrue(state.isAtCap)
        state.addBonus(steps: 1_000)
        XCTAssertEqual(state.reserveSteps, 6_000)
        var rng = SplitMix64(seed: 5)
        let piece = state.makePiece(using: &rng)
        XCTAssertEqual(piece?.steps, Snow.maxSteps)
        XCTAssertEqual(state.rollingSteps, 6_000)
        XCTAssertEqual(state.reserveSteps, 0)
    }

    func testCarryOverIsAlsoCappedPerBall() {
        var state = GameState()
        state.addBonus(steps: Snow.maxSteps * 2 + 7_000)
        var rng = SplitMix64(seed: 6)
        _ = state.makePiece(using: &rng)
        XCTAssertEqual(state.rollingSteps, Snow.maxSteps)
        XCTAssertEqual(state.reserveSteps, 7_000)
    }

    func testArtworkPiecesMoveBetweenStockAndArtwork() {
        var state = GameState()
        state.addBonus(steps: 1_000)
        var rng = SplitMix64(seed: 2)
        let piece = state.makePiece(using: &rng)!
        var art = state.newArtwork()
        let taken = state.takeFromStock(id: piece.id)
        XCTAssertNotNil(taken)
        XCTAssertTrue(state.stock.isEmpty)
        art.placements.append(Placement(piece: taken!, position: SIMD3<Float>(0, taken!.radius, 0)))
        state.saveArtwork(art)
        XCTAssertEqual(state.artworks.count, 1)
        XCTAssertEqual(state.totalPieceCount, 1)
        // 作品を消すとゆきだまは手元に戻る
        state.deleteArtwork(id: art.id)
        XCTAssertEqual(state.stock.count, 1)
        XCTAssertTrue(state.artworks.isEmpty)
    }

    func testCodableRoundTripKeepsShapesAndArtworks() throws {
        var state = GameState()
        state.addBonus(steps: 4_000)
        var rng = SplitMix64(seed: 3)
        var piece = state.makePiece(using: &rng)!
        piece.shape.cutBlade(rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), planeX: -0.5, bandLow: -3, bandHigh: 3)
        piece.shape.setTint(SIMD3<Float>(1, 0, 0))
        state.updateStock(id: piece.id, shape: piece.shape)
        var art = state.newArtwork()
        art.placements = [Placement(piece: piece, position: SIMD3<Float>(1, 2, 3), rotation: SIMD4<Float>(0, 0.7071, 0, 0.7071))]
        state.saveArtwork(art)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GameState.self, from: try encoder.encode(state))
        XCTAssertEqual(decoded.stock.first?.shape, piece.shape)
        XCTAssertEqual(decoded.artworks.first?.placements.first?.position, SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(decoded.totalSteps, 4_000)

        // 将来の項目が足りない古いファイルでも読める
        let old = try decoder.decode(GameState.self, from: Data("{\"rollingSteps\": 123}".utf8))
        XCTAssertEqual(old.rollingSteps, 123)
        XCTAssertTrue(old.stock.isEmpty)
    }

    // MARK: 成形しながら転がす

    func testRollingBallKeepsItsShapeAndGrowsWithUniformThickness() {
        var state = GameState()
        state.addBonus(steps: 1_000)
        let r1 = Float(BallScale.radius(steps: 1_000))
        var shape = state.rollingShape
        shape.cutBlade(rotation: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)), planeX: -0.5, bandLow: -3, bandHigh: 3)
        state.updateRolling(shape: shape)
        let before = state.rollingShape

        state.addBonus(steps: 4_000)
        let r2 = Float(BallScale.radius(steps: 5_000))
        XCTAssertGreaterThan(r2, r1)
        for k in stride(from: 0, to: before.radii.count, by: 211) {
            let delta = r2 * state.rollingShape.radii[k] - r1 * before.radii[k]
            XCTAssertEqual(delta, r2 - r1, accuracy: 1e-3, "どこも同じ厚さだけ大きくなる")
        }
        XCTAssertNotEqual(state.rollingShape, before)
    }

    func testMakePieceTakesTheShapedBallAndStartsANewOne() {
        var state = GameState()
        state.addBonus(steps: 2_000)
        var shape = state.rollingShape
        shape.setTint(SIMD3<Float>(0, 1, 0))
        state.updateRolling(shape: shape)
        var rng = SplitMix64(seed: 4)
        let piece = state.makePiece(using: &rng)
        XCTAssertEqual(piece?.shape.tint, [0, 255, 0])
        XCTAssertEqual(state.rollingShape.tint, [255, 255, 255], "次の雪玉は白いまっさらな玉")
        XCTAssertEqual(state.rollingSteps, 0)
    }

    func testDiametersAreReported() {
        var state = GameState()
        state.addBonus(steps: 3_000)
        XCTAssertGreaterThan(state.rollingDiameter, 0.5)
        XCTAssertEqual(state.rollingDiameter, 2 * BallScale.radius(steps: 3_000) * Double(state.rollingShape.maxExtent), accuracy: 1e-9)
        var rng = SplitMix64(seed: 1)
        let piece = state.makePiece(using: &rng)!
        XCTAssertGreaterThan(piece.diameter, 0.5)
    }
}
