import XCTest
import SceneKit
import simd

final class SculptTests: XCTestCase {
    private let identity = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    private func index(of direction: SIMD3<Float>) -> Int {
        // 向きがいちばん近い頂点
        var best = 0
        var bestDot: Float = -2
        for (k, d) in SculptGrid.directions.enumerated() {
            let v = simd_dot(d, simd_normalize(direction))
            if v > bestDot { bestDot = v; best = k }
        }
        return best
    }

    func testPristineShapeIsNearlyWhiteSphere() {
        let s = SnowShape.pristine(seed: 4)
        XCTAssertEqual(s.radii.count, SculptGrid.vertexCount)
        XCTAssertEqual(s.tint, [255, 255, 255])
        XCTAssertGreaterThan(s.radii.min() ?? 0, 0.9)
        XCTAssertLessThan(s.radii.max() ?? 2, 1.1)
        XCTAssertFalse(s.isModified)
    }

    // MARK: 刃

    func testBladeCutsTheSideItPassedThrough() {
        // 刃は左（x<0）から入る。刃の面（x=-0.5）より左の雪が取り除かれる。
        var s = SnowShape.pristine(seed: 1)
        let left = index(of: SIMD3<Float>(-1, 0, 0))
        let right = index(of: SIMD3<Float>(1, 0, 0))
        let rightBefore = s.radii[right]
        XCTAssertTrue(s.cutBlade(rotation: identity, planeX: -0.5, bandLow: -3, bandHigh: 3))
        XCTAssertEqual(s.radii[left], 0.5, accuracy: 0.02, "刃の面ぴったりまで削れる")
        XCTAssertEqual(s.radii[right], rightBefore, accuracy: 1e-6, "反対側は変わらない")
        XCTAssertTrue(s.isModified)
    }

    func testCutLeavesAFlatFaceAtThePlane() {
        var s = SnowShape.pristine(seed: 2)
        s.cutBlade(rotation: identity, planeX: -0.6, bandLow: -3, bandHigh: 3)
        // 切り口の上の点は、すべて x = -0.6 にある
        for (k, d) in SculptGrid.directions.enumerated() where d.x < -0.4 {
            let x = s.radii[k] * d.x
            XCTAssertGreaterThanOrEqual(x, -0.6 - 0.01, "刃の面より外へは出ない")
        }
        let k = index(of: SIMD3<Float>(-1, 0.2, 0.1))
        XCTAssertEqual(s.radii[k] * SculptGrid.directions[k].x, -0.6, accuracy: 0.01)
    }

    func testBladeOnlyCutsWithinItsHeight() {
        var s = SnowShape.pristine(seed: 3)
        let before = s
        // 上のほう（y=0.6〜0.9）だけの小さな刃
        s.cutBlade(rotation: identity, planeX: -0.4, bandLow: 0.6, bandHigh: 0.9)
        let high = index(of: SIMD3<Float>(-0.6, 0.8, 0))
        let low = index(of: SIMD3<Float>(-1, -0.6, 0))
        XCTAssertLessThan(s.radii[high], before.radii[high] - 0.1)
        XCTAssertEqual(s.radii[low], before.radii[low], accuracy: 1e-6, "刃の高さの外は削れない")
    }

    func testBladeKeepsTheCenterSide() {
        var s = SnowShape.pristine(seed: 5)
        // 中心の手前までしか入らない（0.2より内には入れない）
        s.cutBlade(rotation: identity, planeX: -0.01, bandLow: -3, bandHigh: 3)
        let left = index(of: SIMD3<Float>(-1, 0, 0))
        XCTAssertGreaterThanOrEqual(s.radii[left], SnowShape.minCutDepth - 0.01)
        XCTAssertGreaterThanOrEqual(s.radii.min() ?? 0, SnowShape.minRadius)
    }

    func testBladeFollowsTheBallRotation() {
        // 雪玉を回すと、刃（画面の座標）に当たる面が変わる
        var s = SnowShape.pristine(seed: 6)
        let turn = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        s.cutBlade(rotation: turn, planeX: -0.5, bandLow: -3, bandHigh: 3)
        // y 軸まわりに90°回すと、画面の左 (-x) には、元の形の +z か -z の面が来る
        let hit = turn.inverse.act(SIMD3<Float>(-1, 0, 0))
        let k = index(of: hit)
        XCTAssertEqual(s.radii[k], 0.5, accuracy: 0.03)
        let unaffected = index(of: SIMD3<Float>(-1, 0, 0))
        XCTAssertGreaterThan(s.radii[unaffected], 0.9)
    }

    func testSeamVerticesStayInSync() {
        var s = SnowShape.pristine(seed: 9)
        s.cutBlade(rotation: simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3<Float>(1, 2, 0.5))), planeX: -0.5, bandLow: -3, bandHigh: 3)
        for i in 0...SculptGrid.rings {
            let a = SculptGrid.index(i, 0)
            let b = SculptGrid.index(i, SculptGrid.segments)
            XCTAssertEqual(s.radii[a], s.radii[b], accuracy: 1e-5, "ring \(i)")
        }
    }

    // MARK: 色

    func testTintIsOneColorForTheWholeBall() {
        var s = SnowShape.pristine(seed: 5)
        s.setTint(SIMD3<Float>(1, 0, 0))
        XCTAssertEqual(s.tint, [255, 0, 0])
        XCTAssertEqual(s.tintRGB.x, 1, accuracy: 1e-6)
        XCTAssertTrue(s.isModified)
        let geo = SculptMesh.geometry(for: s, material: SnowMaterial.make())
        XCTAssertEqual(geo.sources(for: .color).first?.vectorCount, SculptGrid.vertexCount)
    }

    // MARK: 成長（厚さ一定）

    func testGrowAddsUniformThickness() {
        var s = SnowShape.pristine(seed: 7)
        s.cutBlade(rotation: identity, planeX: -0.5, bandLow: -3, bandHigh: 3)
        let before = s
        let old: Float = 0.5, new: Float = 0.7
        s.grow(fromRadius: old, toRadius: new)
        for k in stride(from: 0, to: s.radii.count, by: 97) {
            // 実際の長さ（基準の半径 × 倍率）は、どこも 0.2 だけ増える
            let beforeLength = old * before.radii[k]
            let afterLength = new * s.radii[k]
            XCTAssertEqual(afterLength - beforeLength, new - old, accuracy: 1e-4)
        }
    }

    func testGrowKeepsTheCutFaceAsAnOffsetFace() {
        var s = SnowShape.pristine(seed: 8)
        s.cutBlade(rotation: identity, planeX: -0.5, bandLow: -3, bandHigh: 3)
        s.grow(fromRadius: 0.5, toRadius: 0.6)
        // 切り口は、そのまま少しだけ外側に厚みが付く（ゆがまない）
        let k = index(of: SIMD3<Float>(-1, 0, 0))
        XCTAssertGreaterThan(s.radii[k], 0.45)
        XCTAssertLessThan(s.radii[k], 1.2)
    }

    // MARK: 保存・メッシュ

    func testShapeCodableRoundTrip() throws {
        var s = SnowShape.pristine(seed: 6)
        s.cutBlade(rotation: identity, planeX: -0.5, bandLow: -3, bandHigh: 3)
        s.setTint(SIMD3<Float>(0, 0, 1))
        let decoded = try JSONDecoder().decode(SnowShape.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testOldShapeWithoutTintStillLoads() throws {
        let s = SnowShape.pristine(seed: 3)
        let json = "{\"seed\": 3, \"radii\": \"\(s.radii.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString())\"}"
        let decoded = try JSONDecoder().decode(SnowShape.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.tint, [255, 255, 255])
        XCTAssertEqual(decoded.radii, s.radii)
    }

    func testMeshBuffersAreConsistent() {
        let shape = SnowShape.pristine(seed: 7)
        let geo = SculptMesh.geometry(for: shape, material: SnowMaterial.make())
        XCTAssertEqual(geo.sources(for: .vertex).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.sources(for: .normal).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.sources(for: .texcoord).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.elements.first?.primitiveCount, SculptGrid.rings * SculptGrid.segments * 2)
    }

    func testBladeSizesAreOrdered() {
        XCTAssertLessThan(BladeSize.small.height, BladeSize.medium.height)
        XCTAssertLessThan(BladeSize.medium.height, BladeSize.large.height)
    }

    // MARK: 直径

    func testDiameterFormatAndMeasure() {
        XCTAssertEqual(formatLength(meters: 0.58), "約58cm")
        XCTAssertEqual(formatLength(meters: 1.24), "約1.2m")
        let d = BallScale.diameter(steps: 0, extent: 1)
        XCTAssertEqual(d, 2 * BallScale.r0, accuracy: 1e-9)
        XCTAssertGreaterThan(BallScale.diameter(steps: 10_000, extent: 1), d)
        XCTAssertEqual(BallScale.diameter(steps: 0, extent: 1.5), d * 1.5, accuracy: 1e-9)
    }

    // MARK: 作品

    private func placement(_ radius: Float, x: Float, y: Float, z: Float = 0) -> Placement {
        var steps = 0
        while Float(BallScale.radius(steps: steps)) < radius, steps < Snow.maxSteps { steps += 50 }
        return Placement(piece: SnowPiece(steps: steps, madeAt: Date(), shape: .pristine(seed: 1)), position: SIMD3<Float>(x, y, z))
    }

    func testSettleOnGroundAndOnTopOfAnother() {
        let big = placement(1.0, x: 0, y: 1.0)
        let r = big.piece.radius
        let ground = Artwork.settleHeight(x: 5, z: 0, radius: 0.5, among: [big])
        XCTAssertEqual(ground, 0.5, accuracy: 1e-5, "離れていれば地面に置く")

        let onTop = Artwork.settleHeight(x: 0, z: 0, radius: 0.5, among: [big])
        let expected = big.position.y + (r + 0.5) * Artwork.contactFactor
        XCTAssertEqual(onTop, expected, accuracy: 1e-4, "真上なら上に積む")

        let beside = Artwork.settleHeight(x: r * 0.8, z: 0, radius: 0.5, among: [big])
        XCTAssertGreaterThan(beside, 0.5)
        XCTAssertLessThan(beside, onTop)
    }

    func testSettleIgnoresItself() {
        let a = placement(0.6, x: 0, y: 0.6)
        XCTAssertEqual(Artwork.settleHeight(x: 0, z: 0, radius: a.piece.radius, among: [a], excluding: a.id), a.piece.radius, accuracy: 1e-5)
    }

    func testPlacementOrientationRoundTrip() {
        var p = placement(0.5, x: 0, y: 0.5)
        let q = simd_quatf(angle: 1.1, axis: simd_normalize(SIMD3<Float>(1, 2, 3)))
        p.orientation = q
        XCTAssertEqual(simd_length(p.orientation.vector - q.vector), 0, accuracy: 1e-5)
    }

    func testArtworkWorldSyncsNodes() {
        let world = ArtworkWorld(daypart: .day)
        let a = placement(0.5, x: 0, y: 0.5)
        let b = placement(0.9, x: 2, y: 0.9)
        world.sync([a, b], selected: a.id)
        XCTAssertNotNil(world.scene.rootNode.childNode(withName: a.id.uuidString, recursively: false))
        XCTAssertNotNil(world.scene.rootNode.childNode(withName: b.id.uuidString, recursively: false))
        world.sync([b])
        XCTAssertNil(world.scene.rootNode.childNode(withName: a.id.uuidString, recursively: false))
        let node = world.scene.rootNode.childNode(withName: b.id.uuidString, recursively: false)
        XCTAssertEqual(node?.simdPosition.x ?? 0, 2, accuracy: 1e-5)
        XCTAssertEqual(node?.simdScale.x ?? 0, b.piece.radius, accuracy: 1e-5)
    }

    // MARK: 背景

    func testDaypartByHour() {
        XCTAssertEqual(Daypart.current(hour: 12), .day)
        XCTAssertEqual(Daypart.current(hour: 6), .dusk)
        XCTAssertEqual(Daypart.current(hour: 17), .dusk)
        XCTAssertEqual(Daypart.current(hour: 23), .night)
        XCTAssertEqual(Daypart.current(hour: 2), .night)
    }
}
