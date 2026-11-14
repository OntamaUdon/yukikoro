import Foundation
import simd

/// 雪玉を整える道具
enum SculptTool: String, CaseIterable, Identifiable {
    case rotate, carve, add, smooth, flatten, paint
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rotate: return "まわす"
        case .carve: return "けずる"
        case .add: return "もる"
        case .smooth: return "ならす"
        case .flatten: return "たいらに"
        case .paint: return "ぬる"
        }
    }

    var symbol: String {
        switch self {
        case .rotate: return "rotate.3d"
        case .carve: return "scissors"
        case .add: return "plus.circle"
        case .smooth: return "water.waves"
        case .flatten: return "rectangle.compress.vertical"
        case .paint: return "paintbrush.pointed"
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

    /// 隣り合う頂点（継ぎ目は反対側につなぐ）
    static func neighbors(_ i: Int, _ j: Int) -> [Int] {
        let jj = j % segments
        let jm = (jj + segments - 1) % segments
        let jp = (jj + 1) % segments
        var out = [index(i, jm), index(i, jp)]
        if i > 0 { out.append(index(i - 1, jj)) }
        if i < rings { out.append(index(i + 1, jj)) }
        return out
    }
}

/// 雪玉の形と色。半径1の球を基準に、頂点ごとの半径の倍率と色を持つ。
struct SnowShape: Equatable, Hashable {
    var seed: UInt32
    /// 頂点ごとの半径の倍率（1 が元の球の大きさ）
    var radii: [Float]
    /// 頂点ごとの色（RGB、255 が白）
    var colors: [UInt8]

    static let minRadius: Float = 0.3
    static let maxRadius: Float = 1.6

    /// 手を加える前の、すこしでこぼこした雪玉
    static func pristine(seed: UInt32) -> SnowShape {
        let dirs = SculptGrid.directions
        let small = Float(seed % 1024)
        let offset = SIMD3<Float>(small * 3.1, small * 1.7, small * 0.9)
        var radii = [Float](repeating: 1, count: dirs.count)
        for k in 0..<dirs.count {
            radii[k] = 1 + 0.06 * SnowNoise.fbm(dirs[k] * 1.4 + offset, seed: seed)
        }
        return SnowShape(seed: seed, radii: radii, colors: [UInt8](repeating: 255, count: dirs.count * 3))
    }

    /// 手を加えたか（色か形が元と違うか）
    var isModified: Bool { self != SnowShape.pristine(seed: seed) }

    // MARK: 道具

    /// 道具を1回あてる。
    /// - Parameters:
    ///   - direction: 当てた場所の向き（単位ベクトル）
    ///   - size: 道具の大きさ（単位球上の距離。0.1〜0.7）
    ///   - strength: 強さ（1 が標準）
    ///   - color: 「ぬる」の色（0〜1）
    ///   - plane: 「たいらに」で使う平面（法線の向きと、中心からの深さ）
    mutating func apply(tool: SculptTool, direction dir: SIMD3<Float>, size: Float, strength: Float,
                        color: SIMD3<Float> = SIMD3<Float>(repeating: 1),
                        plane: (normal: SIMD3<Float>, depth: Float)? = nil) {
        guard tool != .rotate, size > 0 else { return }
        let dirs = SculptGrid.directions
        let size2 = size * size
        let old = tool == .smooth ? radii : []

        for i in 0...SculptGrid.rings {
            for j in 0...SculptGrid.segments {
                let k = SculptGrid.index(i, j)
                let d2 = simd_length_squared(dirs[k] - dir)
                if d2 >= size2 { continue }
                let t = 1 - d2 / size2
                let w = t * t
                switch tool {
                case .carve:
                    radii[k] = max(SnowShape.minRadius, radii[k] - 0.012 * strength * w)
                case .add:
                    radii[k] = min(SnowShape.maxRadius, radii[k] + 0.010 * strength * w)
                case .smooth:
                    let ns = SculptGrid.neighbors(i, j)
                    var sum: Float = 0
                    for n in ns { sum += old[n] }
                    let avg = sum / Float(ns.count)
                    radii[k] = old[k] + (avg - old[k]) * min(1, 0.7 * strength * w)
                case .flatten:
                    guard let plane else { break }
                    let dn = simd_dot(dirs[k], plane.normal)
                    if dn > 0.05 {
                        let limit = plane.depth / dn
                        if radii[k] > limit {
                            radii[k] = max(SnowShape.minRadius, radii[k] + (limit - radii[k]) * min(1, 1.5 * w))
                        }
                    }
                case .paint:
                    let a = min(1, 0.10 * strength * w)
                    for c in 0..<3 {
                        let cur = Float(colors[k * 3 + c])
                        colors[k * 3 + c] = UInt8(max(0, min(255, cur + (color[c] * 255 - cur) * a)))
                    }
                case .rotate:
                    break
                }
            }
        }
    }
}

extension SnowShape: Codable {
    private enum CodingKeys: String, CodingKey { case seed, radii, colors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let seed = try c.decode(UInt32.self, forKey: .seed)
        let rData = try c.decode(Data.self, forKey: .radii)
        let cData = try c.decode(Data.self, forKey: .colors)
        var radii = [Float](repeating: 1, count: rData.count / MemoryLayout<Float>.size)
        radii.withUnsafeMutableBytes { _ = rData.copyBytes(to: $0) }
        let colors = [UInt8](cData)
        if radii.count == SculptGrid.vertexCount, colors.count == SculptGrid.vertexCount * 3 {
            self.init(seed: seed, radii: radii, colors: colors)
        } else {
            self = SnowShape.pristine(seed: seed)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seed, forKey: .seed)
        try c.encode(radii.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: .radii)
        try c.encode(Data(colors), forKey: .colors)
    }
}
