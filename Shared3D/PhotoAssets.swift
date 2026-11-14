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
}

/// 物理ベースの素材（PBR）をまとめて作る。
enum PBR {
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
}
