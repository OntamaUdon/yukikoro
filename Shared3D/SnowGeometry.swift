import SceneKit
import UIKit
import simd

/// 3 次元の値ノイズ（雪のでこぼこの形に使う）
enum SnowNoise {
    private static func hash(_ x: Int32, _ y: Int32, _ z: Int32, _ seed: UInt32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ UInt32(bitPattern: z) &* 2_147_483_647 &+ seed &* 1_274_126_177
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65_535 * 2 - 1
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    static func value(_ p: SIMD3<Float>, seed: UInt32) -> Float {
        let fx = floor(p.x), fy = floor(p.y), fz = floor(p.z)
        let ix = Int32(fx), iy = Int32(fy), iz = Int32(fz)
        let tx = smooth(p.x - fx), ty = smooth(p.y - fy), tz = smooth(p.z - fz)
        func corner(_ dx: Int32, _ dy: Int32, _ dz: Int32) -> Float { hash(ix + dx, iy + dy, iz + dz, seed) }
        let x00 = corner(0, 0, 0) * (1 - tx) + corner(1, 0, 0) * tx
        let x10 = corner(0, 1, 0) * (1 - tx) + corner(1, 1, 0) * tx
        let x01 = corner(0, 0, 1) * (1 - tx) + corner(1, 0, 1) * tx
        let x11 = corner(0, 1, 1) * (1 - tx) + corner(1, 1, 1) * tx
        let y0 = x00 * (1 - ty) + x10 * ty
        let y1 = x01 * (1 - ty) + x11 * ty
        return y0 * (1 - tz) + y1 * tz
    }

    /// 大小3段のノイズを重ねる（-1〜1 付近）
    static func fbm(_ p: SIMD3<Float>, seed: UInt32) -> Float {
        value(p, seed: seed) * 0.62 + value(p * 2.1, seed: seed &+ 7) * 0.28 + value(p * 4.3, seed: seed &+ 13) * 0.10
    }
}

enum SnowGeometry {
    /// でこぼこした雪のかたまり（球をノイズでゆがめたもの）。法線・接線・UV つき。
    /// - Parameters:
    ///   - lump: ゆがみの大きさ（半径に対する割合）
    ///   - frequency: ゆがみの細かさ
    ///   - tile: テクスチャの繰り返し回数（横, 縦）
    static func blob(radius: Float, seed: UInt32 = 1, lump: Float = 0.04, frequency: Float = 1.7,
                     rings: Int = 48, segments: Int = 96, tile: (Float, Float) = (3, 2)) -> SCNGeometry {
        func surface(_ theta: Float, _ phi: Float) -> SIMD3<Float> {
            let d = SIMD3<Float>(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
            let n = SnowNoise.fbm(d * frequency + SIMD3<Float>(Float(seed) * 3.1, Float(seed) * 1.7, Float(seed) * 0.9), seed: seed)
            return d * radius * (1 + lump * n)
        }

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var tangentData: [Float] = []
        let eps: Float = 0.004

        for i in 0...rings {
            let theta = max(0.0001, min(.pi - 0.0001, Float(i) / Float(rings) * .pi))
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                let p = surface(theta, phi)
                let dPhi = surface(theta, phi + eps) - surface(theta, phi - eps)
                let dTheta = surface(theta + eps, phi) - surface(theta - eps, phi)
                var n = simd_cross(dTheta, dPhi)
                if simd_length(n) < 1e-9 { n = p }
                n = simd_normalize(n)
                if simd_dot(n, p) < 0 { n = -n }
                let t = simd_length(dPhi) > 1e-9 ? simd_normalize(dPhi) : SIMD3<Float>(1, 0, 0)
                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
                tangentData.append(contentsOf: [t.x, t.y, t.z, 1])
                uvs.append(CGPoint(x: CGFloat(Float(j) / Float(segments) * tile.0), y: CGFloat(Float(i) / Float(rings) * tile.1)))
            }
        }

        var indices: [UInt32] = []
        let row = segments + 1
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * row + j)
                let b = UInt32((i + 1) * row + j)
                let c = UInt32(i * row + j + 1)
                let d = UInt32((i + 1) * row + j + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }

        let tangents = tangentData.withUnsafeBufferPointer { Data(buffer: $0) }
        let tangentSource = SCNGeometrySource(
            data: tangents, semantic: .tangent, vectorCount: positions.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4
        )
        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
                tangentSource,
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }
}
