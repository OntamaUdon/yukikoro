import SceneKit
import UIKit
import Metal
import simd

/// 作品（複数のゆきだまの組み合わせ）を 3D で表示する世界。空・雪原・ゆきだまを持つ。
/// 作品の編集画面・一覧のサムネイル・共有画像で共通に使う。
final class ArtworkWorld {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let rig: SkyRig
    var orbit = OrbitCamera(azimuth: 0.55, elevation: 0.28, distance: 7, target: SIMD3<Float>(0, 0.9, 0),
                            minDistance: 2.5, maxDistance: 40, minElevation: 0.02, maxElevation: 1.4)

    private var nodes: [UUID: SCNNode] = [:]
    private var materials: [UUID: SCNMaterial] = [:]
    private var shapes: [UUID: SnowShape] = [:]

    init(hour: Double, shadows: Bool) {
        rig = SkyRig(scene: scene, ground: true, shadows: shadows)
        rig.apply(hour: hour)
        let cam = SCNCamera()
        cam.fieldOfView = 42
        SceneSetup.configure(camera: cam, exposure: -0.3)
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        orbit.apply(to: cameraNode)
    }

    func applyOrbit() { orbit.apply(to: cameraNode) }

    // MARK: ゆきだま

    /// 作品の中身に合わせて、ゆきだまのノードを作る・消す・動かす。
    func sync(_ placements: [Placement], selected: UUID? = nil) {
        let ids = Set(placements.map(\.id))
        for (id, node) in nodes where !ids.contains(id) {
            node.removeFromParentNode()
            nodes[id] = nil
            materials[id] = nil
            shapes[id] = nil
        }
        for p in placements {
            let material: SCNMaterial
            let node: SCNNode
            if let existing = nodes[p.id], let m = materials[p.id] {
                node = existing
                material = m
            } else {
                material = SnowMaterial.make()
                node = SCNNode()
                node.name = p.id.uuidString
                scene.rootNode.addChildNode(node)
                nodes[p.id] = node
                materials[p.id] = material
            }
            if shapes[p.id] != p.piece.shape || node.geometry == nil {
                node.geometry = SculptMesh.geometry(for: p.piece.shape, material: material)
                shapes[p.id] = p.piece.shape
            }
            node.simdScale = SIMD3<Float>(repeating: p.piece.radius)
            node.simdPosition = p.position
            node.simdOrientation = p.orientation
            SnowMaterial.setSelected(material, p.id == selected)
        }
    }

    /// 置いたゆきだま全体が見える位置にカメラを合わせる。
    func frameAll(_ placements: [Placement]) {
        guard !placements.isEmpty else {
            orbit.target = SIMD3<Float>(0, 0.9, 0)
            orbit.distance = 7
            applyOrbit()
            return
        }
        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for p in placements {
            let r = SIMD3<Float>(repeating: p.piece.radius)
            low = simd_min(low, p.position - r)
            high = simd_max(high, p.position + r)
        }
        let center = (low + high) / 2
        let extent = max(simd_length(high - low) / 2, 0.8)
        orbit.target = center
        orbit.distance = min(orbit.maxDistance, max(orbit.minDistance, extent * 3.2))
        applyOrbit()
    }

    /// ワールド座標のノードから、ゆきだまの ID をたどる
    static func pieceID(of node: SCNNode) -> UUID? {
        var current: SCNNode? = node
        while let n = current {
            if let name = n.name, let id = UUID(uuidString: name) { return id }
            current = n.parent
        }
        return nil
    }
}

/// シーンを画像にする（サムネイル・共有画像用）。メインスレッドで使う。
@MainActor
enum SceneSnapshot {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var renderer: SCNRenderer?

    static func image(scene: SCNScene, pointOfView: SCNNode, size: CGSize, scale: CGFloat = 2) -> UIImage? {
        guard let device else { return nil }
        if renderer == nil { renderer = SCNRenderer(device: device, options: nil) }
        guard let renderer else { return nil }
        renderer.scene = scene
        renderer.pointOfView = pointOfView
        return renderer.snapshot(atTime: 0, with: CGSize(width: size.width * scale, height: size.height * scale), antialiasingMode: .multisampling4X)
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// 1つのゆきだまだけを昼の空の前に置いた絵
    static func piece(_ piece: SnowPiece, size: CGSize, scale: CGFloat = 2) -> UIImage? {
        let key = "p-\(piece.id)-\(piece.shape.hashValue)-\(Int(size.width))x\(Int(size.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let world = SnowCameraScene(shape: piece.shape, hour: 12)
        guard let image = image(scene: world.scene, pointOfView: world.cameraNode, size: size, scale: scale) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// 作品の全体像
    static func artwork(_ artwork: Artwork, hour: Double, size: CGSize, scale: CGFloat = 2, useCache: Bool = true) -> UIImage? {
        let key = "a-\(artwork.id)-\(artwork.updatedAt.timeIntervalSince1970)-\(Int(hour))-\(Int(size.width))x\(Int(size.height))" as NSString
        if useCache, let hit = cache.object(forKey: key) { return hit }
        let world = ArtworkWorld(hour: hour, shadows: false)
        world.sync(artwork.placements)
        world.frameAll(artwork.placements)
        guard let image = image(scene: world.scene, pointOfView: world.cameraNode, size: size, scale: scale) else { return nil }
        if useCache { cache.setObject(image, forKey: key) }
        return image
    }
}

/// ゆきだま1つを昼の空の前に置いた小さなシーン（一覧のサムネイル用）
final class SnowCameraScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let rig: SkyRig

    init(shape: SnowShape, hour: Double) {
        rig = SkyRig(scene: scene, ground: false, shadows: false)
        rig.apply(hour: hour)
        let node = SCNNode(geometry: SculptMesh.geometry(for: shape, material: SnowMaterial.make()))
        scene.rootNode.addChildNode(node)
        let cam = SCNCamera()
        cam.fieldOfView = 34
        SceneSetup.configure(camera: cam, exposure: -0.3)
        cameraNode.camera = cam
        OrbitCamera(azimuth: 0.5, elevation: 0.3, distance: 4.4).apply(to: cameraNode)
        scene.rootNode.addChildNode(cameraNode)
    }
}
