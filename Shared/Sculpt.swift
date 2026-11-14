import Foundation
import simd

/// 刃（ヘラ）の大きさ。縦の板の高さで、一度に削れる幅が変わる。
enum BladeSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    /// 刃の高さ（雪玉の大きさ＝直径約2 を基準とした長さ）
    var height: Float {
        switch self {
        case .small: return 0.45
        case .medium: return 1.0
        case .large: return 3.2
        }
    }
}

/// 雪玉の網目（緯度×経度の格子）。形の編集はこの格子の頂点ごとに行う。
enum SculptGrid {
    static let rings = 56
    static let segments = 112
    static let rowCount = segments + 1
    static let vertexCount = (rings + 1) * (segments + 1)

    static func index(_ i: Int, _ j: Int) -> Int { i * rowCount + j }

    /// 頂点ごとの向き（単位ベクトル）
    static let directions: [SIMD3<Float>] = {
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(vertexCount)
        for i in 0...rings {
            let theta = Float(i) / Float(rings) * .pi
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                out.append(SIMD3<Float>(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi)))
            }
        }
        return out
    }()
}

/// 雪玉の形と色。半径1の球を基準に、頂点ごとの半径の倍率を持つ。色は雪玉ぜんたいで1色。
struct SnowShape: Equatable, Hashable {
    var seed: UInt32
    /// 頂点ごとの半径の倍率（1 が元の球の大きさ）
    var radii: [Float]
    /// 雪玉の色（RGB。255,255,255 が白）
    var tint: [UInt8]

    static let minRadius: Float = 0.05
    static let maxRadius: Float = 2.5
    /// 刃は、中心からこれより近くには入れない（雪玉が消えてしまわないように）
    static let minCutDepth: Float = 0.2

    /// 手を加える前の、すこしでこぼこした白い雪玉
    static func pristine(seed: UInt32) -> SnowShape {
        let dirs = SculptGrid.directions
        let small = Float(seed % 1024)
        let offset = SIMD3<Float>(small * 3.1, small * 1.7, small * 0.9)
        var radii = [Float](repeating: 1, count: dirs.count)
        for k in 0..<dirs.count {
            radii[k] = 1 + 0.06 * SnowNoise.fbm(dirs[k] * 1.4 + offset, seed: seed)
        }
        return SnowShape(seed: seed, radii: radii, tint: [255, 255, 255])
    }

    /// 手を加えたか（色か形が元と違うか）
    var isModified: Bool { self != SnowShape.pristine(seed: seed) }

    /// いちばん遠い所までの半径（基準の半径に対する倍率）
    var maxExtent: Float { radii.max() ?? 1 }

    /// 雪玉の色
    var tintRGB: SIMD3<Float> {
        guard tint.count == 3 else { return SIMD3<Float>(repeating: 1) }
        return SIMD3<Float>(Float(tint[0]), Float(tint[1]), Float(tint[2])) / 255
    }

    mutating func setTint(_ rgb: SIMD3<Float>) {
        tint = [0, 1, 2].map { UInt8(max(0, min(255, (rgb[$0] * 255).rounded()))) }
    }

    // MARK: 刃で削る

    /// 刃で削る。刃は地面に垂直な板で、画面の横方向（x）に `planeX` の位置にあり、
    /// 高さは `bandLow`〜`bandHigh`、奥行きは雪玉の端まで。
    /// 雪玉は `rotation` だけ回っている（形はその回転を含めて、画面の座標で刃と交わる）。
    /// 刃が通った側（刃より外側）の雪が、刃の面ぴったりまで取り除かれる。
    /// 刃は x<0（左側）から入る。中心を含む側が残るので、半径の倍率だけで形を表せる。
    /// - Returns: 形が変わったか
    @discardableResult
    mutating func cutBlade(rotation: simd_quatf, planeX: Float, bandLow y0: Float, bandHigh y1: Float) -> Bool {
        guard y1 > y0 else { return false }
        let a = max(SnowShape.minCutDepth, abs(planeX))
        let s: Float = planeX < 0 ? -1 : 1
        let dirs = SculptGrid.directions
        var changed = false
        for k in 0..<dirs.count {
            let dw = rotation.act(dirs[k])
            let dx = s * dw.x
            guard dx > 1e-4 else { continue }
            let r = radii[k]
            let rx = a / dx
            guard r > rx else { continue }
            // 今の表面が、刃の高さの範囲に入っているか
            let py = r * dw.y
            guard py >= y0, py <= y1 else { continue }
            // その向きの線が、刃の高さの範囲に入る所までの距離（上面・下面で平らに切れる）
            var lower: Float = 0
            if abs(dw.y) > 1e-5 {
                lower = max(0, min(y0 / dw.y, y1 / dw.y))
            }
            let newR = max(SnowShape.minRadius, max(rx, lower))
            if newR < r - 1e-6 {
                radii[k] = newR
                changed = true
            }
        }
        return changed
    }

    // MARK: 成長

    /// 雪が積もって一回り大きくなる。今の形のまま、どこも同じ厚さで外側に増える。
    /// 形は「基準の半径に対する倍率」なので、実際の長さに直して厚みを足し、新しい基準で割り直す。
    mutating func grow(fromRadius old: Float, toRadius new: Float) {
        guard new > old, old > 0 else { return }
        let thickness = new - old
        for k in 0..<radii.count {
            radii[k] = min(SnowShape.maxRadius, (old * radii[k] + thickness) / new)
        }
    }
}

extension SnowShape: Codable {
    private enum CodingKeys: String, CodingKey { case seed, radii, tint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seed = try c.decode(UInt32.self, forKey: .seed)
        let rData = try c.decode(Data.self, forKey: .radii)
        var radii = [Float](repeating: 1, count: rData.count / MemoryLayout<Float>.size)
        radii.withUnsafeMutableBytes { _ = rData.copyBytes(to: $0) }
        var tint = [UInt8](repeating: 255, count: 3)
        if let tData = try c.decodeIfPresent(Data.self, forKey: .tint), tData.count == 3 { tint = [UInt8](tData) }
        if radii.count == SculptGrid.vertexCount {
            self.init(seed: seed, radii: radii, tint: tint)
        } else {
            self = SnowShape.pristine(seed: seed)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(radii.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .radii)
        try c.encode(Data(tint), forKey: .tint)
    }
}
