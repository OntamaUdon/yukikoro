#if DEBUG
import SwiftUI
import simd

/// 起動引数で画面の見た目を確認するためのデバッグ専用機能（Release には含まれない）。
/// 例: -yukikoro-demo -yukikoro-tab 2 -yukikoro-hour 22.5
enum DemoMode {
    static var args: [String] { CommandLine.arguments }
    static var isOn: Bool { args.contains("-yukikoro-demo") }
    /// 整える画面を開いて起動する
    static var sculpts: Bool { args.contains("-yukikoro-sculpt") }
    /// 作品の編集画面を開いて起動する
    static var composes: Bool { args.contains("-yukikoro-compose") }
    /// 作品の編集画面でゆきだまを1つ選んで起動する
    static var selectsPiece: Bool { args.contains("-yukikoro-select") }

    static func value(_ key: String) -> String? {
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var hour: Double? { value("-yukikoro-hour").flatMap(Double.init) }
    static var tab: Int { value("-yukikoro-tab").flatMap(Int.init) ?? 0 }
    static var steps: Int { value("-yukikoro-steps").flatMap(Int.init) ?? 4_200 }

    /// デモ用に道具で整えたゆきだま
    private static func shaped(seed: UInt32, _ edit: (inout SnowShape) -> Void) -> SnowShape {
        var s = SnowShape.pristine(seed: seed)
        edit(&s)
        return s
    }

    private static func dir(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { simd_normalize(SIMD3<Float>(x, y, z)) }

    /// 動作確認用の状態（ゆきだま3つと、積み上げた作品1つ）
    static func state() -> GameState {
        var s = GameState()
        s.onboarded = true
        s.initialized = true

        // 赤いマフラーを巻いた、顔のある雪玉
        let body = shaped(seed: 3) { b in
            for i in 0..<28 {
                let a = Float(i) / 28 * 2 * .pi
                b.apply(tool: .paint, direction: dir(sin(a), 0.1, cos(a)), size: 0.2, strength: 2.5, color: SIMD3<Float>(0.9, 0.2, 0.2))
            }
        }
        let head = shaped(seed: 8) { h in
            for _ in 0..<26 { h.apply(tool: .carve, direction: dir(-0.28, 0.2, 1), size: 0.14, strength: 1) }
            for _ in 0..<26 { h.apply(tool: .carve, direction: dir(0.28, 0.2, 1), size: 0.14, strength: 1) }
            for _ in 0..<18 { h.apply(tool: .add, direction: dir(0, -0.05, 1), size: 0.16, strength: 1.4) }
            h.apply(tool: .paint, direction: dir(0, -0.05, 1), size: 0.2, strength: 8, color: SIMD3<Float>(0.98, 0.58, 0.2))
        }
        let base = shaped(seed: 21) { b in
            for _ in 0..<30 { b.apply(tool: .carve, direction: dir(0.9, 0.5, 0.3), size: 0.4, strength: 1) }
            for _ in 0..<10 { b.apply(tool: .smooth, direction: dir(0.9, 0.5, 0.3), size: 0.5, strength: 1) }
        }

        let big = SnowPiece(id: UUID(), steps: 15_000, madeAt: Date(), shape: base)
        let mid = SnowPiece(id: UUID(), steps: 5_000, madeAt: Date(), shape: body)
        let small = SnowPiece(id: UUID(), steps: 1_600, madeAt: Date(), shape: head)

        var art = Artwork(name: "ゆきころ像", createdAt: Date(), updatedAt: Date())
        func place(_ piece: SnowPiece, x: Float, z: Float, yaw: Float = 0) {
            let y = Artwork.settleHeight(x: x, z: z, radius: piece.radius, among: art.placements)
            var p = Placement(piece: piece, position: SIMD3<Float>(x, y, z))
            p.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            art.placements.append(p)
        }
        place(big, x: 0, z: 0, yaw: 0.6)
        place(mid, x: 0.05, z: 0, yaw: 0)
        place(small, x: 0.05, z: 0.05, yaw: 0)
        // 隣に並べた小さな雪玉
        place(SnowPiece(id: UUID(), steps: 900, madeAt: Date(), shape: SnowShape.pristine(seed: 40)), x: 2.4, z: 0.6)
        place(SnowPiece(id: UUID(), steps: 500, madeAt: Date(), shape: SnowShape.pristine(seed: 41)), x: -2.1, z: 0.9)
        s.artworks = [art]

        s.stock = [
            SnowPiece(id: UUID(), steps: 3_200, madeAt: Date(), shape: SnowShape.pristine(seed: 5)),
            SnowPiece(id: UUID(), steps: 800, madeAt: Date(), shape: shaped(seed: 12) { b in
                for _ in 0..<40 { b.apply(tool: .paint, direction: dir(0.2, 1, 0.4), size: 0.5, strength: 3, color: SIMD3<Float>(0.35, 0.75, 0.95)) }
            }),
            SnowPiece(id: UUID(), steps: 6_500, madeAt: Date(), shape: shaped(seed: 17) { b in
                for _ in 0..<32 { b.apply(tool: .carve, direction: dir(0.1, 0.2, 1), size: 0.5, strength: 1) }
            }),
        ]
        s.rollingSteps = steps
        s.totalSteps = 38_000 + steps
        s.credited[DayKey.key(for: Date())] = 5_200
        return s
    }
}
#endif
