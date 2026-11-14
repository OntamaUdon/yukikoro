import SceneKit
import UIKit
import simd

/// 3 次元の値ノイズ（雪のでこぼこの形に使う）
enum SnowNoise {
    private static func hash(_ x: Int32, _ y: Int32, _ z: Int32, _ seed: UInt32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ UInt32(bitPattern: z) &* 2_147_483_647 &+ seed &* 1_274_126_177
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65_535 * 2 - 1
    }

    private static func smooth(_ t: Float) -> Float { t * t * (3 - 2 * t) }

    static func value(_ p: SIMD3<Float>, seed: UInt32) -> Float {
        let fx = floor(p.x), fy = floor(p.y), fz = floor(p.z)
        let ix = Int32(fx), iy = Int32(fy), iz = Int32(fz)
        let tx = smooth(p.x - fx), ty = smooth(p.y - fy), tz = smooth(p.z - fz)
        func corner(_ dx: Int32, _ dy: Int32, _ dz: Int32) -> Float { hash(ix + dx, iy + dy, iz + dz, seed) }
        let x00 = corner(0, 0, 0) * (1 - tx) + corner(1, 0, 0) * tx
        let x10 = corner(0, 1, 0) * (1 - tx) + corner(1, 1, 0) * tx
        let x01 = corner(0, 0, 1) * (1 - tx) + corner(1, 0, 1) * tx
        let x11 = corner(0, 1, 1) * (1 - tx) + corner(1, 1, 1) * tx
        let y0 = x00 * (1 - ty) + x10 * ty
        let y1 = x01 * (1 - ty) + x11 * ty
        return y0 * (1 - tz) + y1 * tz
    }

    /// 大小3段のノイズを重ねる（-1〜1 付近）
    static func fbm(_ p: SIMD3<Float>, seed: UInt32) -> Float {
        value(p, seed: seed) * 0.62 + value(p * 2.1, seed: seed &+ 7) * 0.28 + value(p * 4.3, seed: seed &+ 13) * 0.10
    }
}
