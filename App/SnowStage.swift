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

    private let camera = SCNCamera()
    private let ball = SCNNode()
    private let ballMaterial = SCNMaterial()
    private let ring = SCNNode()
    private let shadow = SCNNode()
    private let world = SCNNode()
    private let ground = SCNNode()
    private let crew = SCNNode()
    private let orbit = SCNNode()
    private let ambient = SCNNode()
    private let sun = SCNNode()

    // 木の道に使う材料
    private let trunkMaterial = SCNMaterial()
    private let leafMaterial = SCNMaterial()
    private let snowCapMaterial = SCNMaterial()
    /// イルミネーションの電球（4色）
    private var bulbMaterials: [SCNMaterial] = []

    /// 木の道 1 本ぶん（左右 2 列、等間隔）
    private struct LaneLayer {
        let root: SCNNode
        let holders: [SCNNode]
    }
    private var layers: [LaneLayer] = []

    private var lastAngle: Double?
    /// 転がった道のり（メートル）
    private var scroll: Double = 0
    private var lastCrew: CrewLook?
    private var lastDaypart: Daypart?
    private var lastSquish = 0
    private var lastBlackHole = false

    private static let pairsPerLane = 14
    private static let tierSizes: [Double] = [0.8, 2.2, 3.0, 5.0, 12.0]
    private static let groundTile = 8.0

    init() {
        scene.background.contents = UIColor.clear
        scene.fogStartDistance = 30
        scene.fogEndDistance = 170
        scene.fogDensityExponent = 1

        // カメラ（雪玉の後ろ上 30°から、少し水平寄りに見下ろす）
        camera.fieldOfView = StageGeometry.fieldOfView
        camera.zNear = 0.1
        camera.zFar = 3_000_000
        camera.projectionDirection = .vertical
        camera.bloomThreshold = 0.8
        camera.bloomBlurRadius = 12
        camera.bloomIntensity = 0
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

        setUpMaterials()
        // 左右 2 列の木の道。落ちていく道・いまの道・次の道の 3 本ぶんを用意しておく。
        let variants = (0..<3).map { makeTreeGeometry(seed: UInt64($0 + 1) * 7_919) }
        for _ in 0..<3 {
            let layer = makeLane(variants: variants)
            world.addChildNode(layer.root)
            layers.append(layer)
        }
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
        }
        lastAngle = input.angle

        ball.eulerAngles = SCNVector3(Float(-input.angle.truncatingRemainder(dividingBy: 2 * .pi)), 0, 0)
        world.scale = SCNVector3(s, s, s)

        // 地面が大きくなりすぎた雪玉のまわりでも途切れないように広げる
        let groundScale = Float(max(1.0, r / 300))
        ground.scale = SCNVector3(groundScale, groundScale, 1)
        let tile = Self.groundTile * Double(groundScale)
        ground.position = SCNVector3(0, 0, Float(scroll.truncatingRemainder(dividingBy: tile)))

        updateLanes(radius: r)
        updateCrew(input.crew, radius: r, angle: input.angle)

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

    // MARK: 木の道

    private func setUpMaterials() {
        trunkMaterial.lightingModel = .lambert
        trunkMaterial.diffuse.contents = UIColor(red: 0.30, green: 0.21, blue: 0.15, alpha: 1)
        leafMaterial.lightingModel = .lambert
        leafMaterial.diffuse.contents = UIColor(red: 0.10, green: 0.27, blue: 0.20, alpha: 1)
        snowCapMaterial.lightingModel = .lambert
        snowCapMaterial.diffuse.contents = UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1)

        let bulbColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.84, blue: 0.52, alpha: 1),
            UIColor(red: 1.0, green: 0.52, blue: 0.74, alpha: 1),
            UIColor(red: 0.50, green: 0.86, blue: 1.0, alpha: 1),
            UIColor(red: 0.70, green: 1.0, blue: 0.62, alpha: 1),
        ]
        for color in bulbColors {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.emission.contents = color
            material.emission.intensity = 0
            bulbMaterials.append(material)
        }
    }

    /// 木の形（頂点を直接つくる）。高さは約 8。幹・葉・雪・電球 4 色の 7 つの面に分けて、材料を共有する。
    /// 針葉樹らしく、段ごとに少し不ぞろいで、枝先がたれ、上に雪がのる。
    private func makeTreeGeometry(seed: UInt64) -> SCNGeometry {
        var generator = SplitMix64(seed: seed)
        func random() -> Float { Float(generator.next() % 10_000) / 10_000 }

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var trunk: [UInt32] = []
        var leaf: [UInt32] = []
        var snow: [UInt32] = []
        var bulbs: [[UInt32]] = [[], [], [], []]

        func add(_ p: SCNVector3, _ n: SCNVector3) -> UInt32 {
            vertices.append(p)
            normals.append(n)
            return UInt32(vertices.count - 1)
        }
        func normalized(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 {
            let length = max((x * x + y * y + z * z).squareRoot(), 1e-6)
            return SCNVector3(x / length, y / length, z / length)
        }

        // 幹（8 角形の、先が細い柱）
        let sides = 8
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi
            let a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let n0 = normalized(cos(a0), 0.1, sin(a0))
            let n1 = normalized(cos(a1), 0.1, sin(a1))
            let b0 = add(SCNVector3(cos(a0) * 0.42, 0, sin(a0) * 0.42), n0)
            let b1 = add(SCNVector3(cos(a1) * 0.42, 0, sin(a1) * 0.42), n1)
            let t0 = add(SCNVector3(cos(a0) * 0.22, 2.6, sin(a0) * 0.22), n0)
            let t1 = add(SCNVector3(cos(a1) * 0.22, 2.6, sin(a1) * 0.22), n1)
            trunk += [b0, t1, b1, b0, t0, t1]
        }

        // 葉の段（下の段ほど大きい）
        let tierCount = 9
        let segments = 18
        for k in 0..<tierCount {
            let t = Float(k) / Float(tierCount - 1)
            let baseY = 1.5 + 5.4 * t
            let height = 3.1 - 2.1 * t
            let radius = 2.7 * (1 - 0.88 * t) + 0.2 + random() * 0.15
            let midY = baseY + height * 0.45
            let apexY = baseY + height
            var jitter: [Float] = (0..<segments).map { _ in 0.84 + random() * 0.30 }
            jitter.append(jitter[0])
            let apex = SCNVector3(0, apexY, 0)

            for i in 0..<segments {
                let a0 = Float(i) / Float(segments) * 2 * .pi
                let a1 = Float(i + 1) / Float(segments) * 2 * .pi
                let r0 = radius * jitter[i]
                let r1 = radius * jitter[i + 1]
                // 枝先が、1 つおきに少したれる
                let droop0: Float = i % 2 == 0 ? -0.16 * height : 0
                let droop1: Float = (i + 1) % 2 == 0 ? -0.16 * height : 0
                let n0 = normalized(cos(a0) * height, radius, sin(a0) * height)
                let n1 = normalized(cos(a1) * height, radius, sin(a1) * height)

                let p0 = add(SCNVector3(cos(a0) * r0, baseY + droop0, sin(a0) * r0), n0)
                let p1 = add(SCNVector3(cos(a1) * r1, baseY + droop1, sin(a1) * r1), n1)
                let m0 = add(SCNVector3(cos(a0) * r0 * 0.55, midY, sin(a0) * r0 * 0.55), n0)
                let m1 = add(SCNVector3(cos(a1) * r1 * 0.55, midY, sin(a1) * r1 * 0.55), n1)
                leaf += [p0, m1, p1, p0, m0, m1]

                // 上の部分は雪
                let s0 = add(SCNVector3(cos(a0) * r0 * 0.55, midY, sin(a0) * r0 * 0.55), normalized(n0.x, n0.y + 0.6, n0.z))
                let s1 = add(SCNVector3(cos(a1) * r1 * 0.55, midY, sin(a1) * r1 * 0.55), normalized(n1.x, n1.y + 0.6, n1.z))
                let top = add(apex, SCNVector3(0, 1, 0))
                snow += [s0, top, s1]

                // 下から見えるふた
                let c = add(SCNVector3(0, baseY, 0), SCNVector3(0, -1, 0))
                let q0 = add(SCNVector3(cos(a0) * r0, baseY + droop0, sin(a0) * r0), SCNVector3(0, -1, 0))
                let q1 = add(SCNVector3(cos(a1) * r1, baseY + droop1, sin(a1) * r1), SCNVector3(0, -1, 0))
                leaf += [c, q0, q1]
            }
        }

        // イルミネーション: 木にらせん状に巻いた電球と、道のふちに並ぶ足元の電球
        func addBulb(_ center: SCNVector3, size: Float, color: Int) {
            let corners: [SCNVector3] = [
                SCNVector3(center.x + size, center.y, center.z), SCNVector3(center.x - size, center.y, center.z),
                SCNVector3(center.x, center.y + size, center.z), SCNVector3(center.x, center.y - size, center.z),
                SCNVector3(center.x, center.y, center.z + size), SCNVector3(center.x, center.y, center.z - size),
            ]
            let ids = corners.map { add($0, normalized($0.x - center.x, $0.y - center.y, $0.z - center.z)) }
            // +x -x +y -y +z -z
            let faces: [[Int]] = [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [4, 3, 0], [1, 3, 4], [5, 3, 1], [0, 3, 5]]
            for face in faces {
                bulbs[color % 4] += [ids[face[0]], ids[face[1]], ids[face[2]]]
            }
        }
        for j in 0..<16 {
            let t = Float(j) / 15
            let y = 1.9 + 5.4 * t
            let coneRadius = (2.7 * (1 - 0.88 * ((y - 1.5) / 5.4)) + 0.2) * 0.78
            let angle = Float(j) * 2.3
            addBulb(SCNVector3(cos(angle) * coneRadius, y, sin(angle) * coneRadius), size: 0.13, color: j)
        }
        let groundZs: [Float] = [-3.4, 0, 3.4]
        for (index, z) in groundZs.enumerated() {
            addBulb(SCNVector3(-1.6, 0.22, z), size: 0.14, color: index)
            addBulb(SCNVector3(1.6, 0.22, z), size: 0.14, color: index + 2)
        }

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
            elements: ([trunk, leaf, snow] + bulbs).map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        )
        geometry.materials = [trunkMaterial, leafMaterial, snowCapMaterial] + bulbMaterials
        return geometry
    }

    private func makeLane(variants: [SCNGeometry]) -> LaneLayer {
        let root = SCNNode()
        var holders: [SCNNode] = []
        for index in 0..<(Self.pairsPerLane * 2) {
            let holder = SCNNode()
            let tree = SCNNode(geometry: variants[index % variants.count])
            tree.eulerAngles = SCNVector3(0, Float(index) * 0.9, 0)
            holder.addChildNode(tree)
            root.addChildNode(holder)
            holders.append(holder)
        }
        root.isHidden = true
        return LaneLayer(root: root, holders: holders)
    }

    /// 雪玉の大きさに合わせて、見せる道を決める。
    /// - 雪玉が幅いっぱいになるまで: その道の木が立っている
    /// - 幅を超えたところ: その道の木が倒れていく
    private func updateLanes(radius r: Double) {
        var upright = 0
        while upright < 40 && r > Lane.width(stage: upright) / 2 * 1.0001 { upright += 1 }

        var fallingStage: Int?
        var fall = 0.0
        if upright >= 1 {
            let previous = upright - 1
            let half = Lane.width(stage: previous) / 2
            let p = (r - half) / (0.15 * half)
            if p < 1 {
                fallingStage = previous
                fall = max(0, p)
            }
        }
        configure(layers[0], stage: fallingStage, fall: fall)
        configure(layers[1], stage: upright, fall: 0)
        configure(layers[2], stage: upright + 1, fall: 0)
    }

    private func configure(_ layer: LaneLayer, stage: Int?, fall: Double) {
        guard let stage else {
            layer.root.isHidden = true
            return
        }
        layer.root.isHidden = false
        let f = Lane.treeScale(stage: stage)
        let half = Lane.width(stage: stage) / 2
        let spacing = 7 * f
        let period = spacing * Double(Self.pairsPerLane)
        let near = 4 * spacing
        let fallAngle = Float(fall * .pi / 2)
        let fs = Float(f)
        for index in 0..<(Self.pairsPerLane * 2) {
            let side: Double = index % 2 == 0 ? 1 : -1
            let pair = Double(index / 2)
            var z = (pair * spacing + scroll).truncatingRemainder(dividingBy: period)
            if z < 0 { z += period }
            z = z - period + near

            let holder = layer.holders[index]
            holder.position = SCNVector3(Float(side * (half + 1.5 * f)), 0, Float(z))
            holder.scale = SCNVector3(fs, fs, fs)
            holder.eulerAngles = SCNVector3(0, 0, Float(-side) * fallAngle)
            holder.isHidden = fall >= 1
        }
    }

    // MARK: 仲間

    private func updateCrew(_ look: CrewLook, radius r: Double, angle: Double) {
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
        let spacing: Double
        if count > 1 {
            let natural = 0.85 * nominal
            let limit = 1.7 * r / Double(count - 1) / (size / nominal)
            spacing = min(natural, limit)
        } else {
            spacing = 0
        }
        // 歩いているように、ぴょこぴょこ弾む（仲間だけ。機械は小さく揺れる）
        let bounce = tierIndex <= 1 ? 0.05 : 0.008
        for (index, node) in crew.childNodes.enumerated() {
            let x = (Double(index) - Double(count - 1) / 2) * spacing
            let y = abs(sin(angle * 4 + Double(index) * 1.3)) * bounce
            node.position = SCNVector3(Float(x), Float(y), 0)
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
        func sphere(_ r: CGFloat, _ color: UIColor, _ position: SCNVector3, squash: Float = 1) -> SCNNode {
            let node = SCNNode(geometry: SCNSphere(radius: r))
            node.geometry?.materials = [material(color)]
            node.position = position
            node.scale = SCNVector3(1, squash, 1)
            return node
        }
        func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ color: UIColor, _ position: SCNVector3) -> SCNNode {
            let node = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0.02))
            node.geometry?.materials = [material(color)]
            node.position = position
            return node
        }
        func glowing(_ r: CGFloat, _ color: UIColor, _ position: SCNVector3) -> SCNNode {
            let node = SCNNode(geometry: SCNSphere(radius: r))
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = color
            m.emission.contents = color
            node.geometry?.materials = [m]
            node.position = position
            return node
        }

        let root = SCNNode()
        switch tier {
        case 0, 1:
            let white = UIColor(white: 0.98, alpha: 1)
            let dark = UIColor(white: 0.12, alpha: 1)
            let main = tier == 0 ? UIColor(red: 0.95, green: 0.36, blue: 0.38, alpha: 1) : UIColor(red: 0.25, green: 0.50, blue: 0.95, alpha: 1)

            // からだとあたま
            root.addChildNode(sphere(0.30, white, SCNVector3(0, 0.30, 0)))
            root.addChildNode(sphere(0.215, white, SCNVector3(0, 0.74, 0)))
            // 足
            root.addChildNode(sphere(0.07, dark, SCNVector3(-0.12, 0.04, 0.05), squash: 0.6))
            root.addChildNode(sphere(0.07, dark, SCNVector3(0.12, 0.04, 0.05), squash: 0.6))
            // マフラー
            let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.17, pipeRadius: 0.05))
            scarf.geometry?.materials = [material(main)]
            scarf.position = SCNVector3(0, 0.56, 0)
            root.addChildNode(scarf)
            let tail = SCNNode(geometry: SCNBox(width: 0.07, height: 0.2, length: 0.04, chamferRadius: 0.01))
            tail.geometry?.materials = [material(main)]
            tail.position = SCNVector3(0.12, 0.46, -0.14)
            root.addChildNode(tail)
            // 目・ほっぺ・口・にんじんの鼻
            root.addChildNode(sphere(0.03, dark, SCNVector3(-0.075, 0.78, -0.195)))
            root.addChildNode(sphere(0.03, dark, SCNVector3(0.075, 0.78, -0.195)))
            root.addChildNode(sphere(0.035, UIColor(red: 1.0, green: 0.62, blue: 0.66, alpha: 1), SCNVector3(-0.13, 0.72, -0.16), squash: 0.7))
            root.addChildNode(sphere(0.035, UIColor(red: 1.0, green: 0.62, blue: 0.66, alpha: 1), SCNVector3(0.13, 0.72, -0.16), squash: 0.7))
            for dx in [-0.05, 0.0, 0.05] as [Float] {
                root.addChildNode(sphere(0.016, dark, SCNVector3(dx, 0.66 - abs(dx) * 0.3, -0.205)))
            }
            let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.032, height: 0.13))
            nose.geometry?.materials = [material(UIColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1))]
            nose.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            nose.position = SCNVector3(0, 0.73, -0.26)
            root.addChildNode(nose)
            // 雪玉を押す、枝の腕（先が三つ又に分かれている）
            let bark = material(UIColor(red: 0.36, green: 0.25, blue: 0.16, alpha: 1))
            for side: Float in [-1, 1] {
                let arm = SCNNode(geometry: SCNCylinder(radius: 0.017, height: 0.38))
                arm.geometry?.materials = [bark]
                arm.eulerAngles = SCNVector3(Float.pi / 2 * 0.92, 0, side * 0.10)
                arm.position = SCNVector3(side * 0.27, 0.50, -0.17)
                root.addChildNode(arm)
                for spread: Float in [-0.55, 0, 0.55] {
                    let twig = SCNNode(geometry: SCNCylinder(radius: 0.011, height: 0.11))
                    twig.geometry?.materials = [bark]
                    twig.eulerAngles = SCNVector3(Float.pi / 2 * 0.92, 0, spread)
                    twig.position = SCNVector3(side * 0.28 + spread * 0.05, 0.51, -0.40)
                    root.addChildNode(twig)
                }
            }
            // 帽子
            if tier == 0 {
                // ニット帽（ぽんぽん付き）
                root.addChildNode(sphere(0.19, main, SCNVector3(0, 0.89, 0.0), squash: 0.62))
                root.addChildNode(sphere(0.055, UIColor.white, SCNVector3(0, 1.02, 0.0)))
            } else {
                // シルクハット
                let brim = SCNNode(geometry: SCNCylinder(radius: 0.20, height: 0.03))
                brim.geometry?.materials = [material(dark)]
                brim.position = SCNVector3(0, 0.93, 0)
                root.addChildNode(brim)
                let crown = SCNNode(geometry: SCNCylinder(radius: 0.13, height: 0.2))
                crown.geometry?.materials = [material(dark)]
                crown.position = SCNVector3(0, 1.04, 0)
                root.addChildNode(crown)
                let band = SCNNode(geometry: SCNCylinder(radius: 0.133, height: 0.04))
                band.geometry?.materials = [material(main)]
                band.position = SCNVector3(0, 0.98, 0)
                root.addChildNode(band)
            }
        case 2:
            // そりいた: 板を 2 枚と、押すための持ち手
            let wood = UIColor(red: 0.72, green: 0.52, blue: 0.34, alpha: 1)
            let darkWood = UIColor(red: 0.50, green: 0.34, blue: 0.22, alpha: 1)
            root.addChildNode(box(1.0, 0.66, 0.08, wood, SCNVector3(0, 0.36, 0)))
            root.addChildNode(box(1.0, 0.07, 0.34, darkWood, SCNVector3(0, 0.05, 0.12)))
            root.addChildNode(box(0.06, 0.55, 0.06, darkWood, SCNVector3(-0.4, 0.45, 0.12)))
            root.addChildNode(box(0.06, 0.55, 0.06, darkWood, SCNVector3(0.4, 0.45, 0.12)))
            root.addChildNode(box(0.9, 0.05, 0.05, darkWood, SCNVector3(0, 0.75, 0.12)))
        case 3:
            // でんどうクローラー
            let body = UIColor(red: 0.42, green: 0.52, blue: 0.68, alpha: 1)
            root.addChildNode(box(0.9, 0.42, 1.2, body, SCNVector3(0, 0.52, 0.1)))
            root.addChildNode(box(0.5, 0.3, 0.5, UIColor(red: 0.55, green: 0.70, blue: 0.90, alpha: 1), SCNVector3(0, 0.88, 0.3)))
            root.addChildNode(box(0.22, 0.34, 1.5, UIColor(white: 0.18, alpha: 1), SCNVector3(-0.5, 0.17, 0.1)))
            root.addChildNode(box(0.22, 0.34, 1.5, UIColor(white: 0.18, alpha: 1), SCNVector3(0.5, 0.17, 0.1)))
            root.addChildNode(box(1.1, 0.48, 0.07, UIColor(red: 1.0, green: 0.82, blue: 0.25, alpha: 1), SCNVector3(0, 0.42, -0.64)))
            root.addChildNode(glowing(0.07, UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1), SCNVector3(-0.3, 0.6, -0.52)))
            root.addChildNode(glowing(0.07, UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1), SCNVector3(0.3, 0.6, -0.52)))
        default:
            // おおがたクローラー
            let body = UIColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1)
            root.addChildNode(box(0.9, 0.46, 1.2, body, SCNVector3(0, 0.54, 0.1)))
            root.addChildNode(box(0.55, 0.38, 0.55, UIColor(red: 0.55, green: 0.72, blue: 0.92, alpha: 1), SCNVector3(0, 0.96, 0.3)))
            root.addChildNode(box(0.26, 0.38, 1.6, UIColor(white: 0.16, alpha: 1), SCNVector3(-0.52, 0.19, 0.1)))
            root.addChildNode(box(0.26, 0.38, 1.6, UIColor(white: 0.16, alpha: 1), SCNVector3(0.52, 0.19, 0.1)))
            root.addChildNode(box(1.25, 0.6, 0.08, UIColor(white: 0.86, alpha: 1), SCNVector3(0, 0.46, -0.68)))
            root.addChildNode(glowing(0.08, UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1), SCNVector3(-0.35, 0.72, -0.5)))
            root.addChildNode(glowing(0.08, UIColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1), SCNVector3(0.35, 0.72, -0.5)))
            root.addChildNode(glowing(0.06, UIColor(red: 1.0, green: 0.4, blue: 0.3, alpha: 1), SCNVector3(0, 1.2, 0.3)))
        }
        return root
    }

    // MARK: 時間帯・ブラックホール・ぎゅっ

    private func applyDaypart(_ daypart: Daypart) {
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        var bulbGlow: CGFloat = 0
        switch daypart {
        case .day:
            ambient.light?.color = color(0.60, 0.66, 0.78)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.96, 0.88)
            sun.light?.intensity = 800
            camera.wantsHDR = false
            camera.bloomIntensity = 0
        case .dusk:
            ambient.light?.color = color(0.55, 0.48, 0.62)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.70, 0.50)
            sun.light?.intensity = 750
            bulbGlow = 0.8
            camera.wantsHDR = false
            camera.bloomIntensity = 0
        case .night:
            // 雪玉が見えるくらいには明るく。電球だけがにじんで光る。
            ambient.light?.color = color(0.50, 0.56, 0.78)
            ambient.light?.intensity = 1000
            sun.light?.color = color(0.62, 0.70, 1.0)
            sun.light?.intensity = 500
            bulbGlow = 2.4
            camera.wantsHDR = true
            camera.bloomThreshold = 0.85
            camera.bloomBlurRadius = 14
            camera.bloomIntensity = 1.1
        }
        for material in bulbMaterials {
            material.emission.intensity = bulbGlow
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
