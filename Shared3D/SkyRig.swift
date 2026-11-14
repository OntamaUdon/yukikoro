import SceneKit
import UIKit
import simd

/// ある時刻の空の様子（色・太陽や月の向き・光の強さ）。時刻から連続的に決まる。
struct SkyState: Equatable {
    var top: SIMD3<Float>
    var horizon: SIMD3<Float>
    /// 光源（昼は太陽、夜は月）へ向かう向き
    var lightDirection: SIMD3<Float>
    var lightColor: SIMD3<Float>
    var lightIntensity: Float
    /// 全体を照らす空の明るさ（0.42〜1）
    var ambient: Float
    /// 星の見え方（0〜1）
    var stars: Float
    var isSun: Bool
    /// 光源の高さ（ラジアン）
    var lightElevation: Float
    /// 太陽の高さ（地平線の下は負）
    var sunElevation: Float

    private static let keys: [(h: Double, top: SIMD3<Float>, horizon: SIMD3<Float>)] = [
        (0.0, SIMD3(0.02, 0.03, 0.09), SIMD3(0.06, 0.08, 0.17)),
        (5.0, SIMD3(0.04, 0.06, 0.16), SIMD3(0.18, 0.20, 0.34)),
        (6.0, SIMD3(0.20, 0.28, 0.52), SIMD3(0.95, 0.58, 0.42)),
        (7.5, SIMD3(0.35, 0.60, 0.88), SIMD3(0.85, 0.85, 0.90)),
        (12.0, SIMD3(0.28, 0.55, 0.92), SIMD3(0.78, 0.88, 0.97)),
        (16.0, SIMD3(0.32, 0.56, 0.88), SIMD3(0.88, 0.88, 0.92)),
        (17.5, SIMD3(0.30, 0.34, 0.62), SIMD3(0.98, 0.62, 0.38)),
        (18.5, SIMD3(0.12, 0.14, 0.34), SIMD3(0.85, 0.40, 0.38)),
        (19.5, SIMD3(0.04, 0.06, 0.16), SIMD3(0.20, 0.20, 0.36)),
        (24.0, SIMD3(0.02, 0.03, 0.09), SIMD3(0.06, 0.08, 0.17)),
    ]

    private static func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// 時刻（0〜24。小数で分も表す）から空の状態を決める。
    static func at(hour rawHour: Double) -> SkyState {
        var h = rawHour.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }

        // 空の色（キーフレームの間を直線でつなぐ）
        var top = keys[0].top
        var horizon = keys[0].horizon
        for n in 1..<keys.count where h <= keys[n].h {
            let a = keys[n - 1], b = keys[n]
            let t = Float((h - a.h) / (b.h - a.h))
            top = a.top + (b.top - a.top) * t
            horizon = a.horizon + (b.horizon - a.horizon) * t
            break
        }

        // 太陽の高さ（6時に昇り、18時に沈む）。夜は月が同じように弧を描く。
        let sunElev = Float(sin((h - 6) / 12 * Double.pi)) * (62 * Float.pi / 180)
        let isSun = h >= 6 && h < 18
        let phase = isSun ? (h - 6) / 12 : ((h < 6 ? h + 24 : h) - 18) / 12
        let maxElev: Float = (isSun ? 62 : 48) * Float.pi / 180
        let elev = Float(sin(phase * Double.pi)) * maxElev
        // 太陽は少し手前の右から差す（影が奥の左に落ちて、雪玉の立体感が出る）
        let az = Float(Double.pi / 2 + phase * Double.pi - 0.8)
        let dir = SIMD3<Float>(cos(elev) * sin(az), sin(elev), -cos(elev) * cos(az))

        let intensity: Float
        let color: SIMD3<Float>
        if isSun {
            // 低い太陽はやや強く、高い太陽は弱めに（雪が白飛びしないように）
            intensity = 2400 * (1 - 0.6 * smoothstep(0.3, 1.0, elev)) * smoothstep(0, 0.25, elev)
            let warm = SIMD3<Float>(1.0, 0.80, 0.62)
            let white = SIMD3<Float>(1.0, 0.97, 0.92)
            color = warm + (white - warm) * smoothstep(0, 0.45, elev)
        } else {
            intensity = 450 * smoothstep(0, 0.2, elev)
            color = SIMD3<Float>(0.6, 0.7, 1.0)
        }
        let dayFactor = smoothstep(-0.05, 0.35, sunElev)
        return SkyState(
            top: top, horizon: horizon, lightDirection: dir, lightColor: color, lightIntensity: intensity,
            ambient: 0.42 + 0.58 * dayFactor,
            stars: 1 - smoothstep(-0.2, 0.05, sunElev),
            isSun: isSun, lightElevation: elev, sunElevation: sunElev
        )
    }

    /// 地平線より下の色（雪原の照り返し）
    var groundTone: SIMD3<Float> {
        let snow = SIMD3<Float>(0.78, 0.84, 0.95) * (0.25 + 0.75 * ambient)
        return horizon * 0.4 + snow * 0.6
    }

    /// 高さ（ラジアン。-π/2〜π/2）での空の色
    func color(elevation e: Float) -> SIMD3<Float> {
        if e >= 0 {
            let t = min(1, pow(e / (Float.pi / 2), 0.6))
            return horizon + (top - horizon) * t
        }
        let t = min(1, -e / (Float.pi / 6))
        return horizon + (groundTone - horizon) * t
    }
}

enum SceneSetup {
    static func configure(camera cam: SCNCamera, exposure: CGFloat = -0.3) {
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = exposure
        cam.minimumExposure = -2
        cam.maximumExposure = 2
        cam.bloomIntensity = 0.12
        cam.bloomThreshold = 1.6
        cam.bloomBlurRadius = 8
        cam.vignettingIntensity = 0.2
        cam.vignettingPower = 1.0
        cam.saturation = 1.3
        cam.contrast = 0.1
        cam.zNear = 0.05
        cam.zFar = 300
    }
}

/// 時刻に合わせて空の色・太陽や月・光・雪原を用意し、更新する。
final class SkyRig {
    private weak var scene: SCNScene?
    private let dome = SCNNode()
    private let domeMaterial = SCNMaterial()
    private let starNode = SCNNode()
    private let starMaterial = SCNMaterial()
    private let discNode = SCNNode()
    private let discMaterial = SCNMaterial()
    private let lightNode = SCNNode()
    private(set) var ground: SCNNode?
    private(set) var state = SkyState.at(hour: 12)

    init(scene: SCNScene, ground withGround: Bool, shadows: Bool) {
        self.scene = scene

        domeMaterial.lightingModel = .constant
        domeMaterial.diffuse.contents = UIColor.white
        domeMaterial.isDoubleSided = true
        domeMaterial.writesToDepthBuffer = false
        domeMaterial.readsFromDepthBuffer = false
        dome.renderingOrder = -100
        scene.rootNode.addChildNode(dome)

        starMaterial.lightingModel = .constant
        starMaterial.diffuse.contents = UIColor.white
        starMaterial.writesToDepthBuffer = false
        starMaterial.readsFromDepthBuffer = false
        starNode.geometry = SkyRig.starGeometry(material: starMaterial)
        starNode.renderingOrder = -90
        scene.rootNode.addChildNode(starNode)

        let discPlane = SCNPlane(width: 28, height: 28)
        discMaterial.lightingModel = .constant
        discMaterial.isDoubleSided = true
        discMaterial.writesToDepthBuffer = false
        discMaterial.readsFromDepthBuffer = false
        discPlane.materials = [discMaterial]
        discNode.geometry = discPlane
        discNode.renderingOrder = -80
        discNode.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(discNode)

        let light = SCNLight()
        light.type = .directional
        light.temperature = 6500
        if shadows {
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowRadius = 7
            light.shadowSampleCount = 8
            light.shadowColor = UIColor(red: 0.10, green: 0.16, blue: 0.32, alpha: 0.55)
            light.shadowMapSize = CGSize(width: 2048, height: 2048)
            light.automaticallyAdjustsShadowProjection = true
        }
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)

        if withGround {
            let plane = SCNPlane(width: 120, height: 120)
            let m = PBR.snow(tile: (60, 60))
            m.roughness.contents = 0.95
            m.emission.intensity = 0.03
            m.transparent.contents = SkyRig.groundMask
            m.transparencyMode = .aOne
            plane.materials = [m]
            let node = SCNNode(geometry: plane)
            node.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(node)
            ground = node
        }
        apply(hour: 12)
    }

    /// その時刻の空に切り替える。
    func apply(hour: Double) {
        let s = SkyState.at(hour: hour)
        state = s

        dome.geometry = SkyRig.domeGeometry(s, material: domeMaterial)
        starMaterial.transparency = CGFloat(s.stars)
        starNode.isHidden = s.stars < 0.02

        scene?.background.contents = SkyRig.uiColor(s.horizon)
        scene?.lightingEnvironment.contents = SkyRig.environmentImage(s)
        scene?.lightingEnvironment.intensity = CGFloat(s.ambient * 0.7)

        let light = lightNode.light
        light?.color = SkyRig.uiColor(s.lightColor)
        light?.intensity = CGFloat(s.lightIntensity)
        lightNode.simdPosition = s.lightDirection * 40
        lightNode.simdLook(at: .zero)

        discNode.simdPosition = s.lightDirection * 90
        discNode.isHidden = s.lightElevation < -0.05
        discNode.scale = s.isSun ? SCNVector3(1, 1, 1) : SCNVector3(0.55, 0.55, 0.55)
        discMaterial.diffuse.contents = SkyRig.glowImage(color: s.lightColor, isSun: s.isSun)
    }

    // MARK: 部品

    static func uiColor(_ c: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(min(1, max(0, c.x))), green: CGFloat(min(1, max(0, c.y))), blue: CGFloat(min(1, max(0, c.z))), alpha: 1)
    }

    /// 空のドーム（高さごとの色を頂点に持たせる）
    static func domeGeometry(_ s: SkyState, material: SCNMaterial) -> SCNGeometry {
        let rings = 28, segments = 32
        var vertices: [SCNVector3] = []
        var colors: [Float] = []
        for i in 0...rings {
            let e = Float.pi / 2 - Float(i) / Float(rings) * Float.pi
            let c = s.color(elevation: e) * 1.2
            for j in 0...segments {
                let a = Float(j) / Float(segments) * 2 * Float.pi
                let r: Float = 100
                vertices.append(SCNVector3(r * cos(e) * sin(a), r * sin(e), r * cos(e) * cos(a)))
                colors.append(contentsOf: [c.x, c.y, c.z, 1])
            }
        }
        var indices: [UInt32] = []
        let row = segments + 1
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i * row + j), b = UInt32((i + 1) * row + j)
                let c = UInt32(i * row + j + 1), d = UInt32((i + 1) * row + j + 1)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .color, vectorCount: vertices.count,
            usesFloatComponents: true, componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<Float>.size * 4
        )
        let geo = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices), colorSource],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        geo.materials = [material]
        return geo
    }

    /// 星（空の上半分に散らした点）
    static func starGeometry(material: SCNMaterial) -> SCNGeometry {
        var rng = SplitMix64(seed: 2026)
        var vertices: [SCNVector3] = []
        for _ in 0..<320 {
            let a = Float(rng.next() % 10_000) / 10_000 * 2 * Float.pi
            let e = asin(Float(rng.next() % 10_000) / 10_000 * 0.96 + 0.04)
            vertices.append(SCNVector3(98 * cos(e) * sin(a), 98 * sin(e), 98 * cos(e) * cos(a)))
        }
        let indices: [UInt32] = (0..<UInt32(vertices.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 2.2
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        geo.materials = [material]
        return geo
    }

    /// 全体を照らすための空の画像（上が空、下が雪原の照り返し）
    static func environmentImage(_ s: SkyState) -> UIImage {
        let size = CGSize(width: 128, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let steps = 16
            for n in 0..<steps {
                let v0 = Float(n) / Float(steps)
                let e = Float.pi / 2 - (v0 + 0.5 / Float(steps)) * Float.pi
                ctx.cgContext.setFillColor(uiColor(s.color(elevation: e)).cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: CGFloat(v0) * size.height, width: size.width, height: size.height / CGFloat(steps) + 1))
            }
        }
    }

    /// 太陽・月のにじんだ光
    static func glowImage(color c: SIMD3<Float>, isSun: Bool) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base = uiColor(c)
        let core: UIColor = isSun ? .white : UIColor(white: 0.96, alpha: 1)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [core.cgColor, core.cgColor, base.withAlphaComponent(0.45).cgColor, base.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.10, 0.28, 1]) else { return }
            let center = CGPoint(x: 64, y: 64)
            ctx.cgContext.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 64, options: [])
        }
    }

    /// 雪原の端をなめらかに空へ溶かす（中心が不透明、外が透明。アルファで表す）
    static let groundMask: UIImage = {
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.4, 0.97]) else { return }
            let center = CGPoint(x: 128, y: 128)
            ctx.cgContext.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: 128, options: [])
        }
    }()

    /// 足元のやわらかい影（雪玉の下に敷く）
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
            let colors = [UIColor(red: 0.10, green: 0.16, blue: 0.34, alpha: 0.55).cgColor,
                          UIColor(red: 0.10, green: 0.16, blue: 0.34, alpha: 0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 1]) else { return }
            let c = CGPoint(x: 64, y: 64)
            ctx.cgContext.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 64, options: [])
        }
    }()
}
