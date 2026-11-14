import XCTest
import SceneKit
import simd

final class SculptTests: XCTestCase {
    private let up = SIMD3<Float>(0, 1, 0)

    func testPristineShapeIsNearlySphere() {
        let s = SnowShape.pristine(seed: 4)
        XCTAssertEqual(s.radii.count, SculptGrid.vertexCount)
        XCTAssertEqual(s.colors.count, SculptGrid.vertexCount * 3)
        XCTAssertGreaterThan(s.radii.min() ?? 0, 0.9)
        XCTAssertLessThan(s.radii.max() ?? 2, 1.1)
        XCTAssertFalse(s.isModified)
    }

    func testCarveReducesAndAddRaisesOnlyNearTheTool() {
        let base = SnowShape.pristine(seed: 4)
        var carved = base
        for _ in 0..<10 { carved.apply(tool: .carve, direction: up, size: 0.4, strength: 1) }
        let top = SculptGrid.index(0, 0)
        let bottom = SculptGrid.index(SculptGrid.rings, 0)
        XCTAssertLessThan(carved.radii[top], base.radii[top] - 0.05)
        XCTAssertEqual(carved.radii[bottom], base.radii[bottom], accuracy: 1e-6, "遠い所は変わらない")
        XCTAssertTrue(carved.isModified)

        var raised = base
        for _ in 0..<10 { raised.apply(tool: .add, direction: up, size: 0.4, strength: 1) }
        XCTAssertGreaterThan(raised.radii[top], base.radii[top] + 0.05)
    }

    func testCarveAndAddStayInsideLimits() {
        var s = SnowShape.pristine(seed: 1)
        for _ in 0..<500 { s.apply(tool: .carve, direction: up, size: 0.5, strength: 2) }
        XCTAssertGreaterThanOrEqual(s.radii.min() ?? 0, SnowShape.minRadius)
        for _ in 0..<2_000 { s.apply(tool: .add, direction: up, size: 0.5, strength: 2) }
        XCTAssertLessThanOrEqual(s.radii.max() ?? 9, SnowShape.maxRadius)
    }

    func testSeamVerticesStayInSync() {
        var s = SnowShape.pristine(seed: 9)
        // 経度の継ぎ目（j=0 と j=最後）の近くで道具を使っても、両端が一致する
        let seam = SIMD3<Float>(0, 0, 1)
        s.apply(tool: .carve, direction: seam, size: 0.4, strength: 2)
        s.apply(tool: .smooth, direction: seam, size: 0.4, strength: 1)
        s.apply(tool: .paint, direction: seam, size: 0.4, strength: 3, color: SIMD3<Float>(1, 0, 0))
        for i in 0...SculptGrid.rings {
            let a = SculptGrid.index(i, 0)
            let b = SculptGrid.index(i, SculptGrid.segments)
            XCTAssertEqual(s.radii[a], s.radii[b], accuracy: 1e-5, "ring \(i)")
            XCTAssertEqual(s.colors[a * 3], s.colors[b * 3])
        }
    }

    func testSmoothReducesRoughness() {
        var s = SnowShape.pristine(seed: 2)
        for _ in 0..<12 { s.apply(tool: .carve, direction: up, size: 0.2, strength: 3) }
        let k = SculptGrid.index(0, 0)
        let ring1 = SculptGrid.index(2, 10)
        let before = abs(s.radii[k] - s.radii[ring1])
        for _ in 0..<20 { s.apply(tool: .smooth, direction: up, size: 0.5, strength: 1.5) }
        XCTAssertLessThan(abs(s.radii[k] - s.radii[ring1]), before)
    }

    func testFlattenCutsDownToPlane() {
        var s = SnowShape.pristine(seed: 3)
        for _ in 0..<40 { s.apply(tool: .flatten, direction: up, size: 0.9, strength: 2, plane: (up, 0.7)) }
        // 真上は平面（深さ0.7）まで削れる
        XCTAssertEqual(s.radii[SculptGrid.index(0, 0)], 0.7, accuracy: 0.02)
        // 真下は変わらない
        XCTAssertEqual(s.radii[SculptGrid.index(SculptGrid.rings, 0)], SnowShape.pristine(seed: 3).radii[SculptGrid.index(SculptGrid.rings, 0)], accuracy: 1e-6)
    }

    func testPaintChangesColorOnlyNearTheTool() {
        var s = SnowShape.pristine(seed: 5)
        for _ in 0..<20 { s.apply(tool: .paint, direction: up, size: 0.4, strength: 2, color: SIMD3<Float>(1, 0, 0)) }
        let top = SculptGrid.index(0, 0)
        XCTAssertEqual(s.colors[top * 3], 255)
        XCTAssertLessThan(s.colors[top * 3 + 1], 30, "赤に近づく")
        let bottom = SculptGrid.index(SculptGrid.rings, 0)
        XCTAssertEqual(s.colors[bottom * 3 + 1], 255, "遠い所は白のまま")
        XCTAssertTrue(s.isModified)
    }

    func testShapeCodableRoundTrip() throws {
        var s = SnowShape.pristine(seed: 6)
        s.apply(tool: .carve, direction: up, size: 0.4, strength: 1)
        s.apply(tool: .paint, direction: up, size: 0.4, strength: 2, color: SIMD3<Float>(0, 0, 1))
        let decoded = try JSONDecoder().decode(SnowShape.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testMeshBuffersAreConsistent() {
        let shape = SnowShape.pristine(seed: 7)
        let geo = SculptMesh.geometry(for: shape, material: SnowMaterial.make())
        XCTAssertEqual(geo.sources(for: .vertex).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.sources(for: .normal).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.sources(for: .color).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.sources(for: .texcoord).first?.vectorCount, SculptGrid.vertexCount)
        XCTAssertEqual(geo.elements.first?.primitiveCount, SculptGrid.rings * SculptGrid.segments * 2)
    }

    // MARK: 作品

    private func placement(_ radius: Float, x: Float, y: Float, z: Float = 0) -> Placement {
        // 半径 radius になる歩数を探す
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
        let world = ArtworkWorld(hour: 12, shadows: false)
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

    // MARK: 空

    func testSkyChangesContinuouslyWithTime() {
        var previous = SkyState.at(hour: 0)
        var h = 0.1
        while h < 24 {
            let s = SkyState.at(hour: h)
            XCTAssertLessThan(simd_length(s.top - previous.top), 0.1, "h=\(h) 空の色が急に変わらない")
            XCTAssertLessThan(simd_length(s.horizon - previous.horizon), 0.1, "h=\(h)")
            previous = s
            h += 0.1
        }
    }

    func testSkyIsBrightAtNoonAndDarkAtMidnight() {
        let noon = SkyState.at(hour: 12)
        let night = SkyState.at(hour: 0)
        XCTAssertGreaterThan(noon.top.z, night.top.z + 0.5)
        XCTAssertGreaterThan(noon.ambient, 0.95)
        XCTAssertLessThan(night.ambient, 0.45)
        XCTAssertGreaterThan(noon.lightIntensity, 1000)
        XCTAssertTrue(noon.isSun)
        XCTAssertFalse(night.isSun)
        XCTAssertGreaterThan(night.stars, 0.9)
        XCTAssertLessThan(noon.stars, 0.01)
        XCTAssertGreaterThan(noon.lightDirection.y, 0.8, "正午の太陽はほぼ真上")
    }

    func testSunsetHorizonIsWarmAndTimeWraps() {
        let dusk = SkyState.at(hour: 17.5)
        XCTAssertGreaterThan(dusk.horizon.x, dusk.horizon.z, "夕方の地平線は赤っぽい")
        let a = SkyState.at(hour: 3)
        let b = SkyState.at(hour: 27)
        XCTAssertEqual(simd_length(a.top - b.top), 0, accuracy: 1e-5)
    }
}
