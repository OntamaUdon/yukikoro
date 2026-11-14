import SwiftUI
import SceneKit
import UIKit

/// 雪玉を押している仲間の見た目
struct CrewLook: Equatable {
    /// 0 = ゆきんこ 1 = でかゆきんこ 2 = そりいた 3 = クローラー 4 = おおがたクローラー
    var tier: Int
    /// 見せる数（最大 8）
    var count: Int
    /// 重力そうちの数
    var gravity: Int
}

struct StageInput: Equatable {
    /// 雪玉の半径（メートル）
    var radius: Double
    /// 転がった角度（ラジアン）
    var angle: Double
    var daypart: Daypart
    var crew: CrewLook
    var blackHole: Bool
    /// タップのたびに増える（ぎゅっとする動きの合図）
    var squishTick: Int
}

/// 3D の舞台。雪玉はいつも半径 1 の球で、世界のほうを 1/半径 に縮める。
/// だから、雪玉が大きくなっても見かけの大きさは変わらず、まわりの木や仲間が小さくなって、大きくなったことが分かる。
struct SnowStage: UIViewRepresentable {
    let input: StageInput

    func makeCoordinator() -> StageCoordinator { StageCoordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = context.coordinator.scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        context.coordinator.apply(input)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.apply(input)
    }
}

final class StageCoordinator {
    let scene = SCNScene()

    private let ball = SCNNode()
    private let ballMaterial = SCNMaterial()
    private let ring = SCNNode()
    private let shadow = SCNNode()
    private let world = SCNNode()
    private let ground = SCNNode()
    private let forest = SCNNode()
    private let crew = SCNNode()
    private let orbit = SCNNode()
    private let ambient = SCNNode()
    private let sun = SCNNode()

    private struct Tree {
        let node: SCNNode
        let side: Double
        let lateral: Double
        let phase: Double
    }
    private var trees: [Tree] = []

    private var lastAngle: Double?
    /// 転がった道のり（メートル、240 でひと巡り）
    private var scroll: Double = 0
    private var lastCrew: CrewLook?
    private var lastDaypart: Daypart?
    private var lastSquish = 0
    private var lastBlackHole = false
    private var crewTierSize: Double = 1

    private static let treePeriod = 240.0
    private static let treeNear = 40.0
    private static let groundTile = 8.0
    private static let tierSizes: [Double] = [0.8, 2.2, 3.0, 5.0, 12.0]

    init() {
        scene.background.contents = UIColor.clear
        scene.fogStartDistance = 30
        scene.fogEndDistance = 170
        scene.fogDensityExponent = 1

        // カメラ（雪玉の後ろ上 30°から、少し水平寄りに見下ろす）
        let camera = SCNCamera()
        camera.fieldOfView = StageGeometry.fieldOfView
        camera.zNear = 0.1
        camera.zFar = 3_000_000
        camera.projectionDirection = .vertical
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        let elevation = StageGeometry.elevation * .pi / 180
        cameraNode.position = SCNVector3(0, Float(StageGeometry.distance * sin(elevation)), Float(StageGeometry.distance * cos(elevation)))
        cameraNode.eulerAngles = SCNVector3(Float(-StageGeometry.pitch * .pi / 180), 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        // 光
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        scene.rootNode.addChildNode(ambient)
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.eulerAngles = SCNVector3(-0.9, 0.5, 0)
        scene.rootNode.addChildNode(sun)

        // 雪玉
        ballMaterial.lightingModel = .lambert
        ballMaterial.diffuse.contents = Self.speckle(size: 256, base: UIColor(white: 0.97, alpha: 1), spots: 700, seed: 3, tint: UIColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 1))
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 56
        sphere.materials = [ballMaterial]
        ball.geometry = sphere
        scene.rootNode.addChildNode(ball)

        // ブラックホールのときの輪
        let torus = SCNTorus(ringRadius: 1.9, pipeRadius: 0.14)
        let ringMaterial = SCNMaterial()
        ringMaterial.lightingModel = .constant
        ringMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.62, blue: 0.2, alpha: 1)
        ringMaterial.emission.contents = UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1)
        torus.materials = [ringMaterial]
        ring.geometry = torus
        ring.eulerAngles = SCNVector3(0.35, 0, 0.2)
        ring.isHidden = true
        scene.rootNode.addChildNode(ring)

        // 雪玉の影
        let shadowPlane = SCNPlane(width: 3.4, height: 3.4)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = Self.shadowImage(size: 128)
        shadowMaterial.writesToDepthBuffer = false
        shadowMaterial.isDoubleSided = true
        shadowPlane.materials = [shadowMaterial]
        shadow.geometry = shadowPlane
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, -0.99, 0)
        scene.rootNode.addChildNode(shadow)

        // 世界（雪玉の足元が地面）
        world.position = SCNVector3(0, -1, 0)
        scene.rootNode.addChildNode(world)

        let plane = SCNPlane(width: 3_000, height: 3_000)
        let groundMaterial = SCNMaterial()
        groundMaterial.lightingModel = .lambert
        groundMaterial.diffuse.contents = Self.speckle(size: 256, base: UIColor(white: 0.97, alpha: 1), spots: 260, seed: 9, tint: UIColor(red: 0.78, green: 0.88, blue: 1.0, alpha: 1))
        let repeatCount = Float(3_000 / Self.groundTile)
        groundMaterial.diffuse.wrapS = .repeat
        groundMaterial.diffuse.wrapT = .repeat
        groundMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatCount, repeatCount, 1)
        plane.materials = [groundMaterial]
        ground.geometry = plane
        ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        world.addChildNode(ground)

        world.addChildNode(forest)
        buildForest()
        world.addChildNode(crew)

        // 重力そうちの玉（雪玉のまわりを回る）
        scene.rootNode.addChildNode(orbit)
    }

    // MARK: 更新

    func apply(_ input: StageInput) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        defer { SCNTransaction.commit() }

        let r = max(input.radius, 1e-6)
        let s = Float(1.0 / r)

        if let last = lastAngle {
            scroll += (input.angle - last) * r
            scroll = scroll.truncatingRemainder(dividingBy: Self.treePeriod)
            if scroll < 0 { scroll += Self.treePeriod }
        }
        lastAngle = input.angle

        ball.eulerAngles = SCNVector3(Float(-input.angle.truncatingRemainder(dividingBy: 2 * .pi)), 0, 0)
        world.scale = SCNVector3(s, s, s)

        // 地面が大きくなりすぎた雪玉のまわりでも途切れないように広げる
        let groundScale = Float(max(1.0, r / 300))
        ground.scale = SCNVector3(groundScale, groundScale, 1)
        let tile = Self.groundTile * Double(groundScale)
        ground.position = SCNVector3(0, 0, Float(scroll.truncatingRemainder(dividingBy: tile)))

        updateForest(radius: r)
        updateCrew(input.crew, radius: r)

        if lastDaypart != input.daypart {
            lastDaypart = input.daypart
            applyDaypart(input.daypart)
        }
        if lastBlackHole != input.blackHole {
            lastBlackHole = input.blackHole
            applyBlackHole(input.blackHole)
        }
        if input.squishTick != lastSquish {
            lastSquish = input.squishTick
            squish()
        }
        orbit.eulerAngles = SCNVector3(0.5, Float(input.angle * 0.35), 0)
    }

    // MARK: 木

    private func buildForest() {
        let template = Self.makeTree()
        var generator = SplitMix64(seed: 2024)
        for i in 0..<90 {
            let node = template.clone()
            let scale = Float(0.8 + Double(generator.next() % 100) / 100 * 0.6)
            node.scale = SCNVector3(scale, scale, scale)
            node.eulerAngles = SCNVector3(0, Float(Double(i) * 0.7), 0)
            forest.addChildNode(node)
            trees.append(Tree(
                node: node,
                side: i % 2 == 0 ? 1 : -1,
                lateral: Double(generator.next() % 1_000) / 1_000,
                phase: Double(generator.next() % 1_000) / 1_000
            ))
        }
    }

    private func updateForest(radius r: Double) {
        let period = Self.treePeriod
        for tree in trees {
            let x = tree.side * (6 + 1.35 * r + tree.lateral * (30 + 3 * r))
            var z = (tree.phase * period + scroll).truncatingRemainder(dividingBy: period)
            z = z - period + Self.treeNear
            tree.node.position = SCNVector3(Float(x), 0, Float(z))
        }
    }

    private static func makeTree() -> SCNNode {
        let root = SCNNode()
        let trunkMaterial = SCNMaterial()
        trunkMaterial.lightingModel = .lambert
        trunkMaterial.diffuse.contents = UIColor(red: 0.45, green: 0.32, blue: 0.24, alpha: 1)
        let leafMaterial = SCNMaterial()
        leafMaterial.lightingModel = .lambert
        leafMaterial.diffuse.contents = UIColor(red: 0.30, green: 0.52, blue: 0.46, alpha: 1)
        let snowMaterial = SCNMaterial()
        snowMaterial.lightingModel = .lambert
        snowMaterial.diffuse.contents = UIColor(white: 0.97, alpha: 1)

        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.28, height: 1.4))
        trunk.geometry?.materials = [trunkMaterial]
        trunk.position = SCNVector3(0, 0.7, 0)
        root.addChildNode(trunk)

        let tiers: [(radius: CGFloat, height: CGFloat, y: Float)] = [(2.5, 3.6, 3.0), (1.9, 3.2, 4.9), (1.3, 2.8, 6.5)]
        for tier in tiers {
            let cone = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: tier.radius, height: tier.height))
            cone.geometry?.materials = [leafMaterial]
            cone.position = SCNVector3(0, tier.y, 0)
            root.addChildNode(cone)
            let cap = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: tier.radius * 0.45, height: tier.height * 0.42))
            cap.geometry?.materials = [snowMaterial]
            cap.position = SCNVector3(0, tier.y + Float(tier.height) * 0.30, 0)
            root.addChildNode(cap)
        }
        return root
    }

    // MARK: 仲間

    private func updateCrew(_ look: CrewLook, radius r: Double) {
        if lastCrew != look {
            lastCrew = look
            rebuildCrew(look)
        }
        // 見た目の大きさ: 本来の大きさ。ただし雪玉が小さいうちは、雪玉より大きくなりすぎないようにする。
        let tierIndex = min(max(look.tier, 0), Self.tierSizes.count - 1)
        let nominal = Self.tierSizes[tierIndex]
        let size = min(nominal, 1.6 * r)
        let factor = Float(size / nominal)
        crew.scale = SCNVector3(factor, factor, factor)
        let handHeight = min(0.75 * size, 1.8 * r)
        let surface = max(0, r * r - (r - handHeight) * (r - handHeight)).squareRoot()
        crew.position = SCNVector3(0, 0, Float(surface + 0.45 * size))

        // 横に並べる幅が、雪玉の幅に収まるようにする
        let count = max(1, look.count)
        if count > 1 {
            let natural = 0.85 * nominal
            let limit = 1.7 * r / Double(count - 1) / (size / nominal)
            let spacing = min(natural, limit)
            for (index, node) in crew.childNodes.enumerated() {
                let x = (Double(index) - Double(count - 1) / 2) * spacing
                node.position = SCNVector3(Float(x), 0, 0)
            }
        }

        orbit.isHidden = look.gravity == 0
    }

    private func rebuildCrew(_ look: CrewLook) {
        crew.childNodes.forEach { $0.removeFromParentNode() }
        let tier = min(max(look.tier, 0), Self.tierSizes.count - 1)
        let size = Self.tierSizes[tier]
        for _ in 0..<max(1, min(look.count, 8)) {
            let figure = Self.makeFigure(tier: tier)
            figure.scale = SCNVector3(Float(size), Float(size), Float(size))
            crew.addChildNode(figure)
        }

        orbit.childNodes.forEach { $0.removeFromParentNode() }
        let orbMaterial = SCNMaterial()
        orbMaterial.lightingModel = .constant
        orbMaterial.diffuse.contents = UIColor(red: 0.72, green: 0.55, blue: 1.0, alpha: 1)
        orbMaterial.emission.contents = UIColor(red: 0.62, green: 0.40, blue: 1.0, alpha: 1)
        let orbs = min(look.gravity, 6)
        for i in 0..<orbs {
            let orb = SCNNode(geometry: SCNSphere(radius: 0.13))
            orb.geometry?.materials = [orbMaterial]
            let a = Double(i) / Double(max(orbs, 1)) * 2 * .pi
            orb.position = SCNVector3(Float(cos(a) * 1.75), 0, Float(sin(a) * 1.75))
            orbit.addChildNode(orb)
        }
    }

    /// 高さ約 1 の仲間（正面は -z、雪玉のほう）
    private static func makeFigure(tier: Int) -> SCNNode {
        func material(_ color: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = color
            return m
        }
        func sphere(_ r: CGFloat, _ color: UIColor, _ position: SCNVector3) -> SCNNode {
            let node = SCNNode(geometry: SCNSphere(radius: r))
            node.geometry?.materials = [material(color)]
            node.position = position
            return node
        }
        func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ color: UIColor, _ position: SCNVector3) -> SCNNode {
            let node = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0.02))
            node.geometry?.materials = [material(color)]
            node.position = position
            return node
        }

        let root = SCNNode()
        switch tier {
        case 0, 1:
            let white = UIColor(white: 0.98, alpha: 1)
            root.addChildNode(sphere(0.30, white, SCNVector3(0, 0.30, 0)))
            root.addChildNode(sphere(0.21, white, SCNVector3(0, 0.74, 0)))
            let scarfColor = tier == 0 ? UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1) : UIColor(red: 0.25, green: 0.50, blue: 0.95, alpha: 1)
            let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.045))
            scarf.geometry?.materials = [material(scarfColor)]
            scarf.position = SCNVector3(0, 0.56, 0)
            root.addChildNode(scarf)
            let dark = UIColor(white: 0.12, alpha: 1)
            root.addChildNode(sphere(0.025, dark, SCNVector3(-0.07, 0.78, -0.19)))
            root.addChildNode(sphere(0.025, dark, SCNVector3(0.07, 0.78, -0.19)))
            if tier == 1 {
                let hat = SCNNode(geometry: SCNCylinder(radius: 0.14, height: 0.18))
                hat.geometry?.materials = [material(dark)]
                hat.position = SCNVector3(0, 0.99, 0)
                root.addChildNode(hat)
            }
        case 2:
            root.addChildNode(box(1.0, 0.62, 0.08, UIColor(red: 0.72, green: 0.52, blue: 0.34, alpha: 1), SCNVector3(0, 0.34, 0)))
            root.addChildNode(box(1.0, 0.07, 0.30, UIColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1), SCNVector3(0, 0.05, 0.10)))
        case 3:
            root.addChildNode(box(0.9, 0.42, 1.2, UIColor(red: 0.42, green: 0.52, blue: 0.66, alpha: 1), SCNVector3(0, 0.50, 0.1)))
            root.addChildNode(box(0.22, 0.34, 1.5, UIColor(white: 0.18, alpha: 1), SCNVector3(-0.5, 0.17, 0.1)))
            root.addChildNode(box(0.22, 0.34, 1.5, UIColor(white: 0.18, alpha: 1), SCNVector3(0.5, 0.17, 0.1)))
            root.addChildNode(box(1.1, 0.48, 0.07, UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1), SCNVector3(0, 0.42, -0.62)))
        default:
            root.addChildNode(box(0.9, 0.46, 1.2, UIColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1), SCNVector3(0, 0.52, 0.1)))
            root.addChildNode(box(0.26, 0.38, 1.6, UIColor(white: 0.16, alpha: 1), SCNVector3(-0.52, 0.19, 0.1)))
            root.addChildNode(box(0.26, 0.38, 1.6, UIColor(white: 0.16, alpha: 1), SCNVector3(0.52, 0.19, 0.1)))
            root.addChildNode(box(1.2, 0.55, 0.08, UIColor(white: 0.85, alpha: 1), SCNVector3(0, 0.46, -0.66)))
            root.addChildNode(box(0.4, 0.3, 0.4, UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1), SCNVector3(0, 0.88, 0.2)))
        }
        return root
    }

    // MARK: 時間帯・ブラックホール・ぎゅっ

    private func applyDaypart(_ daypart: Daypart) {
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        switch daypart {
        case .day:
            ambient.light?.color = color(0.60, 0.66, 0.78)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.96, 0.88)
            sun.light?.intensity = 800
        case .dusk:
            ambient.light?.color = color(0.55, 0.48, 0.62)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.70, 0.50)
            sun.light?.intensity = 750
        case .night:
            ambient.light?.color = color(0.30, 0.36, 0.58)
            ambient.light?.intensity = 1000
            sun.light?.color = color(0.50, 0.60, 0.95)
            sun.light?.intensity = 450
        }
        scene.fogColor = UIColor(StoryPalette.of(daypart).hillNear)
    }

    private func applyBlackHole(_ on: Bool) {
        ring.isHidden = !on
        if on {
            ballMaterial.diffuse.contents = UIColor.black
            ballMaterial.lightingModel = .constant
        } else {
            ballMaterial.diffuse.contents = Self.speckle(size: 256, base: UIColor(white: 0.97, alpha: 1), spots: 700, seed: 3, tint: UIColor(red: 0.80, green: 0.90, blue: 1.0, alpha: 1))
            ballMaterial.lightingModel = .lambert
        }
    }

    private func squish() {
        ball.removeAllActions()
        ball.runAction(.sequence([
            .scale(to: 0.94, duration: 0.07),
            .scale(to: 1.0, duration: 0.16),
        ]))
    }

    // MARK: 画像

    private static func speckle(size: Int, base: UIColor, spots: Int, seed: UInt64, tint: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            base.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var generator = SplitMix64(seed: seed)
            for _ in 0..<spots {
                let x = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let y = CGFloat(generator.next() % 1_000) / 1_000 * CGFloat(size)
                let radius = 1.5 + CGFloat(generator.next() % 100) / 100 * 7
                let alpha = 0.10 + CGFloat(generator.next() % 100) / 100 * 0.18
                tint.withAlphaComponent(alpha).setFill()
                for dx in [-CGFloat(size), 0, CGFloat(size)] {
                    for dy in [-CGFloat(size), 0, CGFloat(size)] {
                        cg.fillEllipse(in: CGRect(x: x + dx - radius, y: y + dy - radius, width: radius * 2, height: radius * 2))
                    }
                }
            }
        }
    }

    private static func shadowImage(size: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor(white: 0, alpha: 0.36).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        }
    }
}
