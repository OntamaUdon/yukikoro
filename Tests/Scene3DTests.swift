import XCTest
import SceneKit

final class Scene3DTests: XCTestCase {
    /// 全種類・全サイズの組み合わせで、雪だるまが破綻なく組み立てられること
    func testBuildsEveryKind() {
        var rng = SplitMix64(seed: 11)
        for species in Species.allCases {
            for tier in SizeTier.allCases {
                for _ in 0..<5 {
                    let decorations = SnowmanFactory.pickDecorations(species: species, tier: tier, using: &rng)
                    let node = SnowmanBuilder.make(species: species, decorations: decorations)
                    XCTAssertGreaterThan(node.childNodes.count, 6, "\(species) \(tier)")
                    let (low, high) = Scene3DTests.extent(of: node)
                    XCTAssertGreaterThan(high.y - low.y, 1.5, "背が低すぎる \(species)")
                    XCTAssertLessThan(high.y - low.y, 2.8, "背が高すぎる \(species)")
                    XCTAssertLessThan(high.x - low.x, 2.6, "横に広すぎる \(species)")
                }
            }
        }
    }

    /// 子孫すべての図形をまとめた、ワールド座標での範囲
    static func extent(of root: SCNNode) -> (SIMD3<Float>, SIMD3<Float>) {
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        root.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (mn, mx) = node.boundingBox
            let m = node.simdWorldTransform
            for x in [mn.x, mx.x] {
                for y in [mn.y, mx.y] {
                    for z in [mn.z, mx.z] {
                        let p = m * SIMD4<Float>(x, y, z, 1)
                        let q = SIMD3<Float>(p.x, p.y, p.z)
                        low = simd_min(low, q)
                        high = simd_max(high, q)
                    }
                }
            }
        }
        return (low, high)
    }

    func testLatheGeometryHasConsistentBuffers() {
        let profile = [CGPoint(x: 0, y: 0.5), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.3, y: 0)]
        let g = lathe(profile: profile, segments: 12)
        let vertexCount = g.sources(for: .vertex).first?.vectorCount ?? 0
        let normalCount = g.sources(for: .normal).first?.vectorCount ?? 0
        XCTAssertEqual(vertexCount, 3 * 13)
        XCTAssertEqual(vertexCount, normalCount)
        XCTAssertEqual(g.elements.first?.primitiveCount, 2 * 12 * 2)
    }

    func testOrientAlignsAxis() {
        let node = SCNNode()
        orient(node, axis: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(1, 0, 0))
        let rotated = node.simdOrientation.act(SIMD3<Float>(0, 1, 0))
        XCTAssertEqual(rotated.x, 1, accuracy: 0.001)
        XCTAssertEqual(rotated.y, 0, accuracy: 0.001)

        let flip = SCNNode()
        orient(flip, axis: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(0, -1, 0))
        XCTAssertEqual(flip.simdOrientation.act(SIMD3<Float>(0, 1, 0)).y, -1, accuracy: 0.001)
    }

    func testSurfacePointIsOnSphere() {
        let c = SIMD3<Float>(0, 1, 0)
        let (p, n) = surfacePoint(center: c, radius: 0.5, az: 0.4, el: 0.3)
        XCTAssertEqual(simd_length(p - c), 0.5, accuracy: 0.0001)
        XCTAssertEqual(simd_length(n), 1, accuracy: 0.0001)
    }
}
