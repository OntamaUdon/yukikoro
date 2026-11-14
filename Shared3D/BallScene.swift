import SceneKit
import UIKit
import simd

/// ホームに出す「転がる雪玉」の 3D シーン。時刻に合わせた空と雪原の上で、歩数に合わせて雪玉が大きくなる。
final class BallScene: NSObject {
    let scene: SCNScene
    let camera = SCNNode()
    private let rig: SkyRig
    private let pivot = SCNNode()   // 位置と大きさ
    private let ball = SCNNode()    // 回転
    private var steps = 0
    private var hasShown = false
    private var timer: Timer?
    private let hourProvider: () -> Double

    /// 雪玉をカメラの正面に置く距離
    static let ballDistance: Float = 4.4

    init(hourProvider: @escaping () -> Double) {
        self.hourProvider = hourProvider
        let newScene = SCNScene()
        scene = newScene
        rig = SkyRig(scene: newScene, ground: true, shadows: true)
        super.init()
        rig.apply(hour: hourProvider())
        buildBall()
        buildCamera()
        buildSnowfall()
        // 空は時間とともにゆっくり変わる
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.rig.apply(hour: self.hourProvider())
        }
    }

    deinit { timer?.invalidate() }

    func refreshSky() { rig.apply(hour: hourProvider()) }

    // MARK: 雪玉

    private func buildBall() {
        let shape = SnowShape.pristine(seed: 11)
        ball.geometry = SculptMesh.geometry(for: shape, material: SnowMaterial.make())
        pivot.addChildNode(ball)
        scene.rootNode.addChildNode(pivot)
        apply(steps: 0, animated: false)
    }

    private func buildCamera() {
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 42
        SceneSetup.configure(camera: camera.camera!, exposure: -0.3)
        camera.position = SCNVector3(0, 1.6, 0)
        camera.look(at: SCNVector3(0, 0.34, -BallScene.ballDistance))
        scene.rootNode.addChildNode(camera)
    }

    private func buildSnowfall() {
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
        let radius = Float(BallScale.radius(steps: newSteps))
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        // 大きくなったら雪玉を遠くへ置き、画面からはみ出さないようにする（見かけの大きさはゆっくり増える）
        let distance = Float(BallScale.distance(radius: Double(radius), baseDistance: Double(BallScene.ballDistance)))
        pivot.simdScale = SIMD3<Float>(repeating: radius)
        pivot.simdPosition = SIMD3<Float>(0, radius, -distance)
        if animated { SCNTransaction.commit() }

        if animated, newSteps > old {
            let rolled = Float(newSteps - old) * 0.02
            let angle = min(max(0.6, rolled / radius), 3 * Float.pi)
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
