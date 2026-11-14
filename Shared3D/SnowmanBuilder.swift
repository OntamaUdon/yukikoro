import SceneKit
import SwiftUI
import UIKit
import simd

/// 雪だるまを 3D（SceneKit）で組み立てる。写真素材（雪・樹皮・布）を使った物理ベースの質感。
/// 単位はおおよそメートル。体の半径 0.5、頭の半径 0.34。正面は +z。
enum SnowmanBuilder {
    static let bodyCenter = SIMD3<Float>(0, 0.5, 0)
    static let bodyRadius: Float = 0.5
    static let headCenter = SIMD3<Float>(0, 1.27, 0)
    static let headRadius: Float = 0.34

    // MARK: 色

    static let felt = UIColor(red: 0.95, green: 0.55, blue: 0.62, alpha: 1)
    static let beakOrange = UIColor(red: 0.96, green: 0.52, blue: 0.10, alpha: 1)
    static let gold = UIColor(red: 1.0, green: 0.78, blue: 0.34, alpha: 1)

    // MARK: 部品の作り方

    private static func part(_ geometry: SCNGeometry, _ material: SCNMaterial, at p: SIMD3<Float> = SIMD3<Float>(repeating: 0), scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)) -> SCNNode {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.simdPosition = p
        node.simdScale = scale
        return node
    }

    private static func snowBlob(_ r: Float, seed: UInt32, lump: Float = 0.04, at p: SIMD3<Float> = SIMD3<Float>(repeating: 0), scale: SIMD3<Float> = SIMD3<Float>(repeating: 1), material: SCNMaterial? = nil) -> SCNNode {
        part(SnowGeometry.blob(radius: r, seed: seed, lump: lump, rings: 36, segments: 72), material ?? PBR.snow(tile: (1, 1)), at: p, scale: scale)
    }

    /// 石炭のかけら（目・口・ボタン）
    private static func coalPiece(_ r: Float, seed: UInt32, at p: SIMD3<Float>, normal n: SIMD3<Float>? = nil, scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)) -> SCNNode {
        let node = part(SnowGeometry.blob(radius: r, seed: seed, lump: 0.3, frequency: 2.6, rings: 14, segments: 24, tile: (1, 1)), PBR.coal(), at: p, scale: scale)
        if let n { orient(node, axis: SIMD3<Float>(0, 0, 1), to: n) }
        return node
    }

    private static func stick(from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float) -> SCNNode {
        let d = b - a
        let cone = SCNCone(topRadius: CGFloat(radius * 0.45), bottomRadius: CGFloat(radius), height: CGFloat(simd_length(d)))
        cone.radialSegmentCount = 10
        let node = part(cone, PBR.bark(), at: (a + b) / 2)
        orient(node, axis: SIMD3<Float>(0, 1, 0), to: -d)
        return node
    }

    private static func cone(radius: Float, height: Float, material: SCNMaterial, base: SIMD3<Float>, direction: SIMD3<Float>, segments: Int = 24) -> SCNNode {
        let geo = SCNCone(topRadius: 0, bottomRadius: CGFloat(radius), height: CGFloat(height))
        geo.radialSegmentCount = segments
        let dir = simd_normalize(direction)
        let node = part(geo, material, at: base + dir * (height / 2))
        orient(node, axis: SIMD3<Float>(0, 1, 0), to: dir)
        return node
    }

    private static func doubleSided(_ m: SCNMaterial) -> SCNMaterial {
        m.isDoubleSided = true
        return m
    }

    // MARK: 組み立て

    static func make(species: Species, decorations: [Decoration]) -> SCNNode {
        let root = SCNNode()
        root.name = "snowman"
        let k = UInt32(Species.allCases.firstIndex(of: species) ?? 0) + 1

        addBehind(species, seed: k, to: root)

        let bodyMat: SCNMaterial
        switch species {
        case .penguin: bodyMat = PBR.charcoal()
        case .hiyoko: bodyMat = PBR.fleece(UIColor(red: 1.0, green: 0.86, blue: 0.36, alpha: 1))
        case .daruma: bodyMat = PBR.fleece(UIColor(red: 0.86, green: 0.16, blue: 0.16, alpha: 1))
        default: bodyMat = PBR.snow(tile: (1, 1))
        }
        let isCloth = species == .hiyoko || species == .daruma

        let body = part(
            SnowGeometry.blob(radius: bodyRadius, seed: k * 3 + 1, lump: isCloth ? 0.02 : 0.05, rings: 56, segments: 112),
            bodyMat, at: bodyCenter, scale: SIMD3<Float>(1, 0.94, 1)
        )
        body.name = "body"
        root.addChildNode(body)

        // 体と頭のつなぎ目をなじませる雪
        let neck = part(SnowGeometry.blob(radius: 0.30, seed: k * 3 + 5, lump: isCloth ? 0.02 : 0.05, rings: 24, segments: 48), bodyMat, at: SIMD3<Float>(0, 0.96, 0))
        root.addChildNode(neck)

        let head = part(
            SnowGeometry.blob(radius: headRadius, seed: k * 3 + 2, lump: isCloth ? 0.02 : 0.04, rings: 48, segments: 96),
            bodyMat, at: headCenter
        )
        head.name = "head"
        head.eulerAngles.z = 0.04
        root.addChildNode(head)

        addPatches(species, seed: k, to: root)
        addArms(species, decorations: decorations, to: root)
        addFace(species, seed: k, to: root)
        addSignature(species, to: root)
        for decoration in decorations {
            addDecoration(decoration, species: species, to: root)
        }
        return root
    }

    // MARK: 背面（耳・羽・マント）

    private static func addBehind(_ s: Species, seed k: UInt32, to root: SCNNode) {
        switch s {
        case .usagi:
            for sign: Float in [-1, 1] {
                let ear = snowBlob(0.12, seed: k + 20, lump: 0.05, at: headCenter + SIMD3<Float>(sign * 0.13, 0.50, -0.02), scale: SIMD3<Float>(0.62, 2.5, 0.42))
                ear.eulerAngles.z = -sign * 0.2
                let inner = part(SnowGeometry.blob(radius: 0.1, seed: 4, lump: 0.02, rings: 16, segments: 28), PBR.fleece(felt), at: SIMD3<Float>(0, 0, 0.032), scale: SIMD3<Float>(0.5, 2.0, 0.5))
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case .neko:
            for sign: Float in [-1, 1] {
                let ear = snowBlob(0.12, seed: k + 21, lump: 0.04, at: headCenter + SIMD3<Float>(sign * 0.21, 0.33, -0.02), scale: SIMD3<Float>(0.95, 1.7, 0.45))
                ear.eulerAngles.z = -sign * 0.42
                let inner = part(SnowGeometry.blob(radius: 0.09, seed: 5, lump: 0.02, rings: 16, segments: 28), PBR.fleece(felt), at: SIMD3<Float>(0, -0.02, 0.035), scale: SIMD3<Float>(0.7, 1.4, 0.5))
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case .kuma:
            for sign: Float in [-1, 1] {
                let ear = snowBlob(0.115, seed: k + 22, lump: 0.05, at: headCenter + SIMD3<Float>(sign * 0.25, 0.24, -0.02), scale: SIMD3<Float>(1, 1, 0.7))
                let inner = part(SnowGeometry.blob(radius: 0.07, seed: 6, lump: 0.02, rings: 16, segments: 28), PBR.fleece(felt), at: SIMD3<Float>(0, 0, 0.055), scale: SIMD3<Float>(1, 1, 0.5))
                ear.addChildNode(inner)
                root.addChildNode(ear)
            }
        case .tenshi:
            for sign: Float in [-1, 1] {
                let wing = snowBlob(0.40, seed: k + 23, lump: 0.05, at: SIMD3<Float>(sign * 0.52, 0.82, -0.30), scale: SIMD3<Float>(0.30, 1.0, 0.17))
                wing.eulerAngles = SCNVector3(0, sign * 0.5, -sign * 0.55)
                root.addChildNode(wing)
                let low = snowBlob(0.30, seed: k + 24, lump: 0.05, at: SIMD3<Float>(sign * 0.72, 0.44, -0.30), scale: SIMD3<Float>(0.28, 1.0, 0.16))
                low.eulerAngles = SCNVector3(0, sign * 0.5, -sign * 0.78)
                root.addChildNode(low)
            }
        case .ousama:
            let plane = SCNPlane(width: 1.08, height: 1.0)
            plane.cornerRadius = 0.22
            let cape = part(plane, doubleSided(PBR.fleece(UIColor(red: 0.62, green: 0.08, blue: 0.14, alpha: 1))), at: SIMD3<Float>(0, 0.62, -0.42))
            cape.eulerAngles.x = -0.12
            root.addChildNode(cape)
        default:
            break
        }
    }

    // MARK: 体の模様（球面にかぶせる膨らみ）

    private static func addPatches(_ s: Species, seed k: UInt32, to root: SCNNode) {
        switch s {
        case .penguin:
            let belly = part(SnowGeometry.blob(radius: 0.527, seed: k, lump: 0.03, rings: 48, segments: 96), PBR.snow(), at: bodyCenter + SIMD3<Float>(0, -0.03, 0), scale: SIMD3<Float>(0.88, 0.90, 1.0))
            root.addChildNode(belly)
            let face = part(SnowGeometry.blob(radius: 0.362, seed: k + 1, lump: 0.03, rings: 40, segments: 80), PBR.snow(), at: headCenter + SIMD3<Float>(0, -0.04, 0), scale: SIMD3<Float>(0.84, 0.74, 1.0))
            root.addChildNode(face)
        case .daruma:
            let face = part(SnowGeometry.blob(radius: 0.362, seed: k, lump: 0.03, rings: 40, segments: 80), PBR.snow(), at: headCenter + SIMD3<Float>(0, -0.04, 0), scale: SIMD3<Float>(0.82, 0.72, 1.0))
            root.addChildNode(face)
            for dy: Float in [0.56, 0.42] {
                let rr = sqrt(0.25 - (dy - 0.5) * (dy - 0.5)) + 0.004
                root.addChildNode(part(SCNTorus(ringRadius: CGFloat(rr), pipeRadius: 0.016), PBR.metal(gold, roughness: 0.28), at: SIMD3<Float>(0, dy, 0)))
            }
        case .kuma:
            let muzzle = part(SnowGeometry.blob(radius: 0.355, seed: k, lump: 0.03, rings: 40, segments: 80), PBR.fleece(UIColor(red: 0.96, green: 0.90, blue: 0.80, alpha: 1)), at: headCenter + SIMD3<Float>(0, -0.10, 0), scale: SIMD3<Float>(0.40, 0.30, 1.0))
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
                let start = SIMD3<Float>(sign * 0.44, 0.64, 0.04)
                let end = SIMD3<Float>(sign * 0.98, 0.98, 0.10)
                root.addChildNode(stick(from: start, to: end, radius: 0.02))
                let mid = start + (end - start) * 0.6
                root.addChildNode(stick(from: mid, to: mid + SIMD3<Float>(sign * 0.10, 0.18, 0.0), radius: 0.012))
                root.addChildNode(stick(from: mid, to: mid + SIMD3<Float>(sign * 0.18, 0.05, 0.02), radius: 0.011))
                if let mitten {
                    let tone = UIColor(Palette.tone(mitten.hue).base)
                    let glove = part(SnowGeometry.blob(radius: 0.075, seed: 9, lump: 0.05, rings: 16, segments: 28, tile: (1, 1)), PBR.fleece(tone), at: end)
                    root.addChildNode(glove)
                }
            }
        } else if s == .penguin {
            for sign: Float in [-1, 1] {
                let flipper = part(SnowGeometry.blob(radius: 0.24, seed: 7, lump: 0.03, rings: 24, segments: 48, tile: (1, 1)), PBR.charcoal(), at: SIMD3<Float>(sign * 0.54, 0.55, 0.02), scale: SIMD3<Float>(0.22, 1.0, 0.5))
                flipper.eulerAngles.z = -sign * 0.42
                root.addChildNode(flipper)
                let foot = part(SnowGeometry.blob(radius: 0.10, seed: 8, lump: 0.03, rings: 16, segments: 28, tile: (1, 1)), PBR.felt(beakOrange), at: SIMD3<Float>(sign * 0.20, 0.035, 0.46), scale: SIMD3<Float>(1.2, 0.35, 1.5))
                root.addChildNode(foot)
            }
        } else if s == .hiyoko {
            for sign: Float in [-1, 1] {
                let wing = part(SnowGeometry.blob(radius: 0.2, seed: 7, lump: 0.03, rings: 24, segments: 48, tile: (1, 1)), PBR.fleece(UIColor(red: 1.0, green: 0.78, blue: 0.26, alpha: 1)), at: SIMD3<Float>(sign * 0.50, 0.58, 0.04), scale: SIMD3<Float>(0.3, 1.0, 0.7))
                wing.eulerAngles.z = -sign * 0.5
                root.addChildNode(wing)
                let foot = part(SnowGeometry.blob(radius: 0.08, seed: 8, lump: 0.03, rings: 16, segments: 28, tile: (1, 1)), PBR.felt(beakOrange), at: SIMD3<Float>(sign * 0.18, 0.03, 0.46), scale: SIMD3<Float>(1.2, 0.35, 1.5))
                root.addChildNode(foot)
            }
        }
    }

    // MARK: 顔

    private static func coalEyes(on root: SCNNode, az: Float = 0.34, el: Float = 0.12, size: Float = 0.032) {
        for (i, sign) in ([-1, 1] as [Float]).enumerated() {
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: sign * az, el: el)
            root.addChildNode(coalPiece(size, seed: UInt32(30 + i), at: p + n * 0.004, normal: n, scale: SIMD3<Float>(1, 1.1, 0.8)))
        }
    }

    private static func coalSmile(on root: SCNNode, el0: Float = -0.30, count: Int = 5, spread: Float = 0.085, size: Float = 0.016) {
        for i in 0..<count {
            let k = Float(i) - Float(count - 1) / 2
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: k * spread, el: el0 + 0.024 * abs(k))
            root.addChildNode(coalPiece(size, seed: UInt32(40 + i), at: p + n * 0.003, normal: n))
        }
    }

    private static func nose(_ color: SCNMaterial, size: Float, el: Float, on root: SCNNode, flat: Float = 0.8) {
        let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: el)
        let node = part(SnowGeometry.blob(radius: size, seed: 3, lump: 0.05, rings: 16, segments: 28, tile: (1, 1)), color, at: p + n * 0.006, scale: SIMD3<Float>(1.1, flat, 0.9))
        root.addChildNode(node)
    }

    private static func addFace(_ s: Species, seed k: UInt32, to root: SCNNode) {
        switch s {
        case .plain:
            coalEyes(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.04)
            let dir = simd_normalize(n + SIMD3<Float>(0, -0.14, 0))
            root.addChildNode(cone(radius: 0.05, height: 0.27, material: PBR.carrot(), base: p - n * 0.02, direction: dir))
            coalSmile(on: root, el0: -0.36)
        case .usagi:
            coalEyes(on: root)
            nose(PBR.fleece(felt), size: 0.028, el: -0.06, on: root)
            coalSmile(on: root, el0: -0.26, count: 3, spread: 0.07, size: 0.011)
        case .neko:
            coalEyes(on: root)
            nose(PBR.fleece(felt), size: 0.026, el: -0.06, on: root)
            coalSmile(on: root, el0: -0.26, count: 3, spread: 0.07, size: 0.011)
            for sign: Float in [-1, 1] {
                for i in 0..<3 {
                    let a = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.45, el: -0.12 + Float(i) * 0.05).p
                    root.addChildNode(stick(from: a, to: a + SIMD3<Float>(sign * 0.22, Float(i - 1) * 0.07, 0.04), radius: 0.004))
                }
            }
        case .kuma:
            coalEyes(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.14)
            root.addChildNode(coalPiece(0.034, seed: 50, at: p + n * 0.012, normal: n, scale: SIMD3<Float>(1.2, 0.9, 0.8)))
        case .inu:
            coalEyes(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.08)
            root.addChildNode(coalPiece(0.042, seed: 51, at: p + n * 0.01, normal: n, scale: SIMD3<Float>(1.2, 0.9, 0.8)))
            coalSmile(on: root, el0: -0.26, count: 3, spread: 0.07, size: 0.011)
            for sign: Float in [-1, 1] {
                let ear = part(SnowGeometry.blob(radius: 0.15, seed: 12, lump: 0.04, rings: 24, segments: 48, tile: (1, 1)), PBR.fleece(UIColor(red: 0.78, green: 0.56, blue: 0.34, alpha: 1)), at: headCenter + SIMD3<Float>(sign * 0.33, 0.02, 0.02), scale: SIMD3<Float>(0.5, 1.2, 0.42))
                ear.eulerAngles.z = -sign * 0.22
                root.addChildNode(ear)
            }
        case .penguin:
            coalEyes(on: root, az: 0.30, el: 0.14)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.06)
            root.addChildNode(cone(radius: 0.06, height: 0.17, material: PBR.felt(beakOrange), base: p - n * 0.01, direction: simd_normalize(n + SIMD3<Float>(0, -0.2, 0))))
        case .hiyoko:
            coalEyes(on: root)
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: -0.04)
            root.addChildNode(cone(radius: 0.05, height: 0.13, material: PBR.felt(beakOrange), base: p - n * 0.01, direction: simd_normalize(n + SIMD3<Float>(0, -0.2, 0))))
            for (dx, tilt) in [(Float(-0.07), Float(-0.5)), (0, 0), (0.07, 0.5)] as [(Float, Float)] {
                root.addChildNode(cone(radius: 0.035, height: 0.14, material: PBR.fleece(UIColor(red: 1.0, green: 0.78, blue: 0.26, alpha: 1)), base: headCenter + SIMD3<Float>(dx, 0.31, 0.02), direction: SIMD3<Float>(sin(tilt), 1, 0), segments: 12))
            }
        case .daruma:
            for sign: Float in [-1, 1] {
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.28, el: 0.05)
                let white = part(SnowGeometry.blob(radius: 0.05, seed: 13, lump: 0.02, rings: 16, segments: 28, tile: (1, 1)), PBR.plastic(UIColor(white: 0.97, alpha: 1), roughness: 0.25), at: p + n * 0.012, scale: SIMD3<Float>(1, 1, 0.45))
                orient(white, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(white)
                root.addChildNode(coalPiece(0.024, seed: 52, at: p + n * 0.03, normal: n, scale: SIMD3<Float>(1, 1, 0.5)))
                let (bp, bn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.28, el: 0.33)
                let brow = part(SCNCapsule(capRadius: 0.018, height: 0.17), PBR.coal(), at: bp + bn * 0.006)
                brow.eulerAngles = SCNVector3(0, 0, Float.pi / 2 + sign * 0.28)
                root.addChildNode(brow)
                let (mp, mn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.2, el: -0.32)
                let mus = part(SCNCapsule(capRadius: 0.014, height: 0.14), PBR.coal(), at: mp + mn * 0.006)
                mus.eulerAngles = SCNVector3(0, 0, Float.pi / 2 - sign * 0.35)
                root.addChildNode(mus)
            }
            nose(PBR.fleece(felt), size: 0.026, el: -0.10, on: root)
        case .tenshi:
            coalEyes(on: root)
            coalSmile(on: root, el0: -0.26, count: 3, spread: 0.07, size: 0.011)
        case .ousama:
            coalEyes(on: root)
            nose(PBR.carrot(), size: 0.035, el: -0.04, on: root, flat: 1.0)
            for sign: Float in [-1, 1] {
                let (mp, mn) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.17, el: -0.26)
                let mus = snowBlob(0.07, seed: 14, lump: 0.05, at: mp + mn * 0.012, scale: SIMD3<Float>(1.0, 0.65, 0.6))
                mus.eulerAngles.z = sign * 0.35
                root.addChildNode(mus)
            }
        }
    }

    // MARK: 種類ごとの印

    private static func addSignature(_ s: Species, to root: SCNNode) {
        switch s {
        case .tenshi:
            let halo = part(SCNTorus(ringRadius: 0.21, pipeRadius: 0.024), PBR.metal(gold, roughness: 0.2), at: headCenter + SIMD3<Float>(0, 0.50, -0.02))
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
        let goldMat = PBR.metal(gold, roughness: 0.22)
        group.addChildNode(part(SCNCylinder(radius: 0.2, height: 0.09), goldMat))
        let count = 5
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            group.addChildNode(cone(radius: 0.045, height: 0.15, material: goldMat, base: SIMD3<Float>(sin(a) * 0.17, 0.04, cos(a) * 0.17), direction: SIMD3<Float>(sin(a) * 0.12, 1, cos(a) * 0.12), segments: 12))
            let gemColor = [UIColor(red: 0.85, green: 0.1, blue: 0.2, alpha: 1), UIColor(red: 0.15, green: 0.4, blue: 0.9, alpha: 1)][i % 2]
            group.addChildNode(part(SCNSphere(radius: 0.022), PBR.plastic(gemColor, roughness: 0.08), at: SIMD3<Float>(sin(a) * 0.205, 0.0, cos(a) * 0.205)))
        }
        return group
    }

    // MARK: 飾り

    private static func addDecoration(_ d: Decoration, species: Species, to root: SCNNode) {
        let tone = Palette.tone(d.hue)
        let base = UIColor(tone.base)
        let dark = UIColor(tone.dark)
        let top = headCenter.y + headRadius
        switch d.kind {
        case .bucketHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, top - 0.10, 0)
            group.eulerAngles.z = 0.07
            let pail = doubleSided(PBR.plastic(base, roughness: 0.32))
            group.addChildNode(part(lathe(profile: [CGPoint(x: 0, y: 0.27), CGPoint(x: 0.18, y: 0.27), CGPoint(x: 0.215, y: 0.25), CGPoint(x: 0.27, y: 0.0)]), pail))
            group.addChildNode(part(SCNTorus(ringRadius: 0.27, pipeRadius: 0.022), pail, at: SIMD3<Float>(0, 0.0, 0)))
            group.addChildNode(part(SCNTorus(ringRadius: 0.215, pipeRadius: 0.014), pail, at: SIMD3<Float>(0, 0.22, 0)))
            root.addChildNode(group)
        case .topHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, top - 0.07, 0)
            group.eulerAngles.z = -0.06
            let black = PBR.felt(UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
            group.addChildNode(part(SCNCylinder(radius: 0.36, height: 0.035), black))
            group.addChildNode(part(SCNCylinder(radius: 0.21, height: 0.36), black, at: SIMD3<Float>(0, 0.2, 0)))
            group.addChildNode(part(SCNCylinder(radius: 0.215, height: 0.07), PBR.fleece(base), at: SIMD3<Float>(0, 0.08, 0)))
            root.addChildNode(group)
        case .santaHat:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0.02, top - 0.14, 0)
            group.eulerAngles.z = -0.28
            let red = doubleSided(PBR.fleece(base))
            group.addChildNode(part(lathe(profile: [CGPoint(x: 0, y: 0.52), CGPoint(x: 0.07, y: 0.46), CGPoint(x: 0.15, y: 0.30), CGPoint(x: 0.27, y: 0.04), CGPoint(x: 0.27, y: 0)]), red))
            let white = PBR.fleece(UIColor(white: 0.97, alpha: 1))
            group.addChildNode(part(SCNTorus(ringRadius: 0.27, pipeRadius: 0.055), white, at: SIMD3<Float>(0, 0.01, 0)))
            group.addChildNode(part(SCNSphere(radius: 0.07), white, at: SIMD3<Float>(0.03, 0.54, 0)))
            root.addChildNode(group)
        case .knitCap:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, headCenter.y + 0.02, 0)
            let wool = doubleSided(PBR.fleece(base))
            group.addChildNode(part(lathe(profile: [
                CGPoint(x: 0, y: 0.40), CGPoint(x: 0.14, y: 0.385), CGPoint(x: 0.25, y: 0.32), CGPoint(x: 0.32, y: 0.20),
                CGPoint(x: 0.352, y: 0.09), CGPoint(x: 0.356, y: 0.0),
            ]), wool))
            group.addChildNode(part(SCNTorus(ringRadius: 0.35, pipeRadius: 0.045), doubleSided(PBR.fleece(dark)), at: SIMD3<Float>(0, 0.05, 0)))
            group.addChildNode(part(SCNSphere(radius: 0.07), PBR.fleece(UIColor(white: 0.97, alpha: 1)), at: SIMD3<Float>(0, 0.43, 0)))
            group.eulerAngles.x = -0.08
            root.addChildNode(group)
        case .earmuffs:
            let wire = PBR.metal(UIColor(red: 0.62, green: 0.64, blue: 0.68, alpha: 1), roughness: 0.3)
            for i in 0...14 {
                let a = Float.pi * Float(i) / 14
                root.addChildNode(part(SCNSphere(radius: 0.02), wire, at: headCenter + SIMD3<Float>(-cos(a) * 0.36, sin(a) * 0.40, 0)))
            }
            for sign: Float in [-1, 1] {
                root.addChildNode(part(SCNSphere(radius: 0.1), PBR.fleece(base), at: headCenter + SIMD3<Float>(sign * 0.35, 0.0, 0), scale: SIMD3<Float>(0.6, 1.0, 1.0)))
            }
        case .flowerCrown:
            let count = 7
            for i in 0..<count {
                let az = (Float(i) / Float(count) - 0.5) * 2 * .pi
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: az, el: 0.95)
                let flower = SCNNode()
                flower.simdPosition = p
                let petal = PBR.felt(UIColor(Palette.tone(d.hue + i).base))
                for k in 0..<5 {
                    let a = Float(k) / 5 * 2 * .pi
                    flower.addChildNode(part(SCNSphere(radius: 0.035), petal, at: SIMD3<Float>(cos(a) * 0.045, sin(a) * 0.045, 0), scale: SIMD3<Float>(1, 1, 0.6)))
                }
                flower.addChildNode(part(SCNSphere(radius: 0.026), PBR.felt(UIColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 1)), at: SIMD3<Float>(0, 0, 0.01)))
                orient(flower, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(flower)
            }
        case .ribbon:
            let group = SCNNode()
            let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: 0.55, el: 0.78)
            group.simdPosition = p + n * 0.02
            orient(group, axis: SIMD3<Float>(0, 0, 1), to: n)
            let cloth = PBR.fleece(base)
            for sign: Float in [-1, 1] {
                let wing = part(SCNSphere(radius: 0.085), cloth, at: SIMD3<Float>(sign * 0.09, 0, 0), scale: SIMD3<Float>(1.3, 0.8, 0.5))
                wing.eulerAngles.z = sign * 0.35
                group.addChildNode(wing)
            }
            group.addChildNode(part(SCNSphere(radius: 0.045), PBR.fleece(dark), at: SIMD3<Float>(0, 0, 0.02)))
            root.addChildNode(group)
        case .sunglasses:
            let glass = PBR.plastic(UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1), roughness: 0.08)
            for sign: Float in [-1, 1] {
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.33, el: 0.13)
                let lens = part(SCNSphere(radius: 0.07), glass, at: p + n * 0.02, scale: SIMD3<Float>(1.15, 0.85, 0.35))
                orient(lens, axis: SIMD3<Float>(0, 0, 1), to: n)
                root.addChildNode(lens)
            }
            let (bp, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: 0.13)
            let bridge = part(SCNCylinder(radius: 0.008, height: 0.1), glass, at: bp + SIMD3<Float>(0, 0, 0.02))
            bridge.eulerAngles.z = Float.pi / 2
            root.addChildNode(bridge)
        case .roundGlasses:
            let wire = PBR.metal(gold, roughness: 0.25)
            for sign: Float in [-1, 1] {
                let (p, n) = surfacePoint(center: headCenter, radius: headRadius, az: sign * 0.36, el: 0.13)
                let ring = part(SCNTorus(ringRadius: 0.075, pipeRadius: 0.009), wire, at: p + n * 0.012)
                orient(ring, axis: SIMD3<Float>(0, 1, 0), to: n)
                root.addChildNode(ring)
            }
            let (bp, _) = surfacePoint(center: headCenter, radius: headRadius, az: 0, el: 0.14)
            let bridge = part(SCNCylinder(radius: 0.006, height: 0.08), wire, at: bp + SIMD3<Float>(0, 0, 0.012))
            bridge.eulerAngles.z = Float.pi / 2
            root.addChildNode(bridge)
        case .scarf:
            let cloth = PBR.fleece(base)
            let ring = part(SCNTorus(ringRadius: 0.30, pipeRadius: 0.085), cloth, at: SIMD3<Float>(0, 0.97, 0.01))
            ring.eulerAngles.x = 0.06
            root.addChildNode(ring)
            let tail = part(SCNBox(width: 0.16, height: 0.44, length: 0.06, chamferRadius: 0.025), cloth, at: SIMD3<Float>(0.15, 0.74, 0.37))
            tail.eulerAngles = SCNVector3(-0.12, 0.0, -0.06)
            for dy: Float in [-0.02, -0.11] {
                tail.addChildNode(part(SCNBox(width: 0.165, height: 0.035, length: 0.065, chamferRadius: 0.01), PBR.fleece(dark), at: SIMD3<Float>(0, dy, 0)))
            }
            root.addChildNode(tail)
        case .bowtie:
            let group = SCNNode()
            group.simdPosition = SIMD3<Float>(0, 0.96, 0.36)
            let cloth = PBR.fleece(base)
            for sign: Float in [-1, 1] {
                let wing = part(SCNCone(topRadius: 0, bottomRadius: 0.1, height: 0.13), cloth, at: SIMD3<Float>(sign * 0.075, 0, 0))
                wing.eulerAngles.z = -sign * Float.pi / 2
                group.addChildNode(wing)
            }
            group.addChildNode(part(SCNSphere(radius: 0.04), PBR.fleece(dark), at: SIMD3<Float>(0, 0, 0.02)))
            root.addChildNode(group)
        case .buttons:
            let plastic = PBR.plastic(dark, roughness: 0.3)
            for dy: Float in [0.22, 0.02, -0.18] {
                let y = bodyCenter.y + dy
                let el = asin(dy / bodyRadius)
                let (p, n) = surfacePoint(center: bodyCenter, radius: bodyRadius, az: 0, el: el)
                let button = part(SCNCylinder(radius: 0.045, height: 0.025), plastic, at: SIMD3<Float>(p.x, y, p.z) + n * 0.004)
                orient(button, axis: SIMD3<Float>(0, 1, 0), to: n)
                root.addChildNode(button)
            }
        case .stripe:
            let cloth = PBR.fleece(base)
            for dy: Float in [0.08, -0.12] {
                let rr = sqrt(bodyRadius * bodyRadius - dy * dy) - 0.002
                root.addChildNode(part(SCNTorus(ringRadius: CGFloat(rr), pipeRadius: 0.03), cloth, at: SIMD3<Float>(0, bodyCenter.y + dy, 0)))
            }
        case .mittens:
            break // 腕を作るときに一緒に付ける
        }
    }
}
