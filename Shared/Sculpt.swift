import Foundation
import simd

/// 雪玉の輪郭（横から見た形）と色。中心からの距離を、角度ごとの「基準の半径に対する倍率」で持つ。
/// 色は雪玉ぜんたいで1色。
struct SnowShape: Equatable, Hashable {
    var seed: UInt32
    /// 角度ごとの半径の倍率（1 が元の円の大きさ）
    var radii: [Float]
    /// 雪玉の色（RGB。255,255,255 が白）
    var tint: [UInt8]

    static let pointCount = 180
    static let minRadius: Float = 0.05
    static let maxRadius: Float = 2.5
    /// 切る線は、中心からこれより近くには入れない（雪玉が消えてしまわないように）
    static let minCutDepth: Float = 0.2

    /// 角度ごとの向き（x が右、y が上。0 番は右向きで、反時計回り）
    static let directions: [SIMD2<Float>] = (0..<pointCount).map { k -> SIMD2<Float> in
        let a = Float(k) / Float(pointCount) * 2 * Float.pi
        return SIMD2<Float>(cos(a), sin(a))
    }

    /// 手を加える前の、すこしでこぼこした白い雪玉
    static func pristine(seed: UInt32) -> SnowShape {
        let p1 = Float(seed % 97) * 0.37
        let p2 = Float((seed / 97) % 89) * 0.41
        let p3 = Float((seed / 8_633) % 83) * 0.53
        var radii = [Float](repeating: 1, count: pointCount)
        for k in 0..<pointCount {
            let a = Float(k) / Float(pointCount) * 2 * Float.pi
            radii[k] = 1 + 0.035 * sin(3 * a + p1) + 0.02 * sin(5 * a + p2) + 0.012 * sin(9 * a + p3)
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

    /// 雪玉を `angle`（ラジアン。反時計回り）だけ回したときの、角度ごとの向き
    static func rotated(_ k: Int, by angle: Float) -> SIMD2<Float> {
        let d = directions[k]
        let c = cos(angle), s = sin(angle)
        return SIMD2<Float>(d.x * c - d.y * s, d.x * s + d.y * c)
    }

    // MARK: 線で切る

    /// 直線で切り落とす。`normal`（単位ベクトル）の向きの側、つまり `normal · p > depth` の側を取り除く。
    /// 取り除く側は中心を含まないので、残った形は中心から見て必ず見渡せる（半径の倍率だけで表せる）。
    /// - Returns: 形が変わったか
    @discardableResult
    mutating func cutLine(normal n: SIMD2<Float>, depth rawDepth: Float) -> Bool {
        let depth = max(SnowShape.minCutDepth, rawDepth)
        var changed = false
        for k in 0..<radii.count {
            let dn = simd_dot(SnowShape.directions[k], n)
            guard dn > 1e-4 else { continue }
            let limit = depth / dn
            if radii[k] > limit {
                radii[k] = max(SnowShape.minRadius, limit)
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
        if radii.count == SnowShape.pointCount {
            self.init(seed: seed, radii: radii, tint: tint)
        } else {
            // 以前の形式（3D）のデータは、まっさらな玉にする
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

/// 指でなぞった線で雪玉を切る。
/// 画面の座標は「雪玉の中心が原点、右が x、上が y、基準の半径が 1」の長さで渡す。
enum LineCut {
    struct Result {
        /// 切ったあとの形
        var shape: SnowShape
        /// 切り落とされる破片の輪郭（雪玉の座標。回転前）
        var fragment: [SIMD2<Float>]
    }

    /// これより短いなぞりは、切らない
    static let minLength: Float = 0.25

    /// `a` から `b` までなぞった線で、雪玉を切る。切れなければ nil。
    /// 切り落とすのは、中心がない側。線が中心のすぐそばを通るときは、中心の手前（深さ 0.2）で止める。
    static func apply(to shape: SnowShape, angle: Float, from a: SIMD2<Float>, to b: SIMD2<Float>) -> Result? {
        let length = simd_length(b - a)
        guard length >= minLength else { return nil }
        // 雪玉の座標（回転前）に直す
        let c = cos(-angle), s = sin(-angle)
        func local(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(p.x * c - p.y * s, p.x * s + p.y * c) }
        let la = local(a), lb = local(b)
        let dir = (lb - la) / length
        var normal = SIMD2<Float>(-dir.y, dir.x)
        var depth = simd_dot(normal, la)
        if depth < 0 {
            normal = -normal
            depth = -depth
        }
        depth = max(SnowShape.minCutDepth, depth)

        var next = shape
        guard next.cutLine(normal: normal, depth: depth) else { return nil }

        // 切り落とされる破片: 元の輪郭の弧と、切り口の線で囲まれた形
        let n = shape.radii.count
        let changed = (0..<n).filter { next.radii[$0] < shape.radii[$0] - 1e-6 }
        guard !changed.isEmpty else { return nil }
        let set = Set(changed)
        let start = changed.first { !set.contains(($0 - 1 + n) % n) } ?? changed[0]
        var ordered: [Int] = []
        var k = start
        while set.contains(k), ordered.count < n {
            ordered.append(k)
            k = (k + 1) % n
        }
        let outer = ordered.map { SnowShape.directions[$0] * shape.radii[$0] }
        let inner = ordered.reversed().map { SnowShape.directions[$0] * next.radii[$0] }
        return Result(shape: next, fragment: outer + inner)
    }
}

/// 元に戻すための履歴
struct ShapeHistory {
    private(set) var stack: [SnowShape] = []
    static let limit = 25

    var count: Int { stack.count }
    var canUndo: Bool { !stack.isEmpty }

    mutating func push(_ shape: SnowShape) {
        stack.append(shape)
        if stack.count > Self.limit { stack.removeFirst() }
    }

    mutating func pop() -> SnowShape? { stack.popLast() }
    mutating func clear() { stack.removeAll() }
}
