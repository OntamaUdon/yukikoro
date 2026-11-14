import XCTest
import simd

final class SculptTests: XCTestCase {
    /// 向きがいちばん近い頂点
    private func index(of direction: SIMD2<Float>) -> Int {
        var best = 0
        var bestDot: Float = -2
        let n = simd_normalize(direction)
        for (k, d) in SnowShape.directions.enumerated() {
            let v = simd_dot(d, n)
            if v > bestDot { bestDot = v; best = k }
        }
        return best
    }

    func testPristineShapeIsNearlyWhiteCircle() {
        let s = SnowShape.pristine(seed: 4)
        XCTAssertEqual(s.radii.count, SnowShape.pointCount)
        XCTAssertEqual(s.tint, [255, 255, 255])
        XCTAssertGreaterThan(s.radii.min() ?? 0, 0.9)
        XCTAssertLessThan(s.radii.max() ?? 2, 1.1)
        XCTAssertFalse(s.isModified)
    }

    // MARK: 刃


    // MARK: 線で切る

    func testLineCutRemovesTheFarSideAndLeavesAFlatEdge() {
        var s = SnowShape.pristine(seed: 1)
        let left = index(of: SIMD2<Float>(-1, 0))
        let right = index(of: SIMD2<Float>(1, 0))
        let rightBefore = s.radii[right]
        XCTAssertTrue(s.cutLine(normal: SIMD2<Float>(-1, 0), depth: 0.5))
        XCTAssertEqual(s.radii[left], 0.5, accuracy: 0.02, "線の位置まで削れる")
        XCTAssertEqual(s.radii[right], rightBefore, accuracy: 1e-6, "反対側は変わらない")
        for (k, d) in SnowShape.directions.enumerated() where d.x < -0.4 {
            XCTAssertGreaterThanOrEqual(s.radii[k] * -d.x, -0.01)
            XCTAssertLessThanOrEqual(s.radii[k] * -d.x, 0.5 + 0.01, "切り口の外へは出ない")
        }
    }

    func testLineCutNeverGoesCloserThanTheMinimumDepth() {
        var s = SnowShape.pristine(seed: 5)
        s.cutLine(normal: SIMD2<Float>(0, 1), depth: 0.0)
        XCTAssertGreaterThanOrEqual(s.radii.min() ?? 0, SnowShape.minCutDepth - 0.01)
    }

    func testStrokeCutsTheSideAwayFromTheCenter() {
        let shape = SnowShape.pristine(seed: 2)
        // 雪玉の左側を、上から下へなぞる（x = -0.5 の縦線）
        let result = LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(-0.5, 1.5), to: SIMD2<Float>(-0.5, -1.5))
        XCTAssertNotNil(result)
        let left = index(of: SIMD2<Float>(-1, 0))
        let right = index(of: SIMD2<Float>(1, 0))
        XCTAssertEqual(result?.shape.radii[left] ?? 0, 0.5, accuracy: 0.02)
        XCTAssertEqual(result?.shape.radii[right] ?? 0, shape.radii[right], accuracy: 1e-6)
        // 破片は、切り口の線と元の輪郭で囲まれている
        let fragment = result?.fragment ?? []
        XCTAssertGreaterThan(fragment.count, 6)
        XCTAssertLessThanOrEqual(fragment.map(\.x).max() ?? 9, -0.49)
    }

    func testStrokeDirectionDoesNotMatterAndCenterSideIsKept() {
        let shape = SnowShape.pristine(seed: 2)
        let down = LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(0.6, 1.5), to: SIMD2<Float>(0.6, -1.5))
        let up = LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(0.6, -1.5), to: SIMD2<Float>(0.6, 1.5))
        XCTAssertEqual(down?.shape, up?.shape, "どちら向きになぞっても、中心がない側が切れる")
        let right = index(of: SIMD2<Float>(1, 0))
        XCTAssertEqual(down?.shape.radii[right] ?? 0, 0.6, accuracy: 0.02)
    }

    func testStrokeThroughTheCenterStopsAtTheMinimumDepth() {
        let shape = SnowShape.pristine(seed: 2)
        let result = LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(0, 1.5), to: SIMD2<Float>(0, -1.5))
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result?.shape.radii.min() ?? 0, SnowShape.minCutDepth - 0.01, "雪玉は消えない")
    }

    func testStrokeFollowsTheBallRotation() {
        // 雪玉が反時計回りに90°回っているとき、画面の左側の面は、元の形の「上向き」の面
        let shape = SnowShape.pristine(seed: 6)
        let result = LineCut.apply(to: shape, angle: .pi / 2, from: SIMD2<Float>(-0.5, 1.5), to: SIMD2<Float>(-0.5, -1.5))
        let top = index(of: SIMD2<Float>(0, 1))
        XCTAssertEqual(result?.shape.radii[top] ?? 0, 0.5, accuracy: 0.03)
        let left = index(of: SIMD2<Float>(-1, 0))
        XCTAssertGreaterThan(result?.shape.radii[left] ?? 0, 0.9)
    }

    func testTinyStrokesAndMissesDoNothing() {
        let shape = SnowShape.pristine(seed: 2)
        XCTAssertNil(LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(0, 0), to: SIMD2<Float>(0.05, 0)))
        // 雪玉から遠く離れた線は、何も切らない
        XCTAssertNil(LineCut.apply(to: shape, angle: 0, from: SIMD2<Float>(-3, 1), to: SIMD2<Float>(-3, -1)))
    }

    func testHistoryUndoesInOrderAndIsLimited() {
        var history = ShapeHistory()
        XCTAssertFalse(history.canUndo)
        let a = SnowShape.pristine(seed: 1), b = SnowShape.pristine(seed: 2)
        history.push(a)
        history.push(b)
        XCTAssertEqual(history.pop(), b)
        XCTAssertEqual(history.pop(), a)
        XCTAssertNil(history.pop())
        for i in 0..<40 { history.push(SnowShape.pristine(seed: UInt32(i))) }
        XCTAssertEqual(history.count, ShapeHistory.limit)
    }

    func testStageIsCreatedOnceAndClearedBackToTheTray() {
        var state = GameState()
        XCTAssertTrue(state.artworks.isEmpty)
        var stage = state.ensureStage()
        XCTAssertEqual(state.artworks.count, 1)
        XCTAssertEqual(state.ensureStage().id, stage.id, "舞台は1つだけ")
        let piece = SnowPiece(steps: 800, madeAt: Date(), shape: .pristine(seed: 1))
        stage.placements = [Placement(piece: piece, position: SIMD2<Float>(0, piece.radius))]
        state.saveArtwork(stage)
        XCTAssertEqual(state.stock.count, 0)
        state.clearStage()
        XCTAssertEqual(state.stock.count, 1, "片付けると手元に戻る")
        XCTAssertTrue(state.artworks[0].placements.isEmpty)
        XCTAssertEqual(state.artworks.count, 1)
    }

    // MARK: 色

    func testTintIsOneColorForTheWholeBall() {
        var s = SnowShape.pristine(seed: 5)
        s.setTint(SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(s.tint, [255, 0, 0])
        XCTAssertEqual(s.tintRGB.x, 1, accuracy: 1e-6)
        XCTAssertTrue(s.isModified)
    }

    // MARK: 成長（厚さ一定）

    func testGrowAddsUniformThickness() {
        var s = SnowShape.pristine(seed: 7)
        s.cutLine(normal: SIMD2<Float>(-1, 0), depth: 0.5)
        let before = s
        let old: Float = 0.5, new: Float = 0.7
        s.grow(fromRadius: old, toRadius: new)
        for k in 0..<s.radii.count {
            XCTAssertEqual(new * s.radii[k] - old * before.radii[k], new - old, accuracy: 1e-4)
        }
    }

    // MARK: 保存

    func testShapeCodableRoundTrip() throws {
        var s = SnowShape.pristine(seed: 6)
        s.cutLine(normal: SIMD2<Float>(-1, 0), depth: 0.5)
        s.setTint(SIMD3<Float>(0, 0, 1))
        let decoded = try JSONDecoder().decode(SnowShape.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testOldThreeDimensionalShapeBecomesAFreshBall() throws {
        // 以前の形式（頂点が多い）のデータは、まっさらな玉になる
        let radii = [Float](repeating: 1, count: 8_000)
        let encoded = radii.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
        let json = "{\"seed\": 3, \"radii\": \"\(encoded)\"}"
        let decoded = try JSONDecoder().decode(SnowShape.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, SnowShape.pristine(seed: 3))
    }

    // MARK: 成形の操作

    // MARK: 直径

    func testDiameterFormatAndMeasure() {
        XCTAssertEqual(formatLength(meters: 0.58), "約58cm")
        XCTAssertEqual(formatLength(meters: 1.24), "約1.2m")
        XCTAssertEqual(formatLength(meters: 0.02), "約2cm")
        XCTAssertEqual(BallScale.radius(steps: 0), 0.01, accuracy: 1e-12, "0歩は半径1cm")
        XCTAssertEqual(BallScale.diameter(steps: 0, extent: 1), 0.02, accuracy: 1e-12)
        XCTAssertGreaterThan(BallScale.diameter(steps: 10_000, extent: 1), 1)
    }

    func testDisplayFractionKeepsSmallBallsVisible() {
        XCTAssertGreaterThan(BallScale.displayFraction(radius: 0.01), 0.05)
        XCTAssertEqual(BallScale.displayFraction(radius: BallScale.maxRadius), 1, accuracy: 1e-9)
        var previous = 0.0
        for steps in stride(from: 0, through: Snow.maxSteps, by: 1_000) {
            let f = BallScale.displayFraction(radius: BallScale.radius(steps: steps))
            XCTAssertGreaterThanOrEqual(f, previous)
            previous = f
        }
    }

    // MARK: 作品

    private func piece(radius: Float) -> SnowPiece {
        var steps = 0
        while Float(BallScale.radius(steps: steps)) < radius, steps < Snow.maxSteps { steps += 50 }
        return SnowPiece(steps: steps, madeAt: Date(), shape: .pristine(seed: 1))
    }

    private func placement(_ radius: Float, x: Float, y: Float) -> Placement {
        Placement(piece: piece(radius: radius), position: SIMD2<Float>(x, y))
    }

    func testSettleOnGroundAndOnTopOfAnother() {
        let big = placement(1.0, x: 0, y: 1.0)
        let r = big.piece.radius
        XCTAssertEqual(Artwork.settleHeight(x: 5, radius: 0.5, among: [big]), 0.5, accuracy: 1e-5, "離れていれば地面に置く")
        let onTop = Artwork.settleHeight(x: 0, radius: 0.5, among: [big])
        XCTAssertEqual(onTop, big.position.y + (r + 0.5) * Artwork.contactFactor, accuracy: 1e-4, "真上なら上に積む")
        let beside = Artwork.settleHeight(x: r * 0.8, radius: 0.5, among: [big])
        XCTAssertGreaterThan(beside, 0.5)
        XCTAssertLessThan(beside, onTop)
    }

    func testCameraConvertsBothWaysAndFitsEverything() {
        let a = placement(0.8, x: -2, y: 0.8)
        let b = placement(1.2, x: 3, y: 1.2)
        let size = CGSize(width: 390, height: 800)
        let cam = ArtworkCamera.fitting([a, b], size: size)
        for p in [a, b] {
            let c = cam.point(p.position)
            XCTAssertGreaterThan(c.x - CGFloat(p.reach) * cam.scale, 0)
            XCTAssertLessThan(c.x + CGFloat(p.reach) * cam.scale, size.width)
            XCTAssertGreaterThan(c.y - CGFloat(p.reach) * cam.scale, 0)
        }
        let w = SIMD2<Float>(1.25, 0.6)
        let back = cam.world(cam.point(w))
        XCTAssertEqual(back.x, w.x, accuracy: 1e-4)
        XCTAssertEqual(back.y, w.y, accuracy: 1e-4)
    }

    func testComposeDragMovesSnapsAndSelects() {
        let model = ComposeModel(artwork: Artwork(name: "t", createdAt: Date(), updatedAt: Date()))
        let a = piece(radius: 0.5)
        model.add(a)
        let start = model.artwork.placements[0].position
        XCTAssertEqual(model.selectedID, a.id)
        XCTAssertTrue(model.beginDrag(at: start))
        model.drag(to: start + SIMD2<Float>(1, 0.05))
        model.endDrag()
        let p = model.artwork.placements[0]
        XCTAssertEqual(p.position.x, start.x + 1, accuracy: 1e-5)
        XCTAssertEqual(p.position.y, a.radius, accuracy: 1e-5, "地面の近くで離すとぴたっと乗る")

        // 高く持ち上げて離すと、そのまま浮かぶ（自由に置ける）
        XCTAssertTrue(model.beginDrag(at: p.position))
        model.drag(to: p.position + SIMD2<Float>(0, 2))
        model.endDrag()
        XCTAssertEqual(model.artwork.placements[0].position.y, a.radius + 2, accuracy: 1e-4)

        // 何もない所では動かない
        XCTAssertFalse(model.beginDrag(at: SIMD2<Float>(20, 20)))
    }

    func testComposeStacksOnTopOfAnotherBall() {
        let model = ComposeModel(artwork: Artwork(name: "t", createdAt: Date(), updatedAt: Date()))
        let big = piece(radius: 1.0)
        let small = piece(radius: 0.5)
        model.add(big)
        model.add(small)
        // 小さい玉を大きい玉の真上近くへ持っていく
        let bigPlacement = model.artwork.placements[0]
        let smallPos = model.artwork.placements[1].position
        XCTAssertTrue(model.beginDrag(at: smallPos))
        let top = Artwork.settleHeight(x: bigPlacement.position.x, radius: small.radius, among: [bigPlacement])
        model.drag(to: SIMD2<Float>(bigPlacement.position.x, top + 0.05))
        model.endDrag()
        let placed = model.artwork.placements.first { $0.id == small.id }
        XCTAssertEqual(placed?.position.y ?? 0, top, accuracy: 1e-4, "大きい玉の上にぴたっと積まれる")
    }

    func testComposeRemoveReturnsThePiece() {
        let model = ComposeModel(artwork: Artwork(name: "t", createdAt: Date(), updatedAt: Date()))
        let a = piece(radius: 0.4)
        model.add(a)
        model.rotateSelected(by: .pi / 4)
        XCTAssertEqual(model.artwork.placements[0].angle, .pi / 4, accuracy: 1e-6)
        XCTAssertEqual(model.removeSelected()?.id, a.id)
        XCTAssertTrue(model.artwork.placements.isEmpty)
    }

    // MARK: 背景

    func testDaypartByHour() {
        XCTAssertEqual(Daypart.current(hour: 12), .day)
        XCTAssertEqual(Daypart.current(hour: 6), .dusk)
        XCTAssertEqual(Daypart.current(hour: 17), .dusk)
        XCTAssertEqual(Daypart.current(hour: 23), .night)
        XCTAssertEqual(Daypart.current(hour: 2), .night)
        XCTAssertEqual(Set([Daypart.day, .dusk, .night].map(\.imageName)).count, 3)
    }
}
