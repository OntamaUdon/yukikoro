import SceneKit
import UIKit
import simd

extension MeshBuilder {
    /// 向きのわかっている四角形
    mutating func face(_ e: Int, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, normal n: SIMD3<Float>) {
        quad(e, (a, n), (b, n), (c, n), (d, n))
    }

    /// 直方体（下の面はつくらない。上の面だけ別の材料にもできる）
    mutating func box(_ e: Int, lo: SIMD3<Float>, hi: SIMD3<Float>, top: Int? = nil) {
        let (x0, y0, z0) = (lo.x, lo.y, lo.z)
        let (x1, y1, z1) = (hi.x, hi.y, hi.z)
        face(e, SIMD3(x1, y0, z0), SIMD3(x1, y0, z1), SIMD3(x1, y1, z1), SIMD3(x1, y1, z0), normal: SIMD3(1, 0, 0))
        face(e, SIMD3(x0, y0, z1), SIMD3(x0, y0, z0), SIMD3(x0, y1, z0), SIMD3(x0, y1, z1), normal: SIMD3(-1, 0, 0))
        face(top ?? e, SIMD3(x0, y1, z0), SIMD3(x1, y1, z0), SIMD3(x1, y1, z1), SIMD3(x0, y1, z1), normal: SIMD3(0, 1, 0))
        face(e, SIMD3(x1, y0, z1), SIMD3(x0, y0, z1), SIMD3(x0, y1, z1), SIMD3(x1, y1, z1), normal: SIMD3(0, 0, 1))
        face(e, SIMD3(x0, y0, z0), SIMD3(x1, y0, z0), SIMD3(x1, y1, z0), SIMD3(x0, y1, z0), normal: SIMD3(0, 0, -1))
    }

    /// 壁にはりつく小さな四角（まど）。`normal` は壁の外向き。
    mutating func pane(_ e: Int, center: SIMD3<Float>, width w: Float, height h: Float, normal n: SIMD3<Float>) {
        let u: SIMD3<Float> = abs(n.x) > 0.5 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        let v = SIMD3<Float>(0, 1, 0)
        let c = center + n * 0.03
        face(e, c - u * (w / 2) - v * (h / 2), c + u * (w / 2) - v * (h / 2),
             c + u * (w / 2) + v * (h / 2), c - u * (w / 2) + v * (h / 2), normal: n)
    }
}

/// 道の両側に立つ物の形（木いがい）。どれも、7 の間隔で並べたとき、ちょうど入るくらいの大きさ。
enum StageObjects {
    /// 面の番号: 0 かべ, 1 かざり（屋根・タイヤ・暗いところ）, 2 雪, 3 金の電球, 4 氷の電球, 5 まど
    static let elementCount = 6

    /// 道のはしから、物の中心までの距離（1 段目の大きさで）
    static func offset(_ kind: LaneKind) -> Double {
        switch kind {
        case .tree: return 1.7
        case .pole: return 1.3
        case .car: return 1.8
        case .house: return 3.4
        case .building: return 3.8
        case .mountain: return 6.0
        case .range: return 8.0
        }
    }

    /// 道をまたぐ光のアーチ（高さ・たるみ）。ないときは nil。
    static func arch(_ kind: LaneKind) -> (height: Double, sag: Double)? {
        switch kind {
        case .tree: return (6.4, 1.1)
        case .pole: return (7.8, 1.0)
        case .house: return (5.2, 0.8)
        case .building: return (12.5, 1.2)
        case .car, .mountain, .range: return nil
        }
    }

    static func geometry(kind: LaneKind, seed: UInt64, materials: [SCNMaterial]) -> SCNGeometry {
        var generator = SplitMix64(seed: seed)
        func random() -> Float { Float(generator.next() % 10_000) / 10_000 }
        var mesh = MeshBuilder(elementCount: elementCount)
        switch kind {
        case .tree: break
        case .pole: pole(&mesh)
        case .car: car(&mesh, random: random)
        case .house: house(&mesh, random: random)
        case .building: building(&mesh, random: random)
        case .mountain: mountain(&mesh, height: 12, radius: 4.4, peaks: [(0, 0, 1)], random: random)
        case .range: mountain(&mesh, height: 17, radius: 5.2, peaks: [(0, -1.6, 1), (0, 2.2, 0.72)], random: random)
        }
        return mesh.geometry(materials: materials)
    }

    // MARK: でんしんばしら（街灯つき）

    private static func pole(_ mesh: inout MeshBuilder) {
        let sides = 8
        let ringY: [Float] = [0, 4, 8.4]
        let ringR: [Float] = [0.26, 0.2, 0.13]
        for j in 0..<2 {
            for i in 0..<sides {
                let a0 = Float(i) / Float(sides) * 2 * .pi
                let a1 = Float(i + 1) / Float(sides) * 2 * .pi
                let d0 = SIMD3<Float>(cos(a0), 0, sin(a0)), d1 = SIMD3<Float>(cos(a1), 0, sin(a1))
                mesh.quad(0, (d0 * ringR[j] + SIMD3(0, ringY[j], 0), d0), (d1 * ringR[j] + SIMD3(0, ringY[j], 0), d1),
                          (d1 * ringR[j + 1] + SIMD3(0, ringY[j + 1], 0), d1), (d0 * ringR[j + 1] + SIMD3(0, ringY[j + 1], 0), d0))
            }
        }
        // 腕木と、がいし
        mesh.box(1, lo: SIMD3(-1.5, 7.5, -0.09), hi: SIMD3(1.5, 7.68, 0.09), top: 2)
        mesh.box(1, lo: SIMD3(-1.0, 6.5, -0.07), hi: SIMD3(1.0, 6.66, 0.07), top: 2)
        for x: Float in [-1.4, -0.7, 0.7, 1.4] {
            mesh.box(5, lo: SIMD3(x - 0.07, 7.68, -0.07), hi: SIMD3(x + 0.07, 7.9, 0.07))
        }
        // 街灯（てっぺんのあかり）
        mesh.box(1, lo: SIMD3(-0.28, 8.4, -0.28), hi: SIMD3(0.28, 8.52, 0.28), top: 2)
        mesh.bulb(3, center: SIMD3(0, 8.78, 0), size: 0.3)
        for sign: Float in [-1, 1] {
            mesh.bulb(3, center: SIMD3(sign * 1.4, 7.42, 0), size: 0.12)
        }
        // 電線にそって、次の柱までわたす光の列
        for j in 0...14 {
            let z = Float(j) / 14 * 7
            let sag = 0.8 * sin(Float.pi * z / 7)
            for x: Float in [-1.4, 1.4] {
                mesh.bulb(j % 5 == 2 ? 4 : 3, center: SIMD3(x, 7.7 - sag, z), size: 0.05)
            }
            if j % 2 == 0 {
                mesh.bulb(3, center: SIMD3(0, 6.7 - sag * 0.9, z), size: 0.045)
            }
        }
    }

    // MARK: くるま

    private static func car(_ mesh: inout MeshBuilder, random: () -> Float) {
        // 長いほうが z。車体と屋根の雪
        mesh.box(0, lo: SIMD3(-1.25, 0.55, -2.8), hi: SIMD3(1.25, 1.65, 2.8))
        mesh.box(0, lo: SIMD3(-1.05, 1.65, -1.2), hi: SIMD3(1.05, 2.55, 1.9), top: 2)
        mesh.box(2, lo: SIMD3(-1.0, 2.55, -1.15), hi: SIMD3(1.0, 2.68, 1.85))
        // まど（夜は室内灯）
        for side: Float in [-1, 1] {
            mesh.pane(5, center: SIMD3(side * 1.05, 2.1, 0.35), width: 2.4, height: 0.6, normal: SIMD3(side, 0, 0))
        }
        mesh.pane(5, center: SIMD3(0, 2.1, -1.2), width: 1.7, height: 0.6, normal: SIMD3(0, 0, -1))
        mesh.pane(5, center: SIMD3(0, 2.1, 1.9), width: 1.7, height: 0.6, normal: SIMD3(0, 0, 1))
        // タイヤ
        for sx: Float in [-1, 1] {
            for z: Float in [-1.7, 1.7] {
                mesh.box(1, lo: SIMD3(sx * 1.25 - 0.18, 0, z - 0.5), hi: SIMD3(sx * 1.25 + 0.18, 0.95, z + 0.5))
            }
        }
        // ライト（まえとうしろ）
        for sx: Float in [-0.75, 0.75] {
            mesh.bulb(3, center: SIMD3(sx, 1.1, 2.86), size: 0.2)
            mesh.bulb(4, center: SIMD3(sx, 1.1, -2.86), size: 0.14)
        }
        // 屋根のかざり電球
        for k in 0..<5 {
            mesh.bulb(k % 2 == 0 ? 3 : 4, center: SIMD3(-0.8 + Float(k) * 0.4, 2.8, 0.35), size: 0.07)
        }
    }

    // MARK: いえ

    private static func house(_ mesh: inout MeshBuilder, random: () -> Float) {
        let halfX: Float = 2.6, halfZ: Float = 2.6, wall: Float = 3.2, peak: Float = 5.6
        mesh.box(0, lo: SIMD3(-halfX, 0, -halfZ), hi: SIMD3(halfX, wall, halfZ))
        // 屋根（棟は z のほう）。雪をその上にのせる。
        let eave: Float = 0.45
        let leftLow = SIMD3<Float>(-halfX - eave, wall - 0.1, 0)
        let rightLow = SIMD3<Float>(halfX + eave, wall - 0.1, 0)
        let ridge = SIMD3<Float>(0, peak, 0)
        let zf = halfZ + eave
        let nLeft = simd_normalize(SIMD3<Float>(-(peak - wall), halfX + eave, 0))
        let nRight = simd_normalize(SIMD3<Float>(peak - wall, halfX + eave, 0))
        mesh.face(1, leftLow + SIMD3(0, 0, -zf), ridge + SIMD3(0, 0, -zf), ridge + SIMD3(0, 0, zf), leftLow + SIMD3(0, 0, zf), normal: nLeft)
        mesh.face(1, rightLow + SIMD3(0, 0, -zf), ridge + SIMD3(0, 0, -zf), ridge + SIMD3(0, 0, zf), rightLow + SIMD3(0, 0, zf), normal: nRight)
        let lift = SIMD3<Float>(0, 0.1, 0)
        mesh.face(2, leftLow + lift + SIMD3(0, 0, -zf), ridge + lift + SIMD3(0, 0, -zf), ridge + lift + SIMD3(0, 0, zf), leftLow + lift + SIMD3(0, 0, zf), normal: nLeft)
        mesh.face(2, rightLow + lift + SIMD3(0, 0, -zf), ridge + lift + SIMD3(0, 0, -zf), ridge + lift + SIMD3(0, 0, zf), rightLow + lift + SIMD3(0, 0, zf), normal: nRight)
        // 妻側の三角
        for sign: Float in [-1, 1] {
            let z = sign * halfZ
            mesh.triangle(0, (SIMD3(-halfX, wall, z), SIMD3(0, 0, sign)), (SIMD3(halfX, wall, z), SIMD3(0, 0, sign)), (SIMD3(0, peak - 0.05, z), SIMD3(0, 0, sign)))
        }
        // えんとつ
        mesh.box(1, lo: SIMD3(0.9, wall + 0.6, 0.8), hi: SIMD3(1.5, peak + 0.5, 1.4), top: 2)
        // まど（夜は明かり）とドア
        for sx: Float in [-1, 1] {
            for z: Float in [-1.4, 1.4] {
                mesh.pane(5, center: SIMD3(sx * halfX, 1.9, z), width: 1.0, height: 1.0, normal: SIMD3(sx, 0, 0))
            }
            mesh.pane(5, center: SIMD3(sx * halfX, 1.0, 0), width: 0.9, height: 2.0, normal: SIMD3(sx, 0, 0))
            mesh.bulb(3, center: SIMD3(sx * (halfX + 0.25), 2.55, 0), size: 0.16)
        }
        for sz: Float in [-1, 1] {
            mesh.pane(5, center: SIMD3(-1.2, 1.9, sz * halfZ), width: 1.0, height: 1.0, normal: SIMD3(0, 0, sz))
            mesh.pane(5, center: SIMD3(1.2, 1.9, sz * halfZ), width: 1.0, height: 1.0, normal: SIMD3(0, 0, sz))
        }
        // 軒に、小さな電球を並べる
        for j in 0...8 {
            let z = -zf + Float(j) / 8 * 2 * zf
            for sx: Float in [-1, 1] {
                mesh.bulb(j % 3 == 1 ? 4 : 3, center: SIMD3(sx * (halfX + eave), wall - 0.15, z), size: 0.06)
            }
        }
    }

    // MARK: ビル

    private static func building(_ mesh: inout MeshBuilder, random: () -> Float) {
        let halfX: Float = 2.6, halfZ: Float = 2.9, height: Float = 13
        mesh.box(0, lo: SIMD3(-halfX, 0, -halfZ), hi: SIMD3(halfX, height, halfZ), top: 2)
        // 屋上のへりと機械室
        mesh.box(1, lo: SIMD3(-halfX - 0.1, height - 0.1, -halfZ - 0.1), hi: SIMD3(halfX + 0.1, height + 0.2, halfZ + 0.1), top: 2)
        mesh.box(1, lo: SIMD3(-1.0, height + 0.2, -1.0), hi: SIMD3(1.0, height + 1.2, 1.0), top: 2)
        // まどのならび（ついている部屋は、ばらばら）
        let rows = 9
        for row in 0..<rows {
            let y = 1.6 + Float(row) * 1.25
            for col in 0..<3 {
                let z = (Float(col) - 1) * 1.7
                for sx: Float in [-1, 1] {
                    if random() < 0.8 {
                        mesh.pane(5, center: SIMD3(sx * halfX, y, z), width: 1.0, height: 0.7, normal: SIMD3(sx, 0, 0))
                    }
                }
            }
            for col in 0..<2 {
                let x = (Float(col) - 0.5) * 2.4
                for sz: Float in [-1, 1] {
                    if random() < 0.8 {
                        mesh.pane(5, center: SIMD3(x, y, sz * halfZ), width: 1.0, height: 0.7, normal: SIMD3(0, 0, sz))
                    }
                }
            }
        }
        // かどに、上までのびる光の列
        for sx: Float in [-1, 1] {
            for sz: Float in [-1, 1] {
                for j in 0...12 {
                    mesh.bulb(j % 4 == 2 ? 4 : 3, center: SIMD3(sx * (halfX + 0.08), 0.6 + Float(j), sz * (halfZ + 0.08)), size: 0.07)
                }
            }
        }
        mesh.bulb(3, center: SIMD3(0, height + 1.5, 0), size: 0.24)
    }

    // MARK: やま

    private static func mountain(_ mesh: inout MeshBuilder, height: Float, radius: Float,
                                 peaks: [(x: Float, z: Float, scale: Float)], random: () -> Float) {
        let sides = 10
        // 高さの段ごとの、すそからの半径の割合。上のほうが雪。
        let levels: [(t: Float, r: Float)] = [(0, 1.0), (0.3, 0.66), (0.6, 0.36), (1.0, 0.0)]
        for peak in peaks {
            var ring: [[SIMD3<Float>]] = []
            for level in levels {
                var points: [SIMD3<Float>] = []
                for i in 0..<sides {
                    let a = Float(i) / Float(sides) * 2 * .pi
                    let jitter = 0.86 + random() * 0.28
                    let rr = radius * peak.scale * level.r * (level.t == 0 ? 1 : jitter)
                    let yy = height * peak.scale * level.t * (level.t == 1 ? 1 : 0.94 + random() * 0.12)
                    points.append(SIMD3(peak.x + cos(a) * rr, yy, peak.z + sin(a) * rr))
                }
                ring.append(points)
            }
            for k in 0..<(levels.count - 1) {
                for i in 0..<sides {
                    let j = (i + 1) % sides
                    let element = levels[k].t >= 0.6 ? 2 : (levels[k].t >= 0.3 ? 0 : 0)
                    let a = ring[k][i], b = ring[k][j], c = ring[k + 1][j], d = ring[k + 1][i]
                    let n = simd_normalize(simd_cross(b - a, d - a))
                    let outward = SIMD3<Float>(a.x - peak.x, 0.6, a.z - peak.z)
                    let facing = simd_dot(n, outward) < 0 ? -n : n
                    // 一番上の段は三角になる
                    if levels[k + 1].r == 0 {
                        mesh.triangle(element, (a, facing), (b, facing), (c, facing))
                    } else {
                        mesh.quad(element, (a, facing), (b, facing), (c, facing), (d, facing))
                    }
                }
            }
            // ふもとのあかり（山小屋）と、山頂の星
            for i in stride(from: 0, to: sides, by: 2) {
                let p = ring[0][i] * 0.7 + ring[1][i] * 0.3
                mesh.bulb(3, center: p + SIMD3(0, 0.15, 0), size: 0.22)
            }
            mesh.bulb(3, center: SIMD3(peak.x, height * peak.scale + 0.3, peak.z), size: 0.3)
        }
    }
}
