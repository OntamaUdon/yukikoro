import SceneKit
import UIKit
import Metal
import simd

/// ホームに出す「転がる雪玉」の 3D シーン。歩数に合わせて大きくなり、増えるたびにころころ回る。
final class BallScene: NSObject {
    let scene = SCNScene()
    let camera = SCNNode()
    private let pivot = SCNNode()   // 位置と大きさ
    private let ball = SCNNode()    // 回転
    private var steps = 0
    private var hasShown = false

    init(isDark: Bool, skyTop: UIColor, skyBottom: UIColor) {
        super.init()
        scene.background.contents = BallScene.gradientImage(top: skyTop, bottom: skyBottom)
        if isDark {
            SnowmanScene.addLights(to: scene, ambientIntensity: 620, keyIntensity: 700, ambientColor: UIColor(red: 0.62, green: 0.70, blue: 1.0, alpha: 1))
        } else {
            SnowmanScene.addLights(to: scene)
        }
        buildWorld(isDark: isDark)
        buildBall()
        buildCamera()
        buildSnowfall()
    }

    // MARK: 世界

    private func buildWorld(isDark: Bool) {
        let ground = solid(SCNSphere(radius: 60), UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1), outline: false)
        ground.position = SCNVector3(0, -60, 0)
        scene.rootNode.addChildNode(ground)

        let hillColors = [UIColor(red: 0.86, green: 0.92, blue: 0.99, alpha: 1), UIColor(red: 0.81, green: 0.88, blue: 0.97, alpha: 1)]
        let hills: [(Float, Float, Float, Float, Int)] = [
            (-9, -11, -16, 12, 0), (11, -15, -24, 17, 1), (-2, -9, -30, 15, 1),
        ]
        for (x, y, z, r, c) in hills {
            let hill = solid(SCNSphere(radius: CGFloat(r)), hillColors[c], outline: false)
            hill.position = SCNVector3(x, y, z)
            scene.rootNode.addChildNode(hill)
        }

        let treeColors = [UIColor(red: 0.50, green: 0.70, blue: 0.76, alpha: 1), UIColor(red: 0.42, green: 0.62, blue: 0.72, alpha: 1)]
        let spots: [(Float, Float, Float)] = [
            (-5.5, -7, 1.3), (-3.6, -9.5, 1.0), (4.8, -8, 1.2), (6.6, -6, 0.9), (2.6, -11, 1.1),
            (-7.5, -4.5, 0.8), (8.8, -4, 1.0), (-1.2, -14, 1.4),
        ]
        for (i, spot) in spots.enumerated() {
            let tree = pine(color: treeColors[i % 2])
            tree.simdScale = SIMD3<Float>(repeating: spot.2)
            tree.position = SCNVector3(spot.0, 0, spot.1)
            scene.rootNode.addChildNode(tree)
        }
    }

    private func pine(color: UIColor) -> SCNNode {
        let tree = SCNNode()
        let trunk = solid(SCNCylinder(radius: 0.08, height: 0.4), UIColor(red: 0.50, green: 0.38, blue: 0.32, alpha: 1), outline: false)
        trunk.position = SCNVector3(0, 0.2, 0)
        tree.addChildNode(trunk)
        let layers: [(Float, Float, Float)] = [(0.62, 0.9, 0.55), (0.48, 0.8, 1.05), (0.34, 0.7, 1.5)]
        for (r, h, y) in layers {
            let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(r), height: CGFloat(h))
            let node = solid(cone, color, outline: true)
            node.position = SCNVector3(0, y, 0)
            tree.addChildNode(node)
            let cap = SCNCone(topRadius: 0, bottomRadius: CGFloat(r * 0.62), height: CGFloat(h * 0.5))
            let capNode = solid(cap, UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1), outline: false)
            capNode.position = SCNVector3(0, y + h * 0.22, 0.0)
            tree.addChildNode(capNode)
        }
        return tree
    }

    // MARK: 雪玉

    /// 半径1の雪玉（表面の模様つき・輪郭つき）
    static func makeBallNode() -> SCNNode {
        let geo = SCNSphere(radius: 1)
        geo.segmentCount = 64
        geo.materials = [Toon.texturedMaterial(BallScene.snowTexture)]
        let sphere = SCNNode(geometry: geo)
        addOutline(to: sphere, geometry: geo)
        return sphere
    }

    private func buildBall() {
        ball.addChildNode(BallScene.makeBallNode())
        pivot.addChildNode(ball)
        scene.rootNode.addChildNode(pivot)
        apply(steps: 0, animated: false)
    }

    private func buildCamera() {
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 40
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 200
        camera.position = SCNVector3(1.1, 2.6, 8.6)
        camera.look(at: SCNVector3(-0.15, 0.55, 0))
        scene.rootNode.addChildNode(camera)
    }

    private func buildSnowfall() {
        let ps = SCNParticleSystem()
        ps.birthRate = 38
        ps.particleLifeSpan = 9
        ps.particleLifeSpanVariation = 2
        ps.emitterShape = SCNPlane(width: 24, height: 12)
        ps.particleVelocity = 0.9
        ps.particleVelocityVariation = 0.5
        ps.emittingDirection = SCNVector3(0, 0, -1)
        ps.spreadingAngle = 18
        ps.particleSize = 0.075
        ps.particleSizeVariation = 0.04
        ps.particleColor = .white
        ps.particleImage = BallScene.flakeImage
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        ps.acceleration = SCNVector3(0.12, -0.05, 0)
        ps.warmupDuration = 8
        let node = SCNNode()
        node.position = SCNVector3(0, 9, -3)
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
        let radius = 0.36 + 0.9 * fraction
        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        }
        pivot.simdScale = SIMD3<Float>(repeating: radius)
        pivot.simdPosition = SIMD3<Float>(0, radius, 0)
        if animated { SCNTransaction.commit() }

        if animated, newSteps > old {
            let distance = Float(newSteps - old) * 0.02
            let angle = min(max(0.6, distance / radius), 3 * .pi)
            let roll = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-angle), duration: 1.6)
            roll.timingMode = .easeInEaseOut
            ball.runAction(roll)
        }
    }

    // MARK: 画像

    private static func gradientImage(top: UIColor, bottom: UIColor) -> UIImage {
        let size = CGSize(width: 4, height: 512)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private static let flakeImage: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1]) else { return }
            let c = CGPoint(x: 16, y: 16)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: 16, options: [])
        }
    }()

    /// 表面のやわらかなむら。球に貼って回すと転がって見える。
    private static let snowTexture: UIImage = {
        let size = CGSize(width: 1024, height: 512)
        var rng = SplitMix64(seed: 90210)
        func rand() -> CGFloat { CGFloat(Double(rng.next() % 10_000) / 10_000) }
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            UIColor(red: 0.975, green: 0.985, blue: 1.0, alpha: 1).setFill()
            g.fill(CGRect(origin: .zero, size: size))
            let space = CGColorSpaceCreateDeviceRGB()
            for _ in 0..<70 {
                let r = 40 + rand() * 90
                let x = rand() * size.width
                let y = 50 + rand() * (size.height - 100)
                let alpha = 0.16 + rand() * 0.14
                let colors = [UIColor(red: 0.66, green: 0.76, blue: 0.93, alpha: alpha).cgColor,
                              UIColor(red: 0.66, green: 0.76, blue: 0.93, alpha: 0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { continue }
                for dx in [-size.width, 0, size.width] {
                    let c = CGPoint(x: x + dx, y: y)
                    g.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
                }
            }
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
        SnowmanScene.addLights(to: scene)
        let ball = BallScene.makeBallNode()
        ball.simdScale = SIMD3<Float>(repeating: 1)
        ball.position = SCNVector3(0, 1, 0)
        ball.eulerAngles.z = -0.6
        scene.rootNode.addChildNode(ball)
        scene.rootNode.addChildNode(SnowmanScene.shadowBlob(size: 2.6))
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 26
        camera.position = SCNVector3(0.4, 1.9, 6.4)
        camera.look(at: SCNVector3(0, 0.9, 0))
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: CGSize(width: size.width * scale, height: size.height * scale), antialiasingMode: .multisampling4X)
    }
}
