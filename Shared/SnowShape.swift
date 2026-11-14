import Foundation
import simd

/// 雪玉の輪郭（横から見た、すこしでこぼこした円）。中心からの距離を、角度ごとの「基準の半径に対する倍率」で持つ。
struct SnowShape: Equatable, Hashable {
    var seed: UInt32
    /// 角度ごとの半径の倍率（1 が元の円の大きさ）
    var radii: [Float]

    static let pointCount = 180

    /// 角度ごとの向き（x が右、y が上。0 番は右向きで、反時計回り）
    static let directions: [SIMD2<Float>] = (0..<pointCount).map { k -> SIMD2<Float> in
        let a = Float(k) / Float(pointCount) * 2 * Float.pi
        return SIMD2<Float>(cos(a), sin(a))
    }

    /// すこしでこぼこした雪玉
    static func pristine(seed: UInt32) -> SnowShape {
        let p1 = Float(seed % 97) * 0.37
        let p2 = Float((seed / 97) % 89) * 0.41
        let p3 = Float((seed / 8_633) % 83) * 0.53
        var radii = [Float](repeating: 1, count: pointCount)
        for k in 0..<pointCount {
            let a = Float(k) / Float(pointCount) * 2 * Float.pi
            radii[k] = 1 + 0.035 * sin(3 * a + p1) + 0.02 * sin(5 * a + p2) + 0.012 * sin(9 * a + p3)
        }
        return SnowShape(seed: seed, radii: radii)
    }

    /// いちばん遠い所までの半径（基準の半径に対する倍率）
    var maxExtent: Float { radii.max() ?? 1 }

    /// 雪玉の色（いまは白だけ）
    var tintRGB: SIMD3<Float> { SIMD3<Float>(repeating: 1) }

    /// 雪玉を `angle`（ラジアン。反時計回り）だけ回したときの、角度ごとの向き
    static func rotated(_ k: Int, by angle: Float) -> SIMD2<Float> {
        let d = directions[k]
        let c = cos(angle), s = sin(angle)
        return SIMD2<Float>(d.x * c - d.y * s, d.x * s + d.y * c)
    }
}
