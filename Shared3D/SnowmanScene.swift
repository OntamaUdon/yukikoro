import SceneKit
import UIKit
import Metal
import simd

/// 光源・カメラ・足元の影をそろえた、雪だるま1体ぶんのシーン。
enum SnowmanScene {
    struct Built {
        let scene: SCNScene
        let camera: SCNNode
        let snowman: SCNNode
    }

    static func addLights(to scene: SCNScene, ambientIntensity: CGFloat = 800, keyIntensity: CGFloat = 900, ambientColor: UIColor = UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 1)) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = ambientColor
        ambient.light?.intensity = ambientIntensity
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        key.light?.intensity = keyIntensity
        key.eulerAngles = SCNVector3(-0.85, -0.55, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.color = UIColor(red: 0.80, green: 0.88, blue: 1.0, alpha: 1)
        rim.light?.intensity = keyIntensity * 0.35
        rim.eulerAngles = SCNVector3(-0.4, 2.6, 0)
        scene.rootNode.addChildNode(rim)
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
            let colors = [UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 0.38).cgColor,
                          UIColor(red: 0.30, green: 0.40, blue: 0.62, alpha: 0.0).cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
    }()

    static func make(species: Species, decorations: [Decoration], background: UIColor? = nil, animated: Bool = true) -> Built {
        let scene = SCNScene()
        scene.background.contents = background ?? UIColor.clear
        addLights(to: scene)

        let snowman = SnowmanBuilder.make(species: species, decorations: decorations)
        scene.rootNode.addChildNode(snowman)
        scene.rootNode.addChildNode(shadowBlob())

        if animated {
            let breathe = SCNAction.customAction(duration: 2.6) { node, t in
                let s = sin(Float(t) / 2.6 * 2 * .pi) * 0.016
                node.scale = SCNVector3(1 - s * 0.6, 1 + s, 1 - s * 0.6)
            }
            snowman.runAction(.repeatForever(breathe))
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 28
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.position = SCNVector3(0, 1.55, 5.8)
        camera.look(at: SCNVector3(0, 0.98, 0))
        scene.rootNode.addChildNode(camera)
        return Built(scene: scene, camera: camera, snowman: snowman)
    }
}

/// シーンを画像にする（図鑑のサムネイル・共有画像・ウィジェット用）。メインスレッドで使う。
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

        let built = SnowmanScene.make(species: species, decorations: decorations, background: background, animated: false)
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
