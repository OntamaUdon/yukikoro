import SceneKit
import UIKit
import Metal
import simd

/// 写真の空（HDRI）で照らした、雪だるま1体ぶんのシーン。
enum SnowmanScene {
    struct Built {
        let scene: SCNScene
        let camera: SCNNode
        let snowman: SCNNode
    }

    /// 空の写真（HDRI）で全体を照らす。写真が無い環境（テスト等）では環境光で代用する。
    static func applyEnvironment(to scene: SCNScene, daypart: Daypart, background: Bool, yaw: Float = 0) {
        let transform = SCNMatrix4MakeRotation(yaw, 0, 1, 0)
        if let url = PhotoAssets.hdr(daypart.hdrName) {
            scene.lightingEnvironment.contents = url
            scene.lightingEnvironment.intensity = daypart.environmentIntensity
            scene.lightingEnvironment.contentsTransform = transform
            if background {
                if let custom = PhotoAssets.customBackground() {
                    scene.background.contents = custom
                } else {
                    scene.background.contents = url
                }
                scene.background.intensity = daypart == .night ? 0.2 : 1.0
                scene.background.contentsTransform = transform
            }
        } else {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 900
            ambient.light?.color = UIColor(red: 0.8, green: 0.88, blue: 1.0, alpha: 1)
            scene.rootNode.addChildNode(ambient)
        }
    }

    /// 太陽（影を落とす光）。向きは写真の太陽の方向に合わせる。
    static func addSun(to scene: SCNScene, daypart: Daypart, castsShadow: Bool, intensity: CGFloat = 1200) {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = daypart == .dusk ? UIColor(red: 1.0, green: 0.86, blue: 0.70, alpha: 1) : UIColor(red: 1.0, green: 0.97, blue: 0.93, alpha: 1)
        sun.light?.intensity = daypart == .night ? intensity * 0.25 : intensity
        sun.light?.temperature = 6500
        if castsShadow {
            sun.light?.castsShadow = true
            sun.light?.shadowMode = .deferred
            sun.light?.shadowRadius = 8
            sun.light?.shadowSampleCount = 8
            sun.light?.shadowColor = UIColor(red: 0.12, green: 0.18, blue: 0.32, alpha: 0.55)
            sun.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
            sun.light?.automaticallyAdjustsShadowProjection = true
        }
        // 太陽は雪玉の奥・右上から手前へ向かう（影が雪玉の手前に落ちて見える）。サムネイルなど影を落とさないときは手前左上から。
        let elevation: Float = daypart == .day ? -0.75 : -0.35
        if castsShadow {
            sun.eulerAngles = SCNVector3(elevation, Float.pi - 0.6, 0)
        } else {
            sun.eulerAngles = SCNVector3(elevation, -0.55, 0)
        }
        scene.rootNode.addChildNode(sun)
    }

    static func configure(camera cam: SCNCamera, exposure: CGFloat = -0.3) {
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = exposure
        cam.minimumExposure = -2
        cam.maximumExposure = 2
        cam.bloomIntensity = 0.12
        cam.bloomThreshold = 1.6
        cam.bloomBlurRadius = 8
        cam.vignettingIntensity = 0.25
        cam.vignettingPower = 1.0
        cam.zNear = 0.05
        cam.zFar = 200
    }

    /// 足元のやわらかい影（板に放射状のグラデーションを貼る）
    static func shadowBlob(size: Float = 1.7) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(size), height: CGFloat(size))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = radialShadowImage
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, 0.004, 0)
        return node
    }

    static let radialShadowImage: UIImage = {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor(red: 0.20, green: 0.28, blue: 0.45, alpha: 0.5).cgColor,
                          UIColor(red: 0.20, green: 0.28, blue: 0.45, alpha: 0.0).cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
    }()

    static func make(species: Species, decorations: [Decoration], background: UIColor? = nil, animated: Bool = true, tight: Bool = false) -> Built {
        let scene = SCNScene()
        scene.background.contents = background ?? UIColor.clear
        applyEnvironment(to: scene, daypart: .day, background: false)
        addSun(to: scene, daypart: .day, castsShadow: false, intensity: 700)

        let snowman = SnowmanBuilder.make(species: species, decorations: decorations)
        scene.rootNode.addChildNode(snowman)
        scene.rootNode.addChildNode(shadowBlob())

        if animated {
            // ごくゆっくり息をするように伸び縮みする
            let breathe = SCNAction.customAction(duration: 3.2) { node, t in
                let s = sin(Float(t) / 3.2 * 2 * .pi) * 0.008
                node.scale = SCNVector3(1 - s * 0.6, 1 + s, 1 - s * 0.6)
            }
            snowman.runAction(.repeatForever(breathe))
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 25
        configure(camera: camera.camera!)
        // tight: 図鑑・共有画像用に、少し近くから大きく写す（腕や耳が切れない範囲で）
        camera.position = tight ? SCNVector3(0, 1.5, 5.4) : SCNVector3(0, 1.55, 5.8)
        camera.look(at: tight ? SCNVector3(0, 1.02, 0) : SCNVector3(0, 0.98, 0))
        scene.rootNode.addChildNode(camera)
        return Built(scene: scene, camera: camera, snowman: snowman)
    }
}

/// シーンを画像にする（図鑑のサムネイル・共有画像用）。メインスレッドで使う。
@MainActor
enum SnowmanSnapshot {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var renderer: SCNRenderer?
    private static let cache = NSCache<NSString, UIImage>()

    static func image(species: Species, decorations: [Decoration], size: CGSize, scale: CGFloat = 2, background: UIColor? = nil) -> UIImage? {
        let key = "\(species.rawValue)|\(decorations.map { "\($0.kind.rawValue)\($0.hue)" }.joined(separator: ","))|\(Int(size.width))x\(Int(size.height))@\(scale)|\(background == nil ? "c" : "b")" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let device else { return nil }
        if renderer == nil { renderer = SCNRenderer(device: device, options: nil) }
        guard let renderer else { return nil }

        let built = SnowmanScene.make(species: species, decorations: decorations, background: background, animated: false, tight: true)
        renderer.scene = built.scene
        renderer.pointOfView = built.camera
        let pixel = CGSize(width: size.width * scale, height: size.height * scale)
        let image = renderer.snapshot(atTime: 0, with: pixel, antialiasingMode: .multisampling4X)
        cache.setObject(image, forKey: key)
        return image
    }

    static func image(for snowman: Snowman, size: CGSize, scale: CGFloat = 2, background: UIColor? = nil) -> UIImage? {
        image(species: snowman.species, decorations: snowman.decorations, size: size, scale: scale, background: background)
    }
}
