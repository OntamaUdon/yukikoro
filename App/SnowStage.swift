import SwiftUI
import SceneKit
import UIKit
import simd

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

/// 頂点を直接組み立てるための道具。三角形の向きは、法線のヒントに合わせて自動で直す。
struct MeshBuilder {
    typealias Vertex = (p: SIMD3<Float>, n: SIMD3<Float>)

    var positions: [SCNVector3] = []
    var normals: [SCNVector3] = []
    var elements: [[UInt32]]

    init(elementCount: Int) {
        elements = Array(repeating: [], count: elementCount)
    }

    mutating func triangle(_ element: Int, _ v0: Vertex, _ v1: Vertex, _ v2: Vertex) {
        var b = v1
        var c = v2
        let geometric = simd_cross(v1.p - v0.p, v2.p - v0.p)
        let hint = v0.n + v1.n + v2.n
        if simd_dot(geometric, hint) < 0 {
            b = v2
            c = v1
        }
        let base = UInt32(positions.count)
        for v in [v0, b, c] {
            positions.append(SCNVector3(v.p.x, v.p.y, v.p.z))
            normals.append(SCNVector3(v.n.x, v.n.y, v.n.z))
        }
        elements[element] += [base, base + 1, base + 2]
    }

    mutating func quad(_ element: Int, _ a: Vertex, _ b: Vertex, _ c: Vertex, _ d: Vertex) {
        triangle(element, a, b, c)
        triangle(element, a, c, d)
    }

    /// 小さな電球（八面体）
    mutating func bulb(_ element: Int, center: SIMD3<Float>, size s: Float) {
        let px = center + SIMD3(s, 0, 0), nx = center - SIMD3(s, 0, 0)
        let py = center + SIMD3(0, s, 0), ny = center - SIMD3(0, s, 0)
        let pz = center + SIMD3(0, 0, s), nz = center - SIMD3(0, 0, s)
        func v(_ p: SIMD3<Float>) -> Vertex { (p, simd_normalize(p - center)) }
        let faces: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = [
            (px, py, pz), (pz, py, nx), (nx, py, nz), (nz, py, px),
            (pz, ny, px), (nx, ny, pz), (nz, ny, nx), (px, ny, nz),
        ]
        for f in faces { triangle(element, v(f.0), v(f.1), v(f.2)) }
    }

    func geometry(materials: [SCNMaterial]) -> SCNGeometry {
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
            elements: elements.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) }
        )
        geometry.materials = materials
        return geometry
    }
}

final class StageCoordinator {
    let scene = SCNScene()

    private let camera = SCNCamera()
    private let ball = SCNNode()
    private let ballMaterial = SCNMaterial()
    private let groundMaterial = SCNMaterial()
    private let ring = SCNNode()
    private let shadow = SCNNode()
    private let world = SCNNode()
    private let ground = SCNNode()
    private let crew = SCNNode()
    private let orbit = SCNNode()
    private let ambient = SCNNode()
    private let sun = SCNNode()
    private let sparkles = SCNNode()
    private let sparkleSystem = SCNParticleSystem()
    /// 雪玉・仲間・足元をあたたかく照らす、街灯のような光
    private let lampLight = SCNNode()
    /// 道ばたに落ちている物（小石・枝・まつぼっくり）。雪玉に拾われて消える。
    private let debrisRoot = SCNNode()
    private var debrisItems: [SCNNode] = []
    private var debrisLateral: [Double] = []
    /// 雪玉の半径を 1 としたときの、転がった道のり
    private var scrollUnits: Double = 0
    /// 木いがいの、道に立つ物の形（種類ごと）
    private var objectGeometries: [LaneKind: [SCNGeometry]] = [:]
    private let windowMaterial = SCNMaterial()
    private var treeVariants: [SCNGeometry] = []

    // 木の道に使う材料
    private let trunkMaterial = SCNMaterial()
    private let needleMaterial = SCNMaterial()
    private let snowMaterial = SCNMaterial()
    /// イルミネーションの電球（あたたかい金色と、氷のような白青）
    private let goldBulb = SCNMaterial()
    private let iceBulb = SCNMaterial()
    /// 足元に映る光だまり
    private let poolMaterial = SCNMaterial()

    /// 木の道 1 本ぶん（左右 2 列、等間隔）
    private struct LaneLayer {
        let root: SCNNode
        let holders: [SCNNode]
        /// 道をまたぐ光のアーチ
        let arches: [SCNNode]
        let pool: SCNNode
        var archStage: Int?
    }
    private var layers: [LaneLayer] = []

    private var lastAngle: Double?
    /// 転がった道のり（メートル）
    private var scroll: Double = 0
    private var lastCrew: CrewLook?
    private var lastDaypart: Daypart?
    private var lastSquish = 0
    private var lastBlackHole = false

    private static let pairsPerLane = 10
    private static let debrisCount = 16
    private static let debrisGap = 2.3
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

        lampLight.light = SCNLight()
        lampLight.light?.type = .omni
        lampLight.light?.color = UIColor(red: 1.0, green: 0.80, blue: 0.52, alpha: 1)
        lampLight.light?.intensity = 0
        lampLight.light?.attenuationStartDistance = 4
        lampLight.light?.attenuationEndDistance = 22
        lampLight.light?.attenuationFalloffExponent = 1.5
        lampLight.position = SCNVector3(0, 3.6, 2.2)
        scene.rootNode.addChildNode(lampLight)

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
        treeVariants = (0..<3).map { index -> SCNGeometry in
            let seed = UInt64(index + 1) * 7_919
            let full = makeTreeGeometry(seed: seed)
            // 画面で小さくなったら、枝の少ない簡単な形にかえる
            full.levelsOfDetail = [SCNLevelOfDetail(geometry: makeTreeGeometry(seed: seed, detailed: false), screenSpaceRadius: 90)]
            return full
        }
        for _ in 0..<3 {
            let layer = makeLane(variants: treeVariants)
            world.addChildNode(layer.root)
            layers.append(layer)
        }
        world.addChildNode(crew)
        setUpDebris()

        // 重力そうちの玉（雪玉のまわりを回る）
        scene.rootNode.addChildNode(orbit)

        setUpSparkles()
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
            scrollUnits += input.angle - last
        }
        lastAngle = input.angle

        ball.eulerAngles = SCNVector3(Float(-input.angle.truncatingRemainder(dividingBy: 2 * .pi)), 0, 0)
        world.scale = SCNVector3(s, s, s)

        // 地面が大きくなりすぎた雪玉のまわりでも途切れないように広げる
        let groundScale = Float(max(1.0, r / 4))
        ground.scale = SCNVector3(groundScale, groundScale, 1)
        let tile = Self.groundTile * Double(groundScale)
        ground.position = SCNVector3(0, 0, Float(scroll.truncatingRemainder(dividingBy: tile)))

        updateLanes(radius: r)
        updateDebris(radius: r)
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
        trunkMaterial.diffuse.contents = UIColor(red: 0.27, green: 0.19, blue: 0.14, alpha: 1)
        needleMaterial.lightingModel = .lambert
        needleMaterial.diffuse.contents = UIColor(red: 0.09, green: 0.24, blue: 0.19, alpha: 1)
        needleMaterial.isDoubleSided = true
        snowMaterial.lightingModel = .lambert
        snowMaterial.diffuse.contents = UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1)
        snowMaterial.isDoubleSided = true

        for (material, color) in [
            (goldBulb, UIColor(red: 1.0, green: 0.80, blue: 0.42, alpha: 1)),
            (iceBulb, UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1)),
        ] {
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.emission.contents = color
            material.emission.intensity = 0
        }

        windowMaterial.lightingModel = .lambert
        windowMaterial.diffuse.contents = UIColor(red: 0.13, green: 0.17, blue: 0.27, alpha: 1)
        windowMaterial.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.42, alpha: 1)
        windowMaterial.emission.intensity = 0

        poolMaterial.lightingModel = .constant
        poolMaterial.diffuse.contents = Self.poolImage(size: 256)
        poolMaterial.diffuse.wrapS = .repeat
        poolMaterial.diffuse.wrapT = .repeat
        poolMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(1, Float(Self.pairsPerLane), 1)
        poolMaterial.blendMode = .add
        poolMaterial.writesToDepthBuffer = false
        poolMaterial.isDoubleSided = true
        poolMaterial.transparency = 0
    }

    private func bulbMaterials() -> [SCNMaterial] { [goldBulb, iceBulb] }

    /// 木いがいの、道に立つ物（種類ごとに形を用意しておく）
    private func geometries(for kind: LaneKind) -> [SCNGeometry] {
        if let cached = objectGeometries[kind] { return cached }
        func paint(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            return m
        }
        let walls: [SCNMaterial]
        let trim: SCNMaterial
        switch kind {
        case .tree: return []
        case .pole:
            walls = [paint(0.46, 0.38, 0.32), paint(0.40, 0.36, 0.34)]
            trim = paint(0.18, 0.17, 0.18)
        case .helicopter:
            walls = [paint(0.86, 0.20, 0.22), paint(0.22, 0.52, 0.80), paint(0.92, 0.72, 0.22)]
            trim = paint(0.12, 0.12, 0.14)
        case .house:
            walls = [paint(0.93, 0.86, 0.72), paint(0.62, 0.74, 0.88), paint(0.72, 0.40, 0.32)]
            trim = paint(0.34, 0.22, 0.22)
        case .building:
            walls = [paint(0.56, 0.59, 0.66), paint(0.42, 0.49, 0.62)]
            trim = paint(0.24, 0.26, 0.30)
        case .mountain, .range:
            walls = [paint(0.40, 0.45, 0.58), paint(0.46, 0.46, 0.56)]
            trim = paint(0.34, 0.38, 0.50)
        }
        let list = walls.enumerated().map { index, wall in
            StageObjects.geometry(kind: kind, seed: UInt64(index + 1) * 4_217, materials: [wall, trim, snowMaterial, goldBulb, iceBulb, windowMaterial])
        }
        objectGeometries[kind] = list
        return list
    }

    /// 針葉樹（トウヒ）の形。高さは約 8。
    /// 幹は先が細くなる円錐。そこに、下ほど長い枝の輪が 16 段つく。枝は少しもち上がってから、先がたれて、上に雪がのる。
    /// 枝にそって小さな電球を並べ、木から木へわたす光の列と、てっぺんの星もつける。
    private func makeTreeGeometry(seed: UInt64, detailed: Bool = true) -> SCNGeometry {
        var generator = SplitMix64(seed: seed)
        func random() -> Float { Float(generator.next() % 10_000) / 10_000 }

        // 面: 0 幹, 1 葉, 2 雪, 3 金の電球, 4 氷の電球
        var mesh = MeshBuilder(elementCount: 5)
        let up = SIMD3<Float>(0, 1, 0)
        func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>) -> MeshBuilder.Vertex { (p, simd_normalize(n)) }

        // 幹
        let ringY: [Float] = [0, 2.5, 5.5, 8.2]
        let ringR: [Float] = [0.36, 0.25, 0.13, 0.03]
        let sides = 8
        for j in 0..<(ringY.count - 1) {
            for i in 0..<sides {
                let a0 = Float(i) / Float(sides) * 2 * .pi
                let a1 = Float(i + 1) / Float(sides) * 2 * .pi
                let d0 = SIMD3<Float>(cos(a0), 0, sin(a0))
                let d1 = SIMD3<Float>(cos(a1), 0, sin(a1))
                mesh.quad(0,
                          vertex(d0 * ringR[j] + SIMD3(0, ringY[j], 0), d0),
                          vertex(d1 * ringR[j] + SIMD3(0, ringY[j], 0), d1),
                          vertex(d1 * ringR[j + 1] + SIMD3(0, ringY[j + 1], 0), d1),
                          vertex(d0 * ringR[j + 1] + SIMD3(0, ringY[j + 1], 0), d0))
            }
        }

        // 枝（1 本の枝と、そこから出る小枝を、同じ作り方でつくる）
        func frond(origin: SIMD3<Float>, radial: SIMD3<Float>, side: SIMD3<Float>, length len: Float, droop: Float,
                   widthFactor: Float, segments: Int, snowy: Bool, bulbAt: [Int]) {
            var left: [SIMD3<Float>] = []
            var right: [SIMD3<Float>] = []
            var ridge: [SIMD3<Float>] = []
            for i in 0...segments {
                let t = Float(i) / Float(segments)
                let dy = len * (0.14 * t - 0.42 * t * t) * droop
                let spine = origin + radial * (len * t) + SIMD3(0, dy, 0)
                let width = widthFactor * len * pow(max(0, sin(Float.pi * pow(t, 0.75))), 0.85)
                left.append(spine - side * width)
                right.append(spine + side * width)
                ridge.append(spine + up * (0.22 * width + 0.025))
            }
            let nUp = simd_normalize(up + radial * 0.3)
            let nLeft = simd_normalize(up * 0.9 - side * 0.6 + radial * 0.2)
            let nRight = simd_normalize(up * 0.9 + side * 0.6 + radial * 0.2)
            for i in 0..<segments {
                mesh.quad(1, vertex(left[i], nLeft), vertex(ridge[i], nUp), vertex(ridge[i + 1], nUp), vertex(left[i + 1], nLeft))
                mesh.quad(1, vertex(ridge[i], nUp), vertex(right[i], nRight), vertex(right[i + 1], nRight), vertex(ridge[i + 1], nUp))
                mesh.quad(1, vertex(left[i], -up), vertex(left[i + 1], -up), vertex(right[i + 1], -up), vertex(right[i], -up))
                if snowy && i >= 1 && i <= segments - 2 && random() < 0.9 {
                    func snow(_ index: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
                        (ridge[index] + (left[index] - ridge[index]) * 0.55 + up * 0.025,
                         ridge[index] + up * 0.04,
                         ridge[index] + (right[index] - ridge[index]) * 0.55 + up * 0.025)
                    }
                    let a = snow(i), c = snow(i + 1)
                    mesh.quad(2, vertex(a.0, up), vertex(a.1, up), vertex(c.1, up), vertex(c.0, up))
                    mesh.quad(2, vertex(a.1, up), vertex(a.2, up), vertex(c.2, up), vertex(c.1, up))
                }
            }
            for i in bulbAt where i <= segments {
                mesh.bulb(random() < 0.12 ? 4 : 3, center: ridge[i] + up * 0.05, size: 0.034)
            }
        }

        let whorls = detailed ? 16 : 9
        for k in 0..<whorls {
            let h = Float(k) / Float(whorls - 1)
            let y0 = 1.5 + 6.3 * pow(h, 0.95)
            let length = 1.9 * pow(1 - h, 0.9) + 0.15
            let branchCount = detailed ? (h < 0.35 ? 10 : (h < 0.7 ? 8 : 6)) : (h < 0.35 ? 6 : (h < 0.7 ? 5 : 4))
            let droop = 1 - 0.55 * h
            for b in 0..<branchCount {
                let theta = (Float(b) / Float(branchCount) + Float(k) * 0.37 + random() * 0.06) * 2 * .pi
                let radial = SIMD3<Float>(cos(theta), 0, sin(theta))
                let side = SIMD3<Float>(-sin(theta), 0, cos(theta))
                let len = length * (0.85 + random() * 0.3)
                let origin = SIMD3<Float>(0, y0, 0) + radial * 0.12
                frond(origin: origin, radial: radial, side: side, length: len, droop: droop,
                      widthFactor: detailed ? 0.27 : 0.34, segments: detailed ? 5 : 3, snowy: true, bulbAt: detailed ? [3, 5] : [3])

                // 小枝（枝の途中から、左右に出る）
                if detailed && len > 0.5 {
                    let t: Float = 0.5
                    let base = origin + radial * (len * t) + SIMD3(0, len * (0.14 * t - 0.42 * t * t) * droop, 0)
                    for sign: Float in [-1, 1] {
                        let direction = simd_normalize(radial * 0.8 + side * (0.6 * sign))
                        let twigSide = simd_normalize(SIMD3<Float>(-direction.z, 0, direction.x))
                        frond(origin: base, radial: direction, side: twigSide, length: len * 0.42, droop: droop,
                              widthFactor: 0.30, segments: 2, snowy: false, bulbAt: [2])
                    }
                }
            }
        }

        // てっぺんの星
        mesh.bulb(3, center: SIMD3(0, 8.35, 0), size: 0.16)
        // 木から木へわたす光の列（次の木までの 7）
        for j in 0...14 {
            let z = Float(j) / 14 * 7
            let y = 5.9 - 0.9 * sin(Float.pi * z / 7)
            mesh.bulb(j % 5 == 2 ? 4 : 3, center: SIMD3(0, y, z), size: 0.045)
        }

        return mesh.geometry(materials: [trunkMaterial, needleMaterial, snowMaterial, goldBulb, iceBulb])
    }

    /// 道をまたぐ、光のアーチ（メートルで作る）
    private func makeArchGeometry(half: Double, f: Double, kind: LaneKind) -> SCNGeometry? {
        guard let shape = StageObjects.arch(kind) else { return nil }
        var mesh = MeshBuilder(elementCount: 2)
        let reach = Float(half + StageObjects.offset(kind) * f)
        let height = Float(shape.height * f)
        let sag = Float(shape.sag * f)
        let count = 26
        for j in 0...count {
            let t = Float(j) / Float(count)
            let x = -reach + 2 * reach * t
            // 両はしでは高く、まん中ではたれる
            let drooped = height - sag * (1 - pow(abs(2 * t - 1), 2))
            mesh.bulb(j % 6 == 3 ? 1 : 0, center: SIMD3(x, drooped, 0), size: Float(0.05 * f))
        }
        return mesh.geometry(materials: [goldBulb, iceBulb])
    }

    private func makeLane(variants: [SCNGeometry]) -> LaneLayer {
        let root = SCNNode()
        var holders: [SCNNode] = []
        for index in 0..<(Self.pairsPerLane * 2) {
            let holder = SCNNode()
            holder.addChildNode(SCNNode(geometry: variants[index % variants.count]))
            root.addChildNode(holder)
            holders.append(holder)
        }
        var arches: [SCNNode] = []
        for _ in 0..<Self.pairsPerLane {
            let arch = SCNNode()
            root.addChildNode(arch)
            arches.append(arch)
        }
        // 足元の光だまり（道全体に 1 枚。木の位置に合わせて、くり返し模様をずらす）
        let poolPlane = SCNPlane(width: 7.6, height: 7 * Double(Self.pairsPerLane))
        poolPlane.materials = [poolMaterial]
        let pool = SCNNode(geometry: poolPlane)
        pool.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        root.addChildNode(pool)
        root.isHidden = true
        return LaneLayer(root: root, holders: holders, arches: arches, pool: pool, archStage: nil)
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
        configure(0, stage: fallingStage, fall: fall)
        configure(1, stage: upright, fall: 0)
        // 次の道は、まだ見せない（外側に大きな物が見えてしまうので）
        configure(2, stage: nil, fall: 0)
    }

    private func configure(_ slot: Int, stage: Int?, fall: Double) {
        guard let stage else {
            layers[slot].root.isHidden = true
            return
        }
        let layer = layers[slot]
        layer.root.isHidden = false
        let kind = Lane.kind(stage: stage)
        let f = Lane.treeScale(stage: stage)
        let half = Lane.width(stage: stage) / 2
        let objectOffset = StageObjects.offset(kind)

        // 立っている物と光のアーチは、道が変わったときだけ作り直す
        if layers[slot].archStage != stage {
            layers[slot].archStage = stage
            let variants = kind == .tree ? treeVariants : geometries(for: kind)
            for (index, holder) in layer.holders.enumerated() {
                holder.childNodes.first?.geometry = variants[index % variants.count]
            }
            let geometry = makeArchGeometry(half: half, f: f, kind: kind)
            for arch in layer.arches { arch.geometry = geometry }
        }
        let hasArch = StageObjects.arch(kind) != nil

        let spacing = 7 * f
        let period = spacing * Double(Self.pairsPerLane)
        let near = 0.5 * spacing
        let fallAngle = Float(fall * .pi / 2)
        let fs = Float(f)
        for index in 0..<(Self.pairsPerLane * 2) {
            let side: Double = index % 2 == 0 ? 1 : -1
            let pair = Double(index / 2)
            var z = (pair * spacing + scroll).truncatingRemainder(dividingBy: period)
            if z < 0 { z += period }
            z = z - period + near

            let holder = layer.holders[index]
            holder.position = SCNVector3(Float(side * (half + objectOffset * f)), 0, Float(z))
            holder.scale = SCNVector3(fs, fs, fs)
            holder.eulerAngles = SCNVector3(0, 0, Float(-side) * fallAngle)
            holder.isHidden = fall >= 1

            if index % 2 == 0 {
                let arch = layer.arches[index / 2]
                arch.position = SCNVector3(0, 0, Float(z))
                arch.isHidden = fall > 0 || !hasArch
            }
        }

        // 光だまり: 木の位置と、くり返し模様のずれを合わせる
        let offset = scroll.truncatingRemainder(dividingBy: spacing)
        layer.pool.position = SCNVector3(0, 0.02 * fs, Float(near - period / 2 + (offset < 0 ? offset + spacing : offset)))
        layer.pool.scale = SCNVector3(fs, fs, fs)
        layer.pool.isHidden = fall > 0 || kind == .mountain || kind == .range
    }

    // MARK: 道ばたの物（雪玉が拾って、資材になる）

    private func setUpDebris() {
        var generator = SplitMix64(seed: 77)
        func random() -> Float { Float(generator.next() % 10_000) / 10_000 }
        func paint(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = UIColor(red: r, green: g, blue: b, alpha: 1)
            return m
        }
        for index in 0..<Self.debrisCount {
            let item = SCNNode()
            switch index % 3 {
            case 0:
                // 小石
                let stone = SCNNode(geometry: SCNSphere(radius: 0.10))
                stone.geometry?.materials = [paint(0.52, 0.54, 0.60)]
                stone.scale = SCNVector3(1.1, 0.65, 0.9)
                stone.position = SCNVector3(0, 0.06, 0)
                item.addChildNode(stone)
            case 1:
                // 木の枝（ちょっと曲がった 2 本）
                for k in 0..<2 {
                    let twig = SCNNode(geometry: SCNCylinder(radius: 0.02, height: k == 0 ? 0.6 : 0.34))
                    twig.geometry?.materials = [paint(0.42, 0.29, 0.18)]
                    twig.eulerAngles = SCNVector3(0, Float(k) * 0.9, Float.pi / 2)
                    twig.position = SCNVector3(Float(k) * 0.08, 0.03 + Float(k) * 0.03, Float(k) * 0.06)
                    item.addChildNode(twig)
                }
            default:
                // まつぼっくり
                let cone = SCNNode(geometry: SCNCone(topRadius: 0.01, bottomRadius: 0.075, height: 0.2))
                cone.geometry?.materials = [paint(0.50, 0.33, 0.20)]
                cone.eulerAngles = SCNVector3(0, 0, Float.pi / 2.4)
                cone.position = SCNVector3(0, 0.07, 0)
                item.addChildNode(cone)
            }
            item.eulerAngles = SCNVector3(0, random() * 6.28, 0)
            debrisRoot.addChildNode(item)
            debrisItems.append(item)
            debrisLateral.append(Double(random() - 0.5) * 1.5)
        }
        debrisRoot.position = SCNVector3(0, -1, 0)
        scene.rootNode.addChildNode(debrisRoot)
    }

    /// 雪玉がまだ小さい間（最初の道のあいだ）、道ばたの物を転がして拾う
    private func updateDebris(radius r: Double) {
        let visible = r <= Lane.width(stage: 0) / 2
        debrisRoot.isHidden = !visible
        guard visible else { return }
        let period = Self.debrisGap * Double(Self.debrisCount)
        for (index, item) in debrisItems.enumerated() {
            var z = (Double(index) * Self.debrisGap + scrollUnits).truncatingRemainder(dividingBy: period)
            if z < 0 { z += period }
            z = z - period + 0.5
            // 雪玉に近づくと、ぐっと吸いこまれて小さくなる
            let t = min(max((z + 1.7) / 1.5, 0), 1)
            let x = debrisLateral[index] * (1 - 0.85 * t)
            item.position = SCNVector3(Float(x), Float(0.9 * t * t), Float(z))
            let scale = Float(1.7 * (1 - 0.85 * t))
            item.scale = SCNVector3(scale, scale, scale)
            item.isHidden = t >= 1
        }
    }

    // MARK: 光の粒（夜に、金色の粒がゆっくり漂う）

    private func setUpSparkles() {
        sparkleSystem.birthRate = 0
        sparkleSystem.particleLifeSpan = 7
        sparkleSystem.particleLifeSpanVariation = 3
        sparkleSystem.particleSize = 0.07
        sparkleSystem.particleSizeVariation = 0.05
        sparkleSystem.particleColor = UIColor(red: 1.0, green: 0.84, blue: 0.5, alpha: 1)
        sparkleSystem.particleImage = Self.glowDot(size: 64)
        sparkleSystem.blendMode = .additive
        sparkleSystem.isAffectedByGravity = false
        sparkleSystem.particleVelocity = 0.12
        sparkleSystem.particleVelocityVariation = 0.1
        sparkleSystem.emittingDirection = SCNVector3(0, 1, 0)
        sparkleSystem.spreadingAngle = 40
        sparkleSystem.emitterShape = SCNBox(width: 9, height: 2.5, length: 14, chamferRadius: 0)
        sparkleSystem.particleColorVariation = SCNVector4(0.05, 0.1, 0.1, 0)
        sparkleSystem.isLocal = true
        sparkles.position = SCNVector3(0, 1.6, -5)
        sparkles.addParticleSystem(sparkleSystem)
        scene.rootNode.addChildNode(sparkles)
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
        let factor = size / nominal
        crew.scale = SCNVector3(Float(factor), Float(factor), Float(factor))
        crew.position = SCNVector3(0, 0, 0)

        // 手が雪玉にふれる高さでの、雪玉の中心からの距離。そこから、うでの長さぶんだけ離れて立つ。
        let handHeight = min(0.75 * size, 1.8 * r)
        let surface = max(0, r * r - (r - handHeight) * (r - handHeight)).squareRoot()
        let distance = surface + 0.45 * size

        // 雪玉の後ろがわの円弧に、はば 1 人ぶんずつ並べる（入りきらない分は見せない）
        let arc = distance * 2.1
        let fit = max(1, Int(arc / (1.05 * size)))
        let shown = max(1, min(min(look.count, 8), fit))
        let step = shown > 1 ? min(1.05 * size / distance, 2.1 / Double(shown - 1)) : 0

        // 歩いているように、ぴょこぴょこ弾む（仲間だけ。機械は小さく揺れる）
        let bounce = tierIndex <= 1 ? 0.05 : 0.008
        for (index, node) in crew.childNodes.enumerated() {
            node.isHidden = index >= shown
            let phi = (Double(index) - Double(shown - 1) / 2) * step
            let y = abs(sin(angle * 4 + Double(index) * 1.3)) * bounce
            node.position = SCNVector3(
                Float(distance * sin(phi) / factor),
                Float(y),
                Float(distance * cos(phi) / factor)
            )
            node.eulerAngles = SCNVector3(0, Float(phi), 0)
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
        // じゅうりょくそうち: 雪玉のまわりに浮かぶ装置。光る核と回る輪から、雪玉へ向けて光の筋がのびる。
        let pods = min(look.gravity, 6)
        for i in 0..<pods {
            let a = Double(i) / Double(max(pods, 1)) * 2 * .pi
            let pivot = SCNNode()
            pivot.eulerAngles = SCNVector3(0, Float(-a), 0)
            let pod = Self.makeGravityPod()
            pod.position = SCNVector3(1.78, 0, 0)
            pivot.addChildNode(pod)
            // 雪玉へのびる光の筋
            let beamMaterial = SCNMaterial()
            beamMaterial.lightingModel = .constant
            beamMaterial.diffuse.contents = UIColor(red: 0.62, green: 0.55, blue: 1.0, alpha: 1)
            beamMaterial.emission.contents = UIColor(red: 0.55, green: 0.45, blue: 1.0, alpha: 1)
            beamMaterial.blendMode = .add
            beamMaterial.writesToDepthBuffer = false
            beamMaterial.transparency = 0.5
            let beam = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.62))
            beam.geometry?.materials = [beamMaterial]
            beam.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            beam.position = SCNVector3(1.42, 0, 0)
            pivot.addChildNode(beam)
            orbit.addChildNode(pivot)
        }
    }

    /// 浮かぶ重力そうち 1 つぶん
    private static func makeGravityPod() -> SCNNode {
        func shiny(_ color: UIColor, emission: UIColor? = nil, additive: Bool = false, alpha: CGFloat = 1) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = emission == nil ? .blinn : .constant
            m.diffuse.contents = color
            if let emission { m.emission.contents = emission }
            if additive {
                m.blendMode = .add
                m.writesToDepthBuffer = false
                m.transparency = alpha
            }
            return m
        }
        let root = SCNNode()
        let dark = UIColor(red: 0.22, green: 0.24, blue: 0.34, alpha: 1)
        let violet = UIColor(red: 0.66, green: 0.48, blue: 1.0, alpha: 1)
        let cyan = UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 1)

        // 台座（下に向かって細くなる脚）
        let leg = SCNNode(geometry: SCNCone(topRadius: 0.13, bottomRadius: 0.03, height: 0.26))
        leg.geometry?.materials = [shiny(dark)]
        leg.position = SCNVector3(0, -0.25, 0)
        root.addChildNode(leg)
        let plate = SCNNode(geometry: SCNCylinder(radius: 0.17, height: 0.04))
        plate.geometry?.materials = [shiny(UIColor(red: 0.5, green: 0.52, blue: 0.62, alpha: 1))]
        plate.position = SCNVector3(0, -0.11, 0)
        root.addChildNode(plate)
        // 3 本のささえ
        for k in 0..<3 {
            let arm = SCNNode(geometry: SCNCylinder(radius: 0.012, height: 0.3))
            arm.geometry?.materials = [shiny(dark)]
            let angle = Float(k) / 3 * 2 * .pi
            arm.position = SCNVector3(cos(angle) * 0.12, 0.04, sin(angle) * 0.12)
            arm.eulerAngles = SCNVector3(sin(angle) * 0.35, 0, -cos(angle) * 0.35)
            root.addChildNode(arm)
        }
        // 光る核と、ぼんやりしたまわりの光
        let core = SCNNode(geometry: SCNSphere(radius: 0.10))
        core.geometry?.materials = [shiny(violet, emission: violet)]
        core.position = SCNVector3(0, 0.14, 0)
        root.addChildNode(core)
        let halo = SCNNode(geometry: SCNSphere(radius: 0.2))
        halo.geometry?.materials = [shiny(violet, emission: violet, additive: true, alpha: 0.28)]
        halo.position = core.position
        root.addChildNode(halo)
        // 回る輪（2 本。たがいにちがう向き）
        for (k, color) in [violet, cyan].enumerated() {
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.19 + CGFloat(k) * 0.04, pipeRadius: 0.009))
            ring.geometry?.materials = [shiny(color, emission: color)]
            ring.position = core.position
            ring.eulerAngles = SCNVector3(Float.pi / 2.2 * Float(k + 1) * 0.6, 0, Float(k) * 0.8)
            ring.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat(k == 0 ? 2 : -2.6), z: 0, duration: 1.6)))
            root.addChildNode(ring)
        }
        // 核がゆっくり脈うつ
        core.runAction(.repeatForever(.sequence([.scale(to: 1.18, duration: 0.8), .scale(to: 0.92, duration: 0.8)])))
        return root
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
        case 3, 4:
            // クローラー（3 = でんどう、4 = おおがた）
            let big = tier == 4
            let body = big ? UIColor(red: 1.0, green: 0.72, blue: 0.14, alpha: 1) : UIColor(red: 0.30, green: 0.62, blue: 0.95, alpha: 1)
            let dark = UIColor(white: 0.16, alpha: 1)
            let metal = UIColor(white: 0.78, alpha: 1)
            // 車体と運転席
            root.addChildNode(box(0.86, 0.34, 1.2, body, SCNVector3(0, 0.50, 0.1)))
            root.addChildNode(box(0.62, 0.34, 0.52, UIColor(white: 0.96, alpha: 1), SCNVector3(0, 0.84, 0.28)))
            root.addChildNode(box(0.56, 0.16, 0.04, UIColor(red: 0.35, green: 0.60, blue: 0.90, alpha: 1), SCNVector3(0, 0.88, 0.0)))
            // キャタピラ（左右）と車輪
            for side: Float in [-1, 1] {
                root.addChildNode(box(0.24, 0.36, 1.55, dark, SCNVector3(side * 0.52, 0.18, 0.1)))
                for z: Float in [-0.55, 0.1, 0.75] {
                    let wheel = SCNNode(geometry: SCNCylinder(radius: 0.15, height: 0.26))
                    wheel.geometry?.materials = [material(metal)]
                    wheel.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    wheel.position = SCNVector3(side * 0.52, 0.18, z)
                    root.addChildNode(wheel)
                }
            }
            // 雪玉を押す、まえのブレード
            root.addChildNode(box(1.22, 0.55, 0.07, metal, SCNVector3(0, 0.40, -0.72)))
            root.addChildNode(box(1.22, 0.06, 0.12, body, SCNVector3(0, 0.70, -0.70)))
            // ライト
            root.addChildNode(glowing(0.07, UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1), SCNVector3(-0.3, 0.62, -0.52)))
            root.addChildNode(glowing(0.07, UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1), SCNVector3(0.3, 0.62, -0.52)))
            root.addChildNode(glowing(0.05, UIColor(red: 1.0, green: 0.45, blue: 0.30, alpha: 1), SCNVector3(0, 1.08, 0.3)))
        default:
            break
        }
        return root
    }

    // MARK: 時間帯・ブラックホール・ぎゅっ

    private func applyDaypart(_ daypart: Daypart) {
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
        var bulbGlow: CGFloat = 0
        var pool: CGFloat = 0
        var sparkle: CGFloat = 0
        var lamp: CGFloat = 0
        var ballGlow = UIColor.black
        switch daypart {
        case .day:
            ambient.light?.color = color(0.60, 0.66, 0.78)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.96, 0.88)
            sun.light?.intensity = 800
            camera.wantsHDR = false
            camera.bloomIntensity = 0
            groundMaterial.multiply.contents = UIColor.white
        case .dusk:
            ambient.light?.color = color(0.55, 0.48, 0.62)
            ambient.light?.intensity = 1000
            sun.light?.color = color(1.0, 0.70, 0.50)
            sun.light?.intensity = 750
            bulbGlow = 0.9
            pool = 0.45
            sparkle = 4
            lamp = 250
            ballGlow = color(0.10, 0.07, 0.06)
            groundMaterial.multiply.contents = color(0.92, 0.86, 0.92)
            camera.wantsHDR = false
            camera.bloomIntensity = 0
        case .night:
            // 雪玉が見えるくらいには明るく。電球だけがにじんで光る。
            ambient.light?.color = color(0.40, 0.46, 0.70)
            ambient.light?.intensity = 1000
            sun.light?.color = color(0.60, 0.68, 1.0)
            sun.light?.intensity = 450
            bulbGlow = 2.6
            pool = 0.9
            sparkle = 16
            lamp = 1300
            ballGlow = color(0.36, 0.38, 0.54)
            // 地面を少し暗くして、雪玉が浮かび上がるようにする
            groundMaterial.multiply.contents = color(0.66, 0.71, 0.90)
            camera.wantsHDR = true
            camera.bloomThreshold = 0.85
            camera.bloomBlurRadius = 14
            camera.bloomIntensity = 1.2
        }
        for material in bulbMaterials() {
            material.emission.intensity = bulbGlow
        }
        windowMaterial.emission.intensity = bulbGlow * 0.32
        poolMaterial.transparency = pool
        lampLight.light?.intensity = lamp
        if !lastBlackHole { ballMaterial.emission.contents = ballGlow }
        sparkleSystem.birthRate = sparkle
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

    /// 光の粒（中心が明るく、ふちが透ける、やわらかい点）
    private static func glowDot(size: Int) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0.35).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1]) else { return }
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size) / 2, options: [])
        }
    }

    /// 木の道の足元に映る光だまり。黒い地に、金色の光をぼかして描く（足し算で重ねる）。
    /// 横は道のはば（-1〜1）、たては木 1 本ぶんのくり返し。光は木の足元（左右のふち）と、道のへりにだけ置く。
    private static func poolImage(size: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            UIColor.black.setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let side = CGFloat(size)
            func blob(centerU: CGFloat, centerV: CGFloat, radiusU: CGFloat, radiusV: CGFloat, strength: CGFloat) {
                let colors = [
                    UIColor(red: 1.0 * strength, green: 0.74 * strength, blue: 0.36 * strength, alpha: 1).cgColor,
                    UIColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor,
                ] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
                cg.saveGState()
                cg.translateBy(x: centerU * side, y: centerV * side)
                cg.scaleBy(x: radiusU * side, y: radiusV * side)
                cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                cg.restoreGState()
            }
            // 木の足元（くり返しの継ぎ目をまたぐので、上下に 1 つずつ描く）
            for centerV: CGFloat in [0, 1] {
                for centerU: CGFloat in [0.079, 0.921] {
                    blob(centerU: centerU, centerV: centerV, radiusU: 0.22, radiusV: 0.40, strength: 0.85)
                }
                // 道のへり（ボールが通る側）
                for centerU: CGFloat in [0.303, 0.697] {
                    blob(centerU: centerU, centerV: centerV, radiusU: 0.09, radiusV: 0.26, strength: 0.30)
                }
            }
        }
    }
}
