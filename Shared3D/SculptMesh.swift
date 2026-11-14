import SceneKit
import UIKit
import simd

/// `SnowShape`（形と色）から、描画用のメッシュを作る。
enum SculptMesh {
    /// テクスチャの繰り返し回数（横, 縦）
    static let tile: (Float, Float) = (3, 2)

    /// 三角形の並び（形が変わっても同じ）
    private static let element: SCNGeometryElement = {
        var indices: [UInt32] = []
        let row = SculptGrid.rowCount
        for i in 0..<SculptGrid.rings {
            for j in 0..<SculptGrid.segments {
                let a = UInt32(i * row + j)
                let b = UInt32((i + 1) * row + j)
                let c = UInt32(i * row + j + 1)
                let d = UInt32((i + 1) * row + j + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        return SCNGeometryElement(indices: indices, primitiveType: .triangles)
    }()

    private static let uvSource: SCNGeometrySource = {
        var uvs: [CGPoint] = []
        uvs.reserveCapacity(SculptGrid.vertexCount)
        for i in 0...SculptGrid.rings {
            for j in 0...SculptGrid.segments {
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(SculptGrid.segments) * tile.0),
                                   y: CGFloat(Float(i) / Float(SculptGrid.rings) * tile.1)))
            }
        }
        return SCNGeometrySource(textureCoordinates: uvs)
    }()

    /// 頂点の位置（半径1の球を基準にした座標）
    static func positions(of shape: SnowShape) -> [SIMD3<Float>] {
        let dirs = SculptGrid.directions
        var p = [SIMD3<Float>](repeating: .zero, count: dirs.count)
        for k in 0..<dirs.count { p[k] = dirs[k] * shape.radii[k] }
        return p
    }

    static func geometry(for shape: SnowShape, material: SCNMaterial) -> SCNGeometry {
        let rings = SculptGrid.rings
        let seg = SculptGrid.segments
        let row = SculptGrid.rowCount
        let dirs = SculptGrid.directions
        let p = positions(of: shape)

        func at(_ i: Int, _ j: Int) -> SIMD3<Float> { p[i * row + ((j % seg) + seg) % seg] }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var tangents: [Float] = []
        var colors: [Float] = []
        vertices.reserveCapacity(p.count)
        normals.reserveCapacity(p.count)
        tangents.reserveCapacity(p.count * 4)
        colors.reserveCapacity(p.count * 4)

        for i in 0...rings {
            for j in 0...seg {
                let k = i * row + j
                let pos = p[k]
                var n = dirs[k]
                var t = SIMD3<Float>(1, 0, 0)
                if i > 0 && i < rings {
                    let dPhi = at(i, j + 1) - at(i, j - 1)
                    let dTheta = at(i + 1, j) - at(i - 1, j)
                    let c = simd_cross(dTheta, dPhi)
                    if simd_length(c) > 1e-9 {
                        n = simd_normalize(c)
                        if simd_dot(n, pos) < 0 { n = -n }
                    }
                    if simd_length(dPhi) > 1e-9 { t = simd_normalize(dPhi) }
                }
                vertices.append(SCNVector3(pos.x, pos.y, pos.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
                tangents.append(contentsOf: [t.x, t.y, t.z, 1])
                colors.append(contentsOf: [
                    Float(shape.colors[k * 3]) / 255,
                    Float(shape.colors[k * 3 + 1]) / 255,
                    Float(shape.colors[k * 3 + 2]) / 255,
                    1,
                ])
            }
        }

        let tangentSource = SCNGeometrySource(
            data: tangents.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .tangent, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4
        )
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4
        )
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), uvSource, tangentSource, colorSource],
            elements: [element]
        )
        geometry.materials = [material]
        return geometry
    }
}

/// 指でぐるっと回せるカメラ（注目点のまわりを回る）
struct OrbitCamera {
    var azimuth: Float = 0.6
    var elevation: Float = 0.3
    var distance: Float = 5
    var target = SIMD3<Float>(0, 0, 0)
    var minDistance: Float = 2
    var maxDistance: Float = 30
    var minElevation: Float = -1.4
    var maxElevation: Float = 1.4

    var position: SIMD3<Float> {
        target + distance * SIMD3<Float>(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
    }

    mutating func rotate(dAzimuth: Float, dElevation: Float) {
        azimuth += dAzimuth
        elevation = min(maxElevation, max(minElevation, elevation + dElevation))
    }

    mutating func zoom(scale: Float) {
        guard scale > 0 else { return }
        distance = min(maxDistance, max(minDistance, distance / scale))
    }

    func apply(to node: SCNNode) {
        node.simdPosition = position
        node.simdLook(at: target)
    }
}

/// 雪玉の素材（写真の質感）を1つ作る。選択中などで見た目を変えられるよう、ノードごとに別の素材にする。
enum SnowMaterial {
    static func make() -> SCNMaterial {
        let m = PBR.snow(tile: (1, 1))
        m.emission.intensity = 0.1
        return m
    }

    static func setSelected(_ material: SCNMaterial, _ selected: Bool) {
        if selected {
            material.emission.contents = UIColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1)
            material.emission.intensity = 0.55
        } else {
            material.emission.contents = UIColor(red: 0.30, green: 0.40, blue: 0.58, alpha: 1)
            material.emission.intensity = 0.1
        }
    }
}
