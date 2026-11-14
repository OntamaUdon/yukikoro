import SwiftUI

/// 転がっている雪玉。表面のでこぼこが球面に沿って回転して見える。
enum SnowballArt {
    /// (緯度, 経度, 大きさ) — 見た目が偏らないよう固定の配置
    private static let lumps: [(lat: Double, lon: Double, size: Double)] = [
        (0.10, 0.2, 0.10), (-0.45, 0.9, 0.07), (0.60, 1.5, 0.08), (-0.15, 2.1, 0.12),
        (0.35, 2.7, 0.06), (-0.60, 3.3, 0.09), (0.05, 3.9, 0.07), (0.70, 4.4, 0.10),
        (-0.30, 4.9, 0.08), (0.45, 5.5, 0.11), (-0.05, 6.0, 0.06), (0.25, 1.0, 0.05),
        (-0.55, 2.4, 0.06), (0.15, 4.2, 0.09),
    ]

    /// 正方形 `rect` の上部に球、下部に影を描く。
    static func draw(in ctx: inout GraphicsContext, rect: CGRect, rotation: Double) {
        let d = min(rect.width, rect.height)
        let r = d * 0.46
        let c = CGPoint(x: rect.midX, y: rect.minY + r)

        let shadow = Path(ellipseIn: CGRect(x: c.x - r * 0.85, y: c.y + r * 0.88, width: r * 1.7, height: r * 0.24))
        ctx.fill(shadow, with: .color(Palette.ink.opacity(0.14)))

        let ballPath = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(
            ballPath,
            with: .radialGradient(
                Gradient(colors: [Palette.snow, Palette.snowShade]),
                center: CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4),
                startRadius: 0,
                endRadius: r * 1.8
            )
        )

        let ballRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.drawLayer { layer in
            layer.clip(to: ballPath)
            for lump in lumps {
                let lon = lump.lon + rotation
                let depth = cos(lon)
                if depth < 0.12 { continue }
                let x = c.x + r * 0.9 * cos(lump.lat) * sin(lon)
                let y = c.y + r * 0.9 * sin(lump.lat)
                let w = r * lump.size * 2 * (0.5 + 0.5 * depth)
                let h = r * lump.size * 2
                let blob = Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
                layer.fill(blob, with: .color(Palette.snowShade.opacity(0.55 * depth)))
                let glint = Path(ellipseIn: CGRect(x: x - w * 0.3, y: y - h * 0.45, width: w * 0.4, height: h * 0.3))
                layer.fill(glint, with: .color(.white.opacity(0.7 * depth)))
            }
            // 縁を少しだけ暗くして立体感を出す
            layer.stroke(Path(ellipseIn: ballRect.insetBy(dx: r * 0.03, dy: r * 0.03)),
                         with: .color(Palette.outline.opacity(0.25)), lineWidth: r * 0.06)
        }

        ctx.stroke(ballPath, with: .color(Palette.outline.opacity(0.7)), lineWidth: max(0.8, r * 0.02))
    }
}
