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

    func testBladeCutsTheSideItPassedThrough() {
        var s = SnowShape.pristine(seed: 1)
        let left = index(of: SIMD2<Float>(-1, 0))
        let right = index(of: SIMD2<Float>(1, 0))
        let rightBefore = s.radii[right]
        XCTAssertTrue(s.cutBlade(angle: 0, planeX: -0.5, bandLow: -3, bandHigh: 3))
        XCTAssertEqual(s.radii[left], 0.5, accuracy: 0.02, "刃の面ぴったりまで削れる")
        XCTAssertEqual(s.radii[right], rightBefore, accuracy: 1e-6, "反対側は変わらない")
        XCTAssertTrue(s.isModified)
    }

    func testCutLeavesAFlatEdgeAtThePlane() {
        var s = SnowShape.pristine(seed: 2)
        s.cutBlade(angle: 0, planeX: -0.6, bandLow: -3, bandHigh: 3)
        for (k, d) in SnowShape.directions.enumerated() where d.x < -0.4 {
            XCTAssertGreaterThanOrEqual(s.radii[k] * d.x, -0.6 - 0.01, "刃の面より外へは出ない")
        }
        let k = index(of: SIMD2<Float>(-1, 0.2))
        XCTAssertEqual(s.radii[k] * SnowShape.directions[k].x, -0.6, accuracy: 0.01)
    }

    func testBladeOnlyCutsWithinItsHeight() {
        var s = SnowShape.pristine(seed: 3)
        let before = s
        // 上のほう（y=0.6〜0.9）だけの小さな刃
        s.cutBlade(angle: 0, planeX: -0.4, bandLow: 0.6, bandHigh: 0.9)
        let high = index(of: SIMD2<Float>(-0.6, 0.8))
        let low = index(of: SIMD2<Float>(-1, -0.6))
        XCTAssertLessThan(s.radii[high], before.radii[high] - 0.1)
        XCTAssertEqual(s.radii[low], before.radii[low], accuracy: 1e-6, "刃の高さの外は削れない")
    }

    func testBladeKeepsTheCenterSide() {
        var s = SnowShape.pristine(seed: 5)
        s.cutBlade(angle: 0, planeX: -0.01, bandLow: -3, bandHigh: 3)
        let left = index(of: SIMD2<Float>(-1, 0))
        XCTAssertGreaterThanOrEqual(s.radii[left], SnowShape.minCutDepth - 0.01)
        XCTAssertGreaterThanOrEqual(s.radii.min() ?? 0, SnowShape.minRadius)
    }

    func testBladeFollowsTheBallRotation() {
        // 雪玉を回すと、刃に当たる面が変わる
        var s = SnowShape.pristine(seed: 6)
        let turn: Float = .pi / 2   // 反時計回りに90°
        s.cutBlade(angle: turn, planeX: -0.5, bandLow: -3, bandHigh: 3)
        // 画面の左(-x)に来ているのは、元の形の「上向き(0,1)」の面
        let hit = index(of: SIMD2<Float>(0, 1))
        XCTAssertEqual(s.radii[hit], 0.5, accuracy: 0.03)
        let unaffected = index(of: SIMD2<Float>(-1, 0))
        XCTAssertGreaterThan(s.radii[unaffected], 0.9)
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
        s.cutBlade(angle: 0, planeX: -0.5, bandLow: -3, bandHigh: 3)
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
        s.cutBlade(angle: 0.3, planeX: -0.5, bandLow: -3, bandHigh: 3)
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

    func testBladeDragCutsInRealTimeAndCanBeUndone() {
        let model = SculptModel(shape: .pristine(seed: 2), baseRadius: 0.5)
        let before = model.shape
        model.beginBlade()
        model.dragBlade(translation: SIMD2<Float>(0.4, 0))     // -1.6 から 0.4 進める → -1.2（まだ当たらない）
        XCTAssertEqual(model.shape, before, "雪玉に届くまでは削れない")
        model.dragBlade(translation: SIMD2<Float>(1.2, 0))     // → -0.4
        XCTAssertNotEqual(model.shape, before, "当たると自動で削れる")
        let left = index(of: SIMD2<Float>(-1, 0))
        XCTAssertEqual(model.shape.radii[left], 0.4, accuracy: 0.03)
        model.endBlade()
        XCTAssertEqual(model.undoCount, 1, "1回の操作は1回のやり直しにまとまる")
        model.undo()
        XCTAssertEqual(model.shape, before)
    }

    func testBladeCannotGoPastTheCenter() {
        let model = SculptModel(shape: .pristine(seed: 2), baseRadius: 0.5)
        model.beginBlade()
        model.dragBlade(translation: SIMD2<Float>(5, 0))
        XCTAssertLessThanOrEqual(model.bladeX, SculptModel.bladeXRange.upperBound + 1e-6)
        XCTAssertGreaterThan(model.shape.radii.min() ?? 0, 0.15, "雪玉は消えない")
    }

    func testSpinKeepsCuttingWhileTheBladeIsHeld() {
        let model = SculptModel(shape: .pristine(seed: 2), baseRadius: 0.5)
        model.beginBlade()
        model.dragBlade(translation: SIMD2<Float>(1.4, 0))     // -0.2 の位置に刃を置く
        let t0 = Date()
        model.spin = 1
        model.tick(now: t0)
        var cuts = 0
        for i in 1...30 {
            let before = model.shape
            model.tick(now: t0.addingTimeInterval(Double(i) / 60))
            if model.shape != before { cuts += 1 }
        }
        XCTAssertGreaterThan(model.angle, 0.3, "左回りに回る")
        XCTAssertGreaterThan(cuts, 0, "回りながらも削れる")
        model.endBlade()
        model.spin = 0
    }

    func testDiameterTracksTheCutShape() {
        let model = SculptModel(shape: .pristine(seed: 2), baseRadius: 0.5)
        let d0 = model.diameter
        XCTAssertEqual(d0, 2 * 0.5 * Double(model.shape.maxExtent), accuracy: 1e-6)
        model.beginBlade()
        model.dragBlade(translation: SIMD2<Float>(1.4, 0))
        model.endBlade()
        XCTAssertLessThanOrEqual(model.diameter, d0)
    }

    func testBladeSizesAreOrdered() {
        XCTAssertLessThan(BladeSize.small.height, BladeSize.medium.height)
        XCTAssertLessThan(BladeSize.medium.height, BladeSize.large.height)
    }

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
