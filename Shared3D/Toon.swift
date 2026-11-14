import SceneKit
import UIKit
import simd

/// アニメ調（セル塗り＋輪郭線）の質感。
enum Toon {
    static let outlineColor = UIColor(red: 0.36, green: 0.46, blue: 0.66, alpha: 1)
    static let outlineWidth: Float = 0.013

    /// 陰影を数段階に丸めて、ふんわりしたセル塗りにする。
    private static let fragment = """
    float lum = max(dot(_output.color.rgb, float3(0.299, 0.587, 0.114)), 0.001);
    float bands = 4.0;
    float q = (floor(lum * bands) + 0.5) / bands;
    float k = mix(lum, q, 0.7);
    _output.color.rgb *= k / lum;
    """

    static func material(_ color: UIColor, emissive: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.shaderModifiers = [.fragment: fragment]
        if emissive {
            m.emission.contents = color
            m.emission.intensity = 0.55
        }
        return m
    }

    static func texturedMaterial(_ image: UIImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .clamp
        m.shaderModifiers = [.fragment: fragment]
        return m
    }

    /// 光に影響されない単色（ハイライトなど）
    static func flat(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return m
    }

    static func outlineMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = outlineColor
        m.cullMode = .front
        return m
    }
}

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

/// 色つきの立体＋輪郭線を作る。
func solid(_ geometry: SCNGeometry, _ color: UIColor, outline: Bool = true, scale: SIMD3<Float> = SIMD3<Float>(repeating: 1), emissive: Bool = false) -> SCNNode {
    geometry.materials = [Toon.material(color, emissive: emissive)]
    let node = SCNNode(geometry: geometry)
    node.simdScale = scale
    if outline {
        addOutline(to: node, geometry: geometry)
    }
    return node
}

func addOutline(to node: SCNNode, geometry: SCNGeometry) {
    let hull: SCNGeometry
    if let special = outlineHull(for: geometry) {
        hull = special
        hull.materials = [Toon.outlineMaterial()]
        node.addChildNode(SCNNode(geometry: hull))
        return
    }
    // 想定外の形は、拡大コピーで代用する
    let (mn, mx) = geometry.boundingBox
    let dims = [abs(mx.x - mn.x), abs(mx.y - mn.y), abs(mx.z - mn.z)]
    let characteristic = max(Float(0.012), (dims.min() ?? 0.1) / 2)
    let k = 1 + Toon.outlineWidth / characteristic
    guard let copy = geometry.copy() as? SCNGeometry else { return }
    copy.materials = [Toon.outlineMaterial()]
    let fallback = SCNNode(geometry: copy)
    fallback.simdScale = SIMD3<Float>(repeating: k)
    node.addChildNode(fallback)
}

/// 形ごとに「少しだけ太らせた」輪郭用の殻を作る（細い輪が不自然に膨らまないように）。
private func outlineHull(for geometry: SCNGeometry) -> SCNGeometry? {
    let w = CGFloat(Toon.outlineWidth)
    switch geometry {
    case let g as SCNSphere:
        let h = SCNSphere(radius: g.radius + w)
        h.segmentCount = g.segmentCount
        return h
    case let g as SCNTorus:
        let h = SCNTorus(ringRadius: g.ringRadius, pipeRadius: g.pipeRadius + w)
        h.ringSegmentCount = g.ringSegmentCount
        h.pipeSegmentCount = g.pipeSegmentCount
        return h
    case let g as SCNCylinder:
        let h = SCNCylinder(radius: g.radius + w, height: g.height + 2 * w)
        h.radialSegmentCount = g.radialSegmentCount
        return h
    case let g as SCNCapsule:
        return SCNCapsule(capRadius: g.capRadius + w, height: g.height + 2 * w)
    case let g as SCNBox:
        return SCNBox(width: g.width + 2 * w, height: g.height + 2 * w, length: g.length + 2 * w, chamferRadius: g.chamferRadius + w)
    case let g as SCNCone:
        let h = SCNCone(topRadius: g.topRadius > 0 ? g.topRadius + w : 0, bottomRadius: g.bottomRadius + w * 1.6, height: g.height + 2 * w)
        h.radialSegmentCount = g.radialSegmentCount
        return h
    default:
        return nil
    }
}

/// 軸まわりの回転体。profile は (半径, 高さ) の点列で、上（軸上）から下へ向かって並べる。
func lathe(profile: [CGPoint], segments: Int = 36, outset: Float = 0) -> SCNGeometry {
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
            let r = Float(profile[i].x) + nr * outset
            let y = Float(profile[i].y) + ny * outset
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

/// 回転体＋その輪郭（外側にずらした殻）
func solidLathe(_ profile: [CGPoint], _ color: UIColor) -> SCNNode {
    let geometry = lathe(profile: profile)
    geometry.materials = [Toon.material(color)]
    let node = SCNNode(geometry: geometry)
    let hull = lathe(profile: profile, outset: Toon.outlineWidth)
    hull.materials = [Toon.outlineMaterial()]
    node.addChildNode(SCNNode(geometry: hull))
    return node
}
