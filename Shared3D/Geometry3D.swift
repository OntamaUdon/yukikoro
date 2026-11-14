import SceneKit
import UIKit
import simd

// MARK: - 幾何の補助

func vec3(_ v: SIMD3<Float>) -> SCNVector3 { SCNVector3(v.x, v.y, v.z) }

/// 半径 `r` の球面上の点と外向きの法線。az は正面(+z)から右(+x)への角度、el は上向きの角度。
func surfacePoint(center c: SIMD3<Float>, radius r: Float, az: Float, el: Float) -> (p: SIMD3<Float>, n: SIMD3<Float>) {
    let n = SIMD3<Float>(cos(el) * sin(az), sin(el), cos(el) * cos(az))
    return (c + n * r, n)
}

/// ノードのローカル軸 `axis` を、方向 `target` に向ける。
func orient(_ node: SCNNode, axis: SIMD3<Float>, to target: SIMD3<Float>) {
    let a = simd_normalize(axis)
    let t = simd_normalize(target)
    let c = simd_cross(a, t)
    let len = simd_length(c)
    if len < 1e-5 {
        if simd_dot(a, t) < 0 {
            // 真逆: 軸に直交する任意の軸で180度回す
            let ortho = abs(a.x) < 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 0, 1)
            node.simdOrientation = simd_quatf(angle: .pi, axis: simd_normalize(simd_cross(a, ortho)))
        }
        return
    }
    let angle = acos(max(-1, min(1, simd_dot(a, t))))
    node.simdOrientation = simd_quatf(angle: angle, axis: c / len)
}

/// 軸まわりの回転体。profile は (半径, 高さ) の点列で、上（軸上）から下へ向かって並べる。
func lathe(profile: [CGPoint], segments: Int = 36) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var indices: [UInt32] = []
    let count = profile.count
    for i in 0..<count {
        let prev = profile[max(i - 1, 0)]
        let next = profile[min(i + 1, count - 1)]
        var tx = Float(next.x - prev.x)
        var ty = Float(next.y - prev.y)
        let len = max(0.0001, (tx * tx + ty * ty).squareRoot())
        tx /= len
        ty /= len
        let nr = -ty
        let ny = tx
        for j in 0...segments {
            let theta = Float(j) / Float(segments) * 2 * .pi
            let s = sin(theta)
            let c = cos(theta)
            let r = Float(profile[i].x)
            let y = Float(profile[i].y)
            vertices.append(SCNVector3(r * s, y, r * c))
            normals.append(SCNVector3(nr * s, ny, nr * c))
        }
    }
    let row = segments + 1
    for i in 0..<(count - 1) {
        for j in 0..<segments {
            let a = UInt32(i * row + j)
            let b = UInt32((i + 1) * row + j)
            let c = UInt32(i * row + j + 1)
            let d = UInt32((i + 1) * row + j + 1)
            indices.append(contentsOf: [a, b, c, b, d, c])
        }
    }
    let geometry = SCNGeometry(
        sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
        elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
    )
    return geometry
}
