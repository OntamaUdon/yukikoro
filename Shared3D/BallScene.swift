import SceneKit
import UIKit
import Metal
import simd

/// ホームに出す「転がる雪玉」の 3D シーン。雪道の写真を背景に、実際の光で照らされた雪玉が歩数に合わせて大きくなる。
final class BallScene: NSObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private let pivot = SCNNode()   // 位置と大きさ
    private let ball = SCNNode()    // 回転
    private var steps = 0
    private var hasShown = false

    /// 雪玉をカメラの正面に置く距離
    static let ballDistance: Float = 4.4

    init(daypart: Daypart, yaw: Float? = nil) {
        super.init()
        SnowmanScene.applyEnvironment(to: scene, daypart: daypart, background: true, yaw: yaw ?? daypart.backgroundYaw)
        SnowmanScene.addSun(to: scene, daypart: daypart, castsShadow: true, intensity: 700)
        buildGround()
        buildBall()
        buildCamera(daypart: daypart)
        buildSnowfall(daypart: daypart)
    }

    // MARK: 世界

    /// 影だけを受ける床（写真の地面の上に、雪玉の影だけを重ねる）
    private func buildGround() {
        let plane = SCNPlane(width: 60, height: 60)
        let m = SCNMaterial()
        m.lightingModel = .shadowOnly
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0, -BallScene.ballDistance)
        scene.rootNode.addChildNode(node)
    }

    // MARK: 雪玉

    /// 半径1の雪玉（写真素材の質感）
    static func makeBallNode() -> SCNNode {
        let geo = SnowGeometry.blob(radius: 1, seed: 11, lump: 0.06, frequency: 1.4, rings: 72, segments: 144, tile: (3, 2))
        geo.materials = [PBR.snow(tile: (1, 1))]
        return SCNNode(geometry: geo)
    }

    private func buildBall() {
        ball.addChildNode(BallScene.makeBallNode())
        pivot.addChildNode(ball)
        scene.rootNode.addChildNode(pivot)
        apply(steps: 0, animated: false)
    }

    private func buildCamera(daypart: Daypart) {
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 42
        SnowmanScene.configure(camera: camera.camera!, exposure: daypart == .day ? -0.9 : -0.4)
        camera.position = SCNVector3(0, 1.6, 0)
        camera.look(at: SCNVector3(0, 0.34, -BallScene.ballDistance))
        scene.rootNode.addChildNode(camera)
    }

    private func buildSnowfall(daypart: Daypart) {
        let ps = SCNParticleSystem()
        ps.birthRate = 26
        ps.particleLifeSpan = 8
        ps.particleLifeSpanVariation = 2
        ps.emitterShape = SCNPlane(width: 14, height: 10)
        ps.particleVelocity = 0.8
        ps.particleVelocityVariation = 0.5
        ps.emittingDirection = SCNVector3(0, 0, -1)
        ps.spreadingAngle = 20
        ps.particleSize = 0.035
        ps.particleSizeVariation = 0.02
        ps.particleColor = .white
        ps.particleImage = BallScene.flakeImage
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0.1, -0.05, 0)
        ps.warmupDuration = 8
        let node = SCNNode()
        node.position = SCNVector3(0, 5, -3)
        node.eulerAngles.x = -.pi / 2
        node.addParticleSystem(ps)
        scene.rootNode.addChildNode(node)
    }

    // MARK: 更新

    /// 歩数に合わせて大きさと回転を更新する。
    func update(steps newSteps: Int) {
        guard newSteps != steps || !hasShown else { return }
        apply(steps: newSteps, animated: hasShown)
        hasShown = true
    }

    private func apply(steps newSteps: Int, animated: Bool) {
        let old = steps
        steps = newSteps
        let fraction = Float(BallScale.fraction(newSteps))
        let radius = 0.28 + 1.0 * fraction
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        pivot.simdScale = SIMD3<Float>(repeating: radius)
        pivot.simdPosition = SIMD3<Float>(0, radius, -BallScene.ballDistance)
        if animated { SCNTransaction.commit() }

        if animated, newSteps > old {
            let distance = Float(newSteps - old) * 0.02
            let angle = min(max(0.6, distance / radius), 3 * .pi)
            let roll = SCNAction.rotateBy(x: CGFloat(angle), y: 0, z: 0, duration: 1.6)
            roll.timingMode = .easeInEaseOut
            ball.runAction(roll)
        }
    }

    // MARK: 画像

    private static let flakeImage: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.3, 1]) else { return }
            let c = CGPoint(x: 16, y: 16)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: 16, options: [])
        }
    }()
}

/// ウィジェット用の、雪玉1個だけの静止画
@MainActor
enum BallSnapshot {
    static func image(size: CGSize, scale: CGFloat = 2, background: UIColor) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let scene = SCNScene()
        scene.background.contents = background
        SnowmanScene.applyEnvironment(to: scene, daypart: .day, background: false)
        SnowmanScene.addSun(to: scene, daypart: .day, castsShadow: false, intensity: 700)
        let ball = BallScene.makeBallNode()
        ball.position = SCNVector3(0, 1, 0)
        ball.eulerAngles.x = 0.6
        scene.rootNode.addChildNode(ball)
        scene.rootNode.addChildNode(SnowmanScene.shadowBlob(size: 2.6))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 26
        SnowmanScene.configure(camera: camera.camera!)
        camera.position = SCNVector3(0.4, 1.9, 6.4)
        camera.look(at: SCNVector3(0, 0.9, 0))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: CGSize(width: size.width * scale, height: size.height * scale), antialiasingMode: .multisampling4X)
    }
}
