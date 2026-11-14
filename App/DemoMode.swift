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

    /// デモ用に刃と色で整えたゆきだま
    private static func shaped(seed: UInt32, _ edit: (inout SnowShape) -> Void) -> SnowShape {
        var s = SnowShape.pristine(seed: seed)
        edit(&s)
        return s
    }

    /// 動作確認用の状態（ゆきだま3つと、積み上げた作品1つ）
    static func state() -> GameState {
        var s = GameState()
        s.onboarded = true
        s.initialized = true

        // 赤い胴体（左を刃で平らに削る）
        let body = shaped(seed: 3) { b in
            b.cutBlade(angle: 0, planeX: -0.7, bandLow: -0.4, bandHigh: 0.6)
            b.setTint(SIMD3<Float>(0.98, 0.62, 0.62))
        }
        // 頭（斜めに平らに）
        let head = shaped(seed: 8) { h in
            h.cutBlade(angle: 0.6, planeX: -0.8, bandLow: -3, bandHigh: 3)
            h.setTint(SIMD3<Float>(0.99, 0.93, 0.55))
        }
        let base = shaped(seed: 21) { b in
            b.cutBlade(angle: 0, planeX: -0.75, bandLow: -3, bandHigh: 3)
            b.cutBlade(angle: 1.2, planeX: -0.8, bandLow: -3, bandHigh: 3)
        }

        let big = SnowPiece(id: UUID(), steps: 15_000, madeAt: Date(), shape: base)
        let mid = SnowPiece(id: UUID(), steps: 5_000, madeAt: Date(), shape: body)
        let small = SnowPiece(id: UUID(), steps: 1_600, madeAt: Date(), shape: head)

        var art = Artwork(name: "ゆきころ像", createdAt: Date(), updatedAt: Date())
        func place(_ piece: SnowPiece, x: Float, angle: Float = 0) {
            let y = Artwork.settleHeight(x: x, radius: piece.radius, among: art.placements)
            art.placements.append(Placement(piece: piece, position: SIMD2<Float>(x, y), angle: angle))
        }
        place(big, x: 0, angle: 0.6)
        place(mid, x: 0.05)
        place(small, x: 0.05, angle: -0.4)
        // 隣に並べた小さな雪玉
        place(SnowPiece(id: UUID(), steps: 900, madeAt: Date(), shape: SnowShape.pristine(seed: 40)), x: 2.4)
        place(SnowPiece(id: UUID(), steps: 500, madeAt: Date(), shape: SnowShape.pristine(seed: 41)), x: -2.1)
        s.artworks = [art]

        s.stock = [
            SnowPiece(id: UUID(), steps: 3_200, madeAt: Date(), shape: SnowShape.pristine(seed: 5)),
            SnowPiece(id: UUID(), steps: 800, madeAt: Date(), shape: shaped(seed: 12) { b in
                b.setTint(SIMD3<Float>(0.62, 0.84, 0.98))
            }),
            SnowPiece(id: UUID(), steps: 6_500, madeAt: Date(), shape: shaped(seed: 17) { b in
                b.cutBlade(angle: 0, planeX: -0.6, bandLow: -3, bandHigh: 3)
            }),
        ]
        s.rollingSteps = steps
        s.rollingShape = shaped(seed: 11) { b in
            b.cutBlade(angle: 0, planeX: -0.8, bandLow: -0.3, bandHigh: 0.9)
        }
        s.totalSteps = 38_000 + steps
        s.credited[DayKey.key(for: Date())] = 5_200
        return s
    }
}
#endif
