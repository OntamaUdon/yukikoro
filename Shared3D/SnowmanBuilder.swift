import SceneKit
import SwiftUI
import UIKit
import simd

/// 雪だるまを 3D（SceneKit）で組み立てる。画像素材は使わず、すべて図形から作る。
/// 単位はおおよそメートル。体の半径 0.5、頭の半径 0.34。正面は +z。
enum SnowmanBuilder {
    static let bodyCenter = SIMD3<Float>(0, 0.5, 0)
    static let bodyRadius: Float = 0.5
    static let headCenter = SIMD3<Float>(0, 1.27, 0)
    static let headRadius: Float = 0.34

    // MARK: 色

    static let snow = UIColor(red: 0.975, green: 0.985, blue: 1.0, alpha: 1)
    static let ink = UIColor(red: 0.16, green: 0.17, blue: 0.25, alpha: 1)
    static let cheek = UIColor(red: 1.0, green: 0.68, blue: 0.74, alpha: 1)
    static let carrot = UIColor(red: 1.0, green: 0.60, blue: 0.22, alpha: 1)
    static let twig = UIColor(red: 0.47, green: 0.33, blue: 0.25, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.82, blue: 0.32, alpha: 1)

    private static func bodyColor(_ s: Species) -> UIColor {
        switch s {
        case .penguin: return UIColor(red: 0.36, green: 0.43, blue: 0.62, alpha: 1)
        case .hiyoko: return UIColor(red: 1.0, green: 0.93, blue: 0.62, alpha: 1)
        case .daruma: return UIColor(red: 0.96, green: 0.40, blue: 0.40, alpha: 1)
        default: return snow
        }
    }

    // MARK: 組み立て

    static func make(species: Species, decorations: [Decoration]) -> SCNNode {
        let root = SCNNode()
        root.name = "snowman"

        addBehind(species, to: root)

        // ゆるい雰囲気のため、体と頭を少しだけ傾ける
        let body = solid(SCNSphere(radius: CGFloat(bodyRadius)), bodyColor(species), scale: SIMD3<Float>(1.0, 0.96, 1.0))
        body.name = "body"
        body.simdPosition = bodyCenter
        root.addChildNode(body)

        let head = solid(SCNSphere(radius: CGFloat(headRadius)), bodyColor(species))
        head.name = "head"
        head.simdPosition = headCenter
        head.eulerAngles.z = 0.04
        root.addChildNode(head)

        addPatches(species, to: root)
        addArms(species, decorations: decorations, to: root)
        addFace(species, to: root)
        addSignature(species, to: root)
        for decoration in decorations {
            addDecoration(decoration, species: species, to: root)
        }
        return root
    }

    // MARK: 小さな部品

    private static func sphere(_ r: Float, _ color: UIColor, at p: SIMD3<Float>, scale: SIMD3<Float> = SIMD3<Float>(repeating: 1), outline: Bool = false) -> SCNNode {
        let n = solid(SCNSphere(radius: CGFloat(r)), color, outline: outline, scale: scale)
        n.simdPosition = p
        return n
    }

    /// 球面に貼りつく平たい部品（目・ほっぺなど）。法線方向に向ける。
    private static func decal(_ r: Float, _ color: UIColor, center: SIMD3<Float>, radius: Float, az: Float, el: Float, scale: SIMD3<Float>, lift: Float = 0, outline: Bool = false) -> SCNNode {
        let (p, n) = surfacePoint(center: center, radius: radius + lift, az: az, el: el)
        let node = solid(SCNSphere(radius: CGFloat(r)), color, outline: outline, scale: scale)
        node.simdPosition = p
        orient(node, axis: SIMD3<Float>(0, 0, 1), to: n)
        return node
    }

    private static func eyes(on root: SCNNode, az: Float = 0.36, el: Float = 0.13, size: Float = 0.046) {
        for sign: Float in [-1, 1] {
            let eye = decal(size, ink, center: headCenter, radius: headRadius, az: sign * az, el: el,
                            scale: SIMD3<Float>(0.82, 1.18, 0.45), lift: -0.004)
            let shine = SCNNode(geometry: SCNSphere(radius: CGFloat(size * 0.32)))
            shine.geometry?.materials = [Toon.flat(.white)]
            shine.simdPosition = SIMD3<Float>(-size * 0.22, size * 0.42, size * 0.95)
            eye.addChildNode(shine)
            let small = SCNNode(geometry: SCNSphere(radius: CGFloat(size * 0.16)))
            small.geometry?.materials = [Toon.flat(.white)]
            small.simdPosition = SIMD3<Float>(size * 0.2, -size * 0.35, size * 0.95)
            eye.addChildNode(small)
            eye.name = "eye"
            root.addChildNode(eye)
        }
    }

    private static func cheeks(on root: SCNNode, az: Float = 0.62, el: Float = -0.10) {
        for sign: Float in [-1, 1] {
            let c = decal(0.07, cheek, center: headCenter, radius: headRadius, az: sign * az, el: el,
                          scale: SIMD3<Float>(1.0, 0.62, 0.22), lift: -0.012)
            root.addChildNode(c)
        }
    }

    private static func smile(on root: SCNNode, az0: Float = 0, el0: Float = -0.30, count: Int = 5, spread: Float = 0.085, size: Float = 0.012) {
        for i in 0..<count {
            let k = Float(i) - Float(count - 1) / 2
            let az = az0 + k * spread
            let el = el0 + 0.022 * abs(k)
            let dot = decal(size, ink, center: headCenter, radius: headRadius, az: az, el: el,
                            scale: SIMD3<Float>(1, 1, 0.5), lift: -0.003)
            root.addChildNode(dot)
        }
    }

    private static func smallSmile(on root: SCNNode, el: Float = -0.22) {
        for sign: Float in [-1, 1] {
            for step in 0..<3 {
                let t = Float(step)
                let az = sign * (0.012 + t * 0.045)
                let e = el + 0.012 * t
                let dot = decal(0.0085, ink, center: headCenter, radius: headRadius, az: az, el: e,
                                scale: SIMD3<Float>(1, 1, 0.5), lift: -0.003)
                root.addChildNode(dot)
            }
        }
    }

    private static func cone(radius: Float, height: Float, color: UIColor, base: SIMD3<Float>, direction: SIMD3<Float>, outline: Bool = true, segments: Int = 24) -> SCNNode {
        let geo = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius), height: CGFloat(height))
        geo.radialSegmentCount = segments
        let node = solid(geo, color, outline: outline)
        let dir = simd_normalize(direction)
        node.simdPosition = base + dir * (height / 2)
        orient(node, axis: SIMD3<Float>(0, 1, 0), to: dir)
        return node
    }

    private static func stick(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, color: UIColor) -> SCNNode {
        let d = b - a
        let length = simd_length(d)
        let geo = SCNCylinder(radius: CGFloat(radius), height: CGFloat(length))
        geo.radialSegmentCount = 10
        let node = solid(geo, color, outline: false)
        node.simdPosition = (a + b) / 2
        orient(node, axis: SIMD3<Float>(0, 1, 0), to: d)
        return node
    }

    // MARK: 背面

    private static func addBehind(_ s: Species, to root: SCNNode) {
        switch s {
        case .tenshi:
            for sign: Float in [-1, 1] {
                let wing = sphere(0.42, snow, at: SIMD3<Float>(sign * 0.52, 0.80, -0.30), scale: SIMD3<Float>(0.34, 1.0, 0.18), outline: true)
                wing.eulerAngles = SCNVector3(0, sign * 0.5, -sign * 0.55)
                root.addChildNode(wing)
                let feather = sphere(0.30, UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1), at: SIMD3<Float>(sign * 0.72, 0.42, -0.30), scale: SIMD3<Float>(0.30, 1.0, 0.16), outline: true)
                feather.eulerAngles = SCNVector3(0, sign * 0.5, -sign * 0.75)
                root.addChildNode(feather)
            }
        case .ousama:
            let plane = SCNPlane(width: 1.05, height: 1.0)
            plane.cornerRadius = 0.22
            plane.materials = [Toon.material(UIColor(red: 0.86, green: 0.26, blue: 0.32, alpha: 1))]
            plane.firstMaterial?.isDoubleSided = true
            let cape = SCNNode(geometry: plane)
            cape.simdPosition = SIMD3<Float>(0, 0.62, -0.42)
            cape.eulerAngles.x = -0.12
            root.addChildNode(cape)
        case .usagi:
            for sign: Float in [-1, 1] {
                let ear = solid(SCNCapsule(capRadius: 0.085, height: 0.58), snow, scale: SIMD3<Float>(1, 1, 0.55))
                ear.simdPosition = headCenter + SIMD3<Float>(sign * 0.13, 0.46, -0.02)
                ear.eulerAngles.z = -sign * 0.2
                let inner = solid(SCNCapsule(capRadius: 0.045, height: 0.40), cheek, outline: false)
                inner.simdPosition = SIMD3<Float>(0, 0, 0.045)
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case .neko:
            for sign: Float in [-1, 1] {
                let geo = SCNCone(topRadius: 0, bottomRadius: 0.15, height: 0.36)
                geo.radialSegmentCount = 3
                let ear = solid(geo, snow, scale: SIMD3<Float>(1, 1, 0.55))
                ear.simdPosition = headCenter + SIMD3<Float>(sign * 0.20, 0.31, -0.02)
                ear.eulerAngles = SCNVector3(0, 0, -sign * 0.38)
                let innerGeo = SCNCone(topRadius: 0, bottomRadius: 0.09, height: 0.24)
                innerGeo.radialSegmentCount = 3
                let inner = solid(innerGeo, cheek, outline: false)
                inner.simdPosition = SIMD3<Float>(0, -0.015, 0.04)
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case .kuma:
            for sign: Float in [-1, 1] {
                let ear = sphere(0.115, snow, at: headCenter + SIMD3<Float>(sign * 0.25, 0.25, -0.02), scale: SIMD3<Float>(1, 1, 0.65), outline: true)
                let inner = sphere(0.062, cheek, at: SIMD3<Float>(0, 0, 0.055), scale: SIMD3<Float>(1, 1, 0.5))
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        default:
            break
        }
    }

    // MARK: 顔や体の模様（球面にのせる平たい膨らみ）

    private static func addPatches(_ s: Species, to root: SCNNode) {
        switch s {
        case .penguin:
            let belly = solid(SCNSphere(radius: 0.527), snow, outline: false, scale: SIMD3<Float>(0.88, 0.90, 1.0))
            belly.simdPosition = bodyCenter + SIMD3<Float>(0, -0.03, 0)
            root.addChildNode(belly)
            let face = solid(SCNSphere(radius: 0.362), snow, outline: false, scale: SIMD3<Float>(0.84, 0.74, 1.0))
            face.simdPosition = headCenter + SIMD3<Float>(0, -0.04, 0)
            root.addChildNode(face)
        case .daruma:
            let face = solid(SCNSphere(radius: 0.352), snow, outline: false, scale: SIMD3<Float>(0.74, 0.66, 1.0))
            face.simdPosition = headCenter + SIMD3<Float>(0, -0.04, 0)
            root.addChildNode(face)
            for dy: Float in [0.55, 0.40] {
                let ring = SCNTorus(ringRadius: CGFloat(sqrt(0.25 - (dy - 0.5) * (dy - 0.5)) + 0.004), pipeRadius: 0.016)
                let band = solid(ring, gold, outline: false)
                band.simdPosition = SIMD3<Float>(0, dy, 0)
                root.addChildNode(band)
            }
        case .kuma:
            let muzzle = solid(SCNSphere(radius: 0.352), UIColor(red: 1.0, green: 0.94, blue: 0.87, alpha: 1), outline: false, scale: SIMD3<Float>(0.40, 0.30, 1.0))
            muzzle.simdPosition = headCenter + SIMD3<Float>(0, -0.10, 0)
            root.addChildNode(muzzle)
        default:
            break
        }
    }

    // MARK: 腕

    private static func addArms(_ s: Species, decorations: [Decoration], to root: SCNNode) {
        if s.hasTwigArms {
            let mitten = decorations.first { $0.kind == .mittens }
            for sign: Float in [-1, 1] {
                let start = SIMD3<Float>(sign * 0.44, 0.66, 0.04)
                let end = SIMD3<Float>(sign * 0.98, 0.98, 0.10)
                root.addChildNode(stick(from: start, to: end, radius: 0.018, color: twig))
                let mid = start + (end - start) * 0.62
                root.addChildNode(stick(from: mid, to: mid + SIMD3<Float>(sign * 0.10, 0.17, 0.0), radius: 0.012, color: twig))
                root.addChildNode(stick(from: mid, to: mid + SIMD3<Float>(sign * 0.17, 0.05, 0.02), radius: 0.011, color: twig))
                if let mitten {
                    let tone = UIColor(Palette.tone(mitten.hue).base)
                    root.addChildNode(sphere(0.07, tone, at: end, outline: true))
                }
            }
        } else if s == .penguin {
            for sign: Float in [-1, 1] {
                let flipper = solid(SCNSphere(radius: 0.24), UIColor(red: 0.27, green: 0.33, blue: 0.50, alpha: 1), scale: SIMD3<Float>(0.22, 1.0, 0.5))
                flipper.simdPosition = SIMD3<Float>(sign * 0.54, 0.55, 0.02)
                flipper.eulerAngles.z = -sign * 0.42
                root.addChildNode(flipper)
            }
            for sign: Float in [-1, 1] {
                let foot = solid(SCNSphere(radius: 0.10), UIColor(red: 1.0, green: 0.70, blue: 0.28, alpha: 1), scale: SIMD3<Float>(1.2, 0.35, 1.5))
                foot.simdPosition = SIMD3<Float>(sign * 0.20, 0.035, 0.46)
                root.addChildNode(foot)
            }
        } else if s == .hiyoko {
            for sign: Float in [-1, 1] {
                let wing = solid(SCNSphere(radius: 0.2), UIColor(red: 0.99, green: 0.84, blue: 0.44, alpha: 1), scale: SIMD3<Float>(0.3, 1.0, 0.7))
                wing.simdPosition = SIMD3<Float>(sign * 0.50, 0.58, 0.04)
                wing.eulerAngles.z = -sign * 0.5
                root.addChildNode(wing)
            }
            for sign: Float in [-1, 1] {
                let foot = solid(SCNSphere(radius: 0.08), UIColor(red: 1.0, green: 0.62, blue: 0.25, alpha: 1), scale: SIMD3<Float>(1.2, 0.35, 1.5))
                foot.simdPosition = SIMD3<Float>(sign * 0.18, 0.03, 0.46)
                root.addChildNode(foot)
            }
        }
    }

    // MARK: 顔

    private static func addFace(_ s: Species, to root: SCNNode) {
        switch s {
        case .plain:
            eyes(on: root)
            cheeks(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.04)
            let dir = simd_normalize(n + SIMD3<Float>(0, -0.14, 0))
            root.addChildNode(cone(radius: 0.052, height: 0.26, color: carrot, base: p - n * 0.02, direction: dir))
            smile(on: root, el0: -0.36)
        case .usagi:
            eyes(on: root)
            cheeks(on: root)
            let (p, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.06)
            root.addChildNode(sphere(0.026, UIColor(red: 0.96, green: 0.52, blue: 0.62, alpha: 1), at: p, scale: SIMD3<Float>(1, 0.8, 0.8)))
            smallSmile(on: root, el: -0.2)
        case .neko:
            eyes(on: root)
            cheeks(on: root)
            let (p, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.06)
            root.addChildNode(sphere(0.024, UIColor(red: 0.96, green: 0.52, blue: 0.62, alpha: 1), at: p, scale: SIMD3<Float>(1, 0.8, 0.8)))
            smallSmile(on: root, el: -0.2)
            for sign: Float in [-1, 1] {
                for k in 0..<3 {
                    let a = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.45, el: -0.12 + Float(k) * 0.05).p
                    let spread = Float(k - 1) * 0.07
                    root.addChildNode(stick(from: a, to: a + SIMD3<Float>(sign * 0.22, spread, 0.04), radius: 0.004, color: UIColor(red: 0.45, green: 0.52, blue: 0.68, alpha: 1)))
                }
            }
        case .kuma:
            eyes(on: root)
            cheeks(on: root, az: 0.7)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.14)
            let nose = solid(SCNSphere(radius: 0.032), ink, outline: false, scale: SIMD3<Float>(1.2, 0.85, 0.8))
            nose.simdPosition = p + n * 0.012
            root.addChildNode(nose)
            smallSmile(on: root, el: -0.30)
        case .inu:
            eyes(on: root)
            cheeks(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.08)
            let nose = solid(SCNSphere(radius: 0.04), ink, outline: false, scale: SIMD3<Float>(1.2, 0.85, 0.8))
            nose.simdPosition = p + n * 0.01
            root.addChildNode(nose)
            smallSmile(on: root, el: -0.24)
            for sign: Float in [-1, 1] {
                let ear = solid(SCNSphere(radius: 0.15), UIColor(red: 0.91, green: 0.77, blue: 0.58, alpha: 1), scale: SIMD3<Float>(0.5, 1.2, 0.42))
                ear.simdPosition = headCenter + SIMD3<Float>(sign * 0.33, 0.02, 0.02)
                ear.eulerAngles.z = -sign * 0.22
                root.addChildNode(ear)
            }
        case .penguin:
            eyes(on: root, az: 0.30, el: 0.14)
            cheeks(on: root, az: 0.55, el: -0.12)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.06)
            root.addChildNode(cone(radius: 0.06, height: 0.16, color: UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1), base: p - n * 0.01, direction: simd_normalize(n + SIMD3<Float>(0, -0.2, 0))))
        case .hiyoko:
            eyes(on: root)
            cheeks(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.04)
            root.addChildNode(cone(radius: 0.05, height: 0.13, color: UIColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1), base: p - n * 0.01, direction: simd_normalize(n + SIMD3<Float>(0, -0.2, 0))))
            let tuftColor = UIColor(red: 0.99, green: 0.84, blue: 0.44, alpha: 1)
            for (dx, tilt) in [(Float(-0.07), Float(-0.5)), (0, 0), (0.07, 0.5)] as [(Float, Float)] {
                let t = cone(radius: 0.035, height: 0.14, color: tuftColor, base: headCenter + SIMD3<Float>(dx, 0.31, 0.02), direction: SIMD3<Float>(sin(tilt), 1, 0), outline: false, segments: 12)
                root.addChildNode(t)
            }
        case .daruma:
            for sign: Float in [-1, 1] {
                let eye = decal(0.05, .white, center: headCenter, radius: headRadius, az: sign * 0.28, el: 0.05, scale: SIMD3<Float>(1, 1, 0.4), lift: 0.012, outline: true)
                root.addChildNode(eye)
                let pupil = decal(0.025, ink, center: headCenter, radius: headRadius, az: sign * 0.28, el: 0.05, scale: SIMD3<Float>(1, 1, 0.4), lift: 0.03)
                root.addChildNode(pupil)
                let (bp, bn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.28, el: 0.33)
                let brow = solid(SCNCapsule(capRadius: 0.018, height: 0.17), ink, outline: false)
                brow.simdPosition = bp + bn * 0.004
                brow.eulerAngles = SCNVector3(0, 0, Float.pi / 2 + sign * 0.28)
                root.addChildNode(brow)
                let (mp, mn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.2, el: -0.32)
                let mus = solid(SCNCapsule(capRadius: 0.014, height: 0.14), ink, outline: false)
                mus.simdPosition = mp + mn * 0.004
                mus.eulerAngles = SCNVector3(0, 0, Float.pi / 2 - sign * 0.35)
                root.addChildNode(mus)
            }
            let (np, nn) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.10)
            root.addChildNode(sphere(0.026, UIColor(red: 0.96, green: 0.52, blue: 0.56, alpha: 1), at: np + nn * 0.01))
        case .tenshi:
            eyes(on: root)
            cheeks(on: root)
            smile(on: root, el0: -0.26, count: 3, spread: 0.07, size: 0.011)
        case .ousama:
            eyes(on: root)
            cheeks(on: root)
            let (np, nn) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.04)
            root.addChildNode(sphere(0.035, carrot, at: np + nn * 0.012))
            for sign: Float in [-1, 1] {
                let (mp, mn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.17, el: -0.26)
                let mus = solid(SCNSphere(radius: 0.07), snow, outline: true, scale: SIMD3<Float>(1.0, 0.65, 0.6))
                mus.simdPosition = mp + mn * 0.012
                mus.eulerAngles.z = sign * 0.35
                root.addChildNode(mus)
            }
        }
    }

    // MARK: 種類ごとの印

    private static func addSignature(_ s: Species, to root: SCNNode) {
        switch s {
        case .tenshi:
            let halo = solid(SCNTorus(ringRadius: 0.21, pipeRadius: 0.028), gold, outline: false, emissive: true)
            halo.simdPosition = headCenter + SIMD3<Float>(0, 0.50, -0.02)
            halo.eulerAngles.x = 0.12
            root.addChildNode(halo)
        case .ousama:
            let crown = crownNode()
            crown.simdPosition = headCenter + SIMD3<Float>(0, 0.30, 0)
            root.addChildNode(crown)
        default:
            break
        }
    }

    private static func crownNode() -> SCNNode {
        let group = SCNNode()
        let band = solid(SCNCylinder(radius: 0.2, height: 0.09), gold)
        group.addChildNode(band)
        let count = 5
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let tip = cone(radius: 0.045, height: 0.15, color: gold, base: SIMD3<Float>(sin(a) * 0.17, 0.04, cos(a) * 0.17), direction: SIMD3<Float>(sin(a) * 0.12, 1, cos(a) * 0.12), outline: true, segments: 12)
            group.addChildNode(tip)
            let jewel = sphere(0.022, [UIColor(red: 0.92, green: 0.25, blue: 0.30, alpha: 1), UIColor(red: 0.30, green: 0.55, blue: 0.95, alpha: 1)][i % 2],
                               at: SIMD3<Float>(sin(a) * 0.205, 0.0, cos(a) * 0.205))
            group.addChildNode(jewel)
        }
        return group
    }

    // MARK: 飾り

    private static func addDecoration(_ d: Decoration, species: Species, to root: SCNNode) {
        let tone = Palette.tone(d.hue)
        let base = UIColor(tone.base)
        let dark = UIColor(tone.dark)
        let top = headCenter.y + headRadius  // 頭のてっぺん
        switch d.kind {
        case .bucketHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, top - 0.10, 0)
            group.eulerAngles.z = 0.07
            let crown = solidLathe([CGPoint(x: 0, y: 0.26), CGPoint(x: 0.12, y: 0.255), CGPoint(x: 0.2, y: 0.22), CGPoint(x: 0.255, y: 0.02), CGPoint(x: 0.255, y: 0)], base)
            group.addChildNode(crown)
            let brim = solidLathe([CGPoint(x: 0.25, y: 0.012), CGPoint(x: 0.40, y: 0.0), CGPoint(x: 0.40, y: -0.02), CGPoint(x: 0.25, y: -0.01)], dark)
            group.addChildNode(brim)
            let band = solid(SCNTorus(ringRadius: 0.245, pipeRadius: 0.018), dark, outline: false)
            band.simdPosition = SIMD3<Float>(0, 0.05, 0)
            group.addChildNode(band)
            root.addChildNode(group)
        case .topHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, top - 0.07, 0)
            group.eulerAngles.z = -0.06
            let brim = solid(SCNCylinder(radius: 0.36, height: 0.04), ink)
            group.addChildNode(brim)
            let crown = solid(SCNCylinder(radius: 0.21, height: 0.36), ink)
            crown.simdPosition = SIMD3<Float>(0, 0.2, 0)
            group.addChildNode(crown)
            let band = solid(SCNCylinder(radius: 0.215, height: 0.07), base, outline: false)
            band.simdPosition = SIMD3<Float>(0, 0.08, 0)
            group.addChildNode(band)
            root.addChildNode(group)
        case .santaHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0.02, top - 0.14, 0)
            group.eulerAngles.z = -0.28
            let hat = solidLathe([CGPoint(x: 0, y: 0.52), CGPoint(x: 0.07, y: 0.46), CGPoint(x: 0.15, y: 0.30), CGPoint(x: 0.27, y: 0.04), CGPoint(x: 0.27, y: 0)], base)
            group.addChildNode(hat)
            let brim = solid(SCNTorus(ringRadius: 0.27, pipeRadius: 0.055), snow)
            brim.simdPosition = SIMD3<Float>(0, 0.01, 0)
            group.addChildNode(brim)
            group.addChildNode(sphere(0.07, snow, at: SIMD3<Float>(0.03, 0.54, 0), outline: true))
            root.addChildNode(group)
        case .knitCap:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, headCenter.y + 0.02, 0)
            let cap = solidLathe([
                CGPoint(x: 0, y: 0.40), CGPoint(x: 0.14, y: 0.385), CGPoint(x: 0.25, y: 0.32), CGPoint(x: 0.32, y: 0.20),
                CGPoint(x: 0.352, y: 0.09), CGPoint(x: 0.356, y: 0.0),
            ], base)
            group.addChildNode(cap)
            let cuff = solid(SCNTorus(ringRadius: 0.35, pipeRadius: 0.045), dark)
            cuff.simdPosition = SIMD3<Float>(0, 0.05, 0)
            group.addChildNode(cuff)
            group.addChildNode(sphere(0.07, snow, at: SIMD3<Float>(0, 0.43, 0), outline: true))
            group.eulerAngles.x = -0.08
            root.addChildNode(group)
        case .earmuffs:
            for k in 0...14 {
                let t = Float(k) / 14
                let a = Float.pi * t
                let p = headCenter + SIMD3<Float>(-cos(a) * 0.36, sin(a) * 0.40, 0)
                root.addChildNode(sphere(0.02, UIColor(red: 0.42, green: 0.46, blue: 0.58, alpha: 1), at: p))
            }
            for sign: Float in [-1, 1] {
                let pad = sphere(0.1, base, at: headCenter + SIMD3<Float>(sign * 0.35, 0.0, 0), scale: SIMD3<Float>(0.6, 1.0, 1.0), outline: true)
                root.addChildNode(pad)
            }
        case .flowerCrown:
            let count = 7
            for i in 0..<count {
                let az = (Float(i) / Float(count) - 0.5) * 2 * .pi * 0.95
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: az, el: 0.95)
                if p.y < headCenter.y + 0.12 { continue }
                let petal = UIColor(Palette.tone(d.hue + i).base)
                let flower = SCNNode()
                flower.simdPosition = p
                for k in 0..<5 {
                    let a = Float(k) / 5 * 2 * .pi
                    let petalNode = sphere(0.035, petal, at: SIMD3<Float>(cos(a) * 0.045, sin(a) * 0.045, 0), scale: SIMD3<Float>(1, 1, 0.6))
                    flower.addChildNode(petalNode)
                }
                flower.addChildNode(sphere(0.028, gold, at: SIMD3<Float>(0, 0, 0.01), scale: SIMD3<Float>(1, 1, 0.8)))
                orient(flower, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(flower)
            }
            // 後ろ側の花
            for i in 0..<4 {
                let az = Float.pi + (Float(i) - 1.5) * 0.7
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: az, el: 0.9)
                let flower = SCNNode()
                flower.simdPosition = p
                for k in 0..<5 {
                    let a = Float(k) / 5 * 2 * .pi
                    flower.addChildNode(sphere(0.035, UIColor(Palette.tone(d.hue + i + 2).base), at: SIMD3<Float>(cos(a) * 0.045, sin(a) * 0.045, 0), scale: SIMD3<Float>(1, 1, 0.6)))
                }
                flower.addChildNode(sphere(0.028, gold, at: SIMD3<Float>(0, 0, 0.01)))
                orient(flower, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(flower)
            }
        case .ribbon:
            let group = SCNNode()
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0.55, el: 0.78)
            group.simdPosition = p + n * 0.02
            orient(group, axis: SIMD3<Float>(0, 0, 1), to: n)
            for sign: Float in [-1, 1] {
                let wing = solid(SCNSphere(radius: 0.085), base, scale: SIMD3<Float>(1.3, 0.8, 0.5))
                wing.simdPosition = SIMD3<Float>(sign * 0.09, 0, 0)
                wing.eulerAngles.z = sign * 0.35
                group.addChildNode(wing)
            }
            group.addChildNode(sphere(0.045, dark, at: SIMD3<Float>(0, 0, 0.02), outline: true))
            root.addChildNode(group)
        case .sunglasses:
            for sign: Float in [-1, 1] {
                let lens = decal(0.07, ink, center: headCenter, radius: headRadius, az: sign * 0.33, el: 0.13,
                                 scale: SIMD3<Float>(1.15, 0.85, 0.35), lift: 0.016, outline: true)
                root.addChildNode(lens)
                let shine = decal(0.016, .white, center: headCenter, radius: headRadius, az: sign * 0.33 - 0.1, el: 0.2,
                                  scale: SIMD3<Float>(1.5, 0.6, 0.3), lift: 0.04)
                shine.geometry?.materials = [Toon.flat(UIColor.white.withAlphaComponent(0.6))]
                root.addChildNode(shine)
            }
            let (bp, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: 0.13)
            let bridge = solid(SCNCylinder(radius: 0.008, height: 0.1), ink, outline: false)
            bridge.simdPosition = bp + SIMD3<Float>(0, 0, 0.02)
            bridge.eulerAngles.z = Float.pi / 2
            root.addChildNode(bridge)
        case .roundGlasses:
            for sign: Float in [-1, 1] {
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.36, el: 0.13)
                let ring = SCNTorus(ringRadius: 0.075, pipeRadius: 0.011)
                let node = solid(ring, dark, outline: false)
                node.simdPosition = p + n * 0.012
                orient(node, axis: SIMD3<Float>(0, 1, 0), to: n)
                root.addChildNode(node)
            }
            let (bp, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: 0.14)
            let bridge = solid(SCNCylinder(radius: 0.007, height: 0.08), dark, outline: false)
            bridge.simdPosition = bp + SIMD3<Float>(0, 0, 0.012)
            bridge.eulerAngles.z = Float.pi / 2
            root.addChildNode(bridge)
        case .scarf:
            let ring = solid(SCNTorus(ringRadius: 0.30, pipeRadius: 0.085), base, scale: SIMD3<Float>(1, 1, 1))
            ring.simdPosition = SIMD3<Float>(0, 0.97, 0.01)
            ring.eulerAngles.x = 0.06
            root.addChildNode(ring)
            let tail = solid(SCNBox(width: 0.16, height: 0.44, length: 0.06, chamferRadius: 0.025), base)
            tail.simdPosition = SIMD3<Float>(0.15, 0.74, 0.37)
            tail.eulerAngles = SCNVector3(-0.12, 0.0, -0.06)
            for dy: Float in [-0.02, -0.11] {
                let stripe = solid(SCNBox(width: 0.165, height: 0.035, length: 0.065, chamferRadius: 0.01), dark, outline: false)
                stripe.simdPosition = SIMD3<Float>(0, dy, 0)
                tail.addChildNode(stripe)
            }
            root.addChildNode(tail)
        case .bowtie:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, 0.96, 0.36)
            for sign: Float in [-1, 1] {
                let geo = SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.13)
                let wing = solid(geo, base)
                wing.simdPosition = SIMD3<Float>(sign * 0.075, 0, 0)
                wing.eulerAngles.z = -sign * Float.pi / 2
                group.addChildNode(wing)
            }
            group.addChildNode(sphere(0.04, dark, at: SIMD3<Float>(0, 0, 0.02), outline: true))
            root.addChildNode(group)
        case .buttons:
            for dy: Float in [0.22, 0.02, -0.18] {
                let y = bodyCenter.y + dy
                let el = asin(dy / bodyRadius)
                let (p, n) = surfacePoint(center: bodyCenter, radius: bodyRadius, az: 0, el: el)
                let button = solid(SCNSphere(radius: 0.04), dark, outline: false, scale: SIMD3<Float>(1, 1, 0.5))
                button.simdPosition = SIMD3<Float>(p.x, y, p.z) + n * 0.004
                orient(button, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(button)
            }
        case .stripe:
            for dy: Float in [0.08, -0.12] {
                let rr = sqrt(bodyRadius * bodyRadius - dy * dy) - 0.002
                let band = solid(SCNTorus(ringRadius: CGFloat(rr), pipeRadius: 0.03), base, outline: false)
                band.simdPosition = SIMD3<Float>(0, bodyCenter.y + dy, 0)
                root.addChildNode(band)
            }
        case .mittens:
            break // 腕を作るときに一緒に付ける
        }
    }
}
