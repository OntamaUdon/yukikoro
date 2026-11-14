import SceneKit
import UIKit

/// 時間帯ごとの空（写真）と光の設定
enum Daypart {
    case day, dusk, night

    static func current(hour: Int) -> Daypart {
        switch hour {
        case 8..<16: return .day
        case 5..<8, 16..<19: return .dusk
        default: return .night
        }
    }

    var hdrName: String {
        switch self {
        case .day: return "snowy_forest_path_01_1k"
        case .dusk, .night: return "stierberg_sunrise_1k"
        }
    }

    /// 空の写真の明るさ
    var environmentIntensity: CGFloat {
        switch self {
        case .day: return 1.0
        case .dusk: return 0.9
        case .night: return 0.3
        }
    }

    /// 背景の写真を回す角度（道・雪原が正面に来るように）
    var backgroundYaw: Float {
        switch self {
        case .day: return Float.pi            // 雪道と林が正面に来る向き
        case .dusk, .night: return Float.pi * 1.5   // 夕日と雪原が正面に来る向き
        }
    }
}

/// 写真の空（HDRI）の背景と照明、太陽の光、カメラの設定
enum PhotoSky {
    /// 空の写真（HDRI）で全体を照らす。写真が無い環境（テスト等）では環境光で代用する。
    static func apply(to scene: SCNScene, daypart: Daypart, background: Bool, yaw: Float? = nil) {
        let transform = SCNMatrix4MakeRotation(yaw ?? daypart.backgroundYaw, 0, 1, 0)
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

    /// 太陽（雪玉を照らす光）。
    static func addSun(to scene: SCNScene, daypart: Daypart, intensity: CGFloat = 1200) {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.color = daypart == .dusk ? UIColor(red: 1.0, green: 0.86, blue: 0.70, alpha: 1) : UIColor(red: 1.0, green: 0.97, blue: 0.93, alpha: 1)
        sun.light?.intensity = daypart == .night ? intensity * 0.25 : intensity
        sun.light?.temperature = 6500
        let elevation: Float = daypart == .day ? -0.75 : -0.35
        sun.eulerAngles = SCNVector3(elevation, -0.55, 0)
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

    /// 足元のやわらかい影（板に放射状のグラデーションを貼る）。大きさは scale で決める。
    static func shadowBlob() -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = shadowImage
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 5
        return node
    }

    private static let shadowImage: UIImage = {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(red: 0.20, green: 0.28, blue: 0.45, alpha: 0.5).cgColor,
                          UIColor(red: 0.20, green: 0.28, blue: 0.45, alpha: 0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 1]) else { return }
            let c = CGPoint(x: 64, y: 64)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 64, options: [])
        }
    }()

    /// 足元の雪面（写真の地面の上に、端をなめらかに溶かして敷く）。作品の画面で、ゆきだまを地面に乗せるために使う。
    static func groundDisc(radius: Float) -> SCNNode {
        let plane = SCNPlane(width: CGFloat(radius * 2), height: CGFloat(radius * 2))
        let m = PBR.snow(tile: (radius * 2.5, radius * 2.5))
        m.roughness.contents = 0.95
        m.transparent.contents = groundMask
        m.transparencyMode = .aOne
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        return node
    }

    /// 中心が不透明、外が透明（アルファで表す）
    private static let groundMask: UIImage = {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 0.97]) else { return }
            let center = CGPoint(x: 128, y: 128)
            ctx.cgContext.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 128, options: [])
        }
    }()
}
