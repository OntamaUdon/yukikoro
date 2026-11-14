import SceneKit
import UIKit

/// アプリに入れた写真素材（CC0）の読み込み。見つからないときは nil を返し、単色の素材で代用する。
enum PhotoAssets {
    private static var images: [String: UIImage] = [:]

    static func path(_ name: String, _ ext: String) -> String? {
        Bundle.main.path(forResource: name, ofType: ext)
    }

    static func image(_ name: String, ext: String = "jpg") -> UIImage? {
        let key = name + "." + ext
        if let hit = images[key] { return hit }
        guard let p = path(name, ext), let image = UIImage(contentsOfFile: p) else { return nil }
        images[key] = image
        return image
    }

    static func hdr(_ name: String) -> URL? {
        path(name, "hdr").map { URL(fileURLWithPath: $0) }
    }

    /// 利用者が差し替えた背景写真（Resources/Photoreal/custom_background.jpg）があれば返す
    static func customBackground() -> UIImage? {
        image("custom_background") ?? image("custom_background", ext: "png")
    }
}

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
        case .night: return 0.12
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

/// 物理ベースの素材（PBR）をまとめて作る。
enum PBR {
    private static var tintedCache: [String: UIImage] = [:]

    private static func base() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.metalness.contents = 0.0
        return m
    }

    private static func tile(_ m: SCNMaterial, _ x: Float, _ y: Float) {
        let t = SCNMatrix4MakeScale(x, y, 1)
        for p in [m.diffuse, m.normal, m.roughness, m.ambientOcclusion] {
            p.contentsTransform = t
            p.wrapS = .repeat
            p.wrapT = .repeat
        }
    }

    /// 雪（写真素材の凹凸と粗さ、青白い影）
    static func snow(tile tiles: (Float, Float) = (1, 1)) -> SCNMaterial {
        let m = base()
        m.diffuse.contents = PhotoAssets.image("snow_albedo") ?? UIColor(white: 0.96, alpha: 1)
        m.normal.contents = PhotoAssets.image("snow_normal")
        m.normal.intensity = 0.9
        m.roughness.contents = PhotoAssets.image("snow_rough") ?? 0.9
        m.ambientOcclusion.contents = PhotoAssets.image("snow_ao")
        m.ambientOcclusion.intensity = 0.5
        // 雪の内側で光が散る感じ（影が真っ黒にならず、青白く透ける）
        m.emission.contents = UIColor(red: 0.30, green: 0.40, blue: 0.58, alpha: 1)
        m.emission.intensity = 0.14
        tile(m, tiles.0, tiles.1)
        return m
    }

    /// 木の枝（樹皮）
    static func bark() -> SCNMaterial {
        let m = base()
        m.diffuse.contents = PhotoAssets.image("bark_diffuse") ?? UIColor(red: 0.35, green: 0.26, blue: 0.18, alpha: 1)
        m.normal.contents = PhotoAssets.image("bark_normal")
        m.roughness.contents = PhotoAssets.image("bark_rough") ?? 0.9
        tile(m, 1, 2)
        return m
    }

    /// 毛糸・フリースの布。色は後から掛ける。
    static func fleece(_ color: UIColor) -> SCNMaterial {
        let m = base()
        if let luma = PhotoAssets.image("fleece_luma") {
            m.diffuse.contents = tinted(luma, color)
        } else {
            m.diffuse.contents = color
        }
        m.normal.contents = PhotoAssets.image("fleece_normal")
        m.normal.intensity = 1.0
        m.roughness.contents = PhotoAssets.image("fleece_rough") ?? 0.95
        tile(m, 3, 3)
        return m
    }

    private static func tinted(_ gray: UIImage, _ color: UIColor) -> UIImage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "%.2f-%.2f-%.2f", r, g, b)
        if let hit = tintedCache[key] { return hit }
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            gray.draw(in: CGRect(origin: .zero, size: size))
            ctx.cgContext.setBlendMode(.multiply)
            color.setFill()
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
        }
        tintedCache[key] = image
        return image
    }

    static func coal() -> SCNMaterial {
        let m = base()
        m.diffuse.contents = UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
        m.roughness.contents = 0.55
        m.normal.contents = PhotoAssets.image("snow_normal")
        m.normal.intensity = 1.2
        return m
    }

    /// つや消しのフェルト・布（くちばし・鼻など）
    static func felt(_ color: UIColor) -> SCNMaterial {
        let m = base()
        m.diffuse.contents = color
        m.roughness.contents = 0.9
        return m
    }

    static func plastic(_ color: UIColor, roughness: CGFloat = 0.3) -> SCNMaterial {
        let m = base()
        m.diffuse.contents = color
        m.roughness.contents = roughness
        return m
    }

    static func metal(_ color: UIColor, roughness: CGFloat = 0.3) -> SCNMaterial {
        let m = base()
        m.diffuse.contents = color
        m.metalness.contents = 1.0
        m.roughness.contents = roughness
        return m
    }

    static func carrot() -> SCNMaterial {
        let m = base()
        m.diffuse.contents = UIColor(red: 0.93, green: 0.42, blue: 0.08, alpha: 1)
        m.roughness.contents = 0.5
        m.normal.contents = PhotoAssets.image("bark_normal")
        m.normal.intensity = 0.35
        return m
    }

    /// 炭のように黒ずんだ雪（ペンギンの体）
    static func charcoal() -> SCNMaterial {
        let m = base()
        m.diffuse.contents = UIColor(red: 0.085, green: 0.09, blue: 0.115, alpha: 1)
        m.roughness.contents = 0.7
        m.normal.contents = PhotoAssets.image("snow_normal")
        m.normal.intensity = 0.7
        tile(m, 3, 2)
        return m
    }
}
