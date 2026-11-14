import SwiftUI

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// 雪だるまを SwiftUI の Canvas で描く。画像素材は使わない。
/// 座標は 0〜1 の単位正方形（原点は左上）。体の中心 (0.5, 0.70) 半径 0.25、頭の中心 (0.5, 0.36) 半径 0.17。
enum SnowmanArt {
    static func draw(species: Species, decorations: [Decoration], in ctx: inout GraphicsContext, rect: CGRect) {
        let f = ArtFrame(rect: rect)
        ctx.fill(f.ellipse(0.5, 0.955, 0.30, 0.04), with: .color(Palette.ink.opacity(0.12)))
        drawBehind(species, &ctx, f)
        drawBodyAndHead(species, &ctx, f)
        drawArms(species, decorations, &ctx, f)
        drawFace(species, &ctx, f)
        drawSignature(species, &ctx, f)
        for decoration in decorations {
            drawDecoration(decoration, species, &ctx, f)
        }
    }

    // MARK: 共通の部品

    private static func bodyColors(_ s: Species) -> (Color, Color) {
        switch s {
        case .penguin: return (Color(red: 0.34, green: 0.42, blue: 0.60), Color(red: 0.17, green: 0.22, blue: 0.36))
        case .hiyoko: return (Color(red: 1.0, green: 0.96, blue: 0.70), Color(red: 0.98, green: 0.82, blue: 0.42))
        case .daruma: return (Color(red: 0.97, green: 0.42, blue: 0.40), Color(red: 0.76, green: 0.20, blue: 0.24))
        default: return (Palette.snow, Palette.snowShade)
        }
    }

    private static func ball(_ ctx: inout GraphicsContext, _ f: ArtFrame, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, base: Color, shade: Color) {
        let path = f.circle(cx, cy, r)
        ctx.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [base, shade]),
                center: f.pt(cx - r * 0.35, cy - r * 0.4),
                startRadius: 0,
                endRadius: f.len(r * 1.8)
            )
        )
        ctx.stroke(path, with: .color(Palette.outline.opacity(0.7)), lineWidth: max(0.8, f.len(0.006)))
    }

    private static func soft(_ ctx: inout GraphicsContext, _ path: Path, _ f: ArtFrame, fill: Color, stroke: Color = Palette.outline) {
        ctx.fill(path, with: .color(fill))
        ctx.stroke(path, with: .color(stroke.opacity(0.75)), style: StrokeStyle(lineWidth: max(0.8, f.len(0.006)), lineJoin: .round))
    }

    // MARK: 背面（羽・マント・耳）

    private static func drawBehind(_ s: Species, _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        switch s {
        case .tenshi:
            for sign: CGFloat in [-1, 1] {
                let wing = f.ellipse(0.5 + sign * 0.31, 0.56, 0.07, 0.17, angle: sign * 0.5)
                soft(&ctx, wing, f, fill: Palette.snow)
            }
        case .ousama:
            let cape = f.poly([P(0.22, 0.50), P(0.78, 0.50), P(0.91, 0.95), P(0.09, 0.95)])
            soft(&ctx, cape, f, fill: Color(red: 0.86, green: 0.25, blue: 0.30), stroke: Color(red: 0.60, green: 0.12, blue: 0.20))
        case .usagi:
            for sign: CGFloat in [-1, 1] {
                let cx = 0.5 + sign * 0.075
                soft(&ctx, f.ellipse(cx, 0.12, 0.042, 0.115, angle: sign * 0.12), f, fill: Palette.snow)
                ctx.fill(f.ellipse(cx, 0.125, 0.02, 0.08, angle: sign * 0.12), with: .color(Palette.cheek.opacity(0.75)))
            }
        case .neko:
            for sign: CGFloat in [-1, 1] {
                let outer = f.poly([P(0.5 + sign * 0.145, 0.25), P(0.5 + sign * 0.15, 0.095), P(0.5 + sign * 0.04, 0.20)])
                soft(&ctx, outer, f, fill: Palette.snow)
                let inner = f.poly([P(0.5 + sign * 0.13, 0.22), P(0.5 + sign * 0.135, 0.13), P(0.5 + sign * 0.07, 0.20)])
                ctx.fill(inner, with: .color(Palette.cheek.opacity(0.75)))
            }
        case .kuma:
            for sign: CGFloat in [-1, 1] {
                let cx = 0.5 + sign * 0.115
                soft(&ctx, f.circle(cx, 0.215, 0.052), f, fill: Palette.snow)
                ctx.fill(f.circle(cx, 0.22, 0.028), with: .color(Palette.cheek.opacity(0.75)))
            }
        default:
            break
        }
    }

    // MARK: 体と頭

    private static func drawBodyAndHead(_ s: Species, _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        let colors = bodyColors(s)
        ball(&ctx, f, 0.5, 0.70, 0.25, base: colors.0, shade: colors.1)
        ball(&ctx, f, 0.5, 0.36, 0.17, base: colors.0, shade: colors.1)
        switch s {
        case .penguin:
            ctx.fill(f.ellipse(0.5, 0.735, 0.155, 0.19), with: .color(Palette.snow))
            ctx.fill(f.ellipse(0.5, 0.385, 0.115, 0.10), with: .color(Palette.snow))
        case .daruma:
            ctx.fill(f.ellipse(0.5, 0.385, 0.125, 0.11), with: .color(Palette.snow))
            ctx.stroke(f.circle(0.5, 0.72, 0.13), with: .color(Palette.gold), lineWidth: f.len(0.014))
        default:
            break
        }
    }

    // MARK: 腕

    private static func drawArms(_ s: Species, _ decorations: [Decoration], _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        if s.hasTwigArms {
            let mitten = decorations.first { $0.kind == .mittens }
            for sign: CGFloat in [-1, 1] {
                let sx = 0.5 + sign * 0.225
                let ex = 0.5 + sign * 0.38
                let style = StrokeStyle(lineWidth: f.len(0.014), lineCap: .round)
                ctx.stroke(f.line(sx, 0.66, ex, 0.545), with: .color(Palette.twig), style: style)
                ctx.stroke(f.line(0.5 + sign * 0.31, 0.595, 0.5 + sign * 0.345, 0.50), with: .color(Palette.twig), style: style)
                ctx.stroke(f.line(0.5 + sign * 0.35, 0.57, 0.5 + sign * 0.41, 0.50), with: .color(Palette.twig), style: style)
                if let mitten {
                    let tone = Palette.tone(mitten.hue)
                    soft(&ctx, f.circle(ex, 0.545, 0.036), f, fill: tone.base, stroke: tone.dark)
                }
            }
        } else if s == .penguin {
            let colors = bodyColors(s)
            for sign: CGFloat in [-1, 1] {
                ctx.fill(f.ellipse(0.5 + sign * 0.26, 0.70, 0.05, 0.13, angle: -sign * 0.35), with: .color(colors.1))
            }
        } else if s == .hiyoko {
            let colors = bodyColors(s)
            for sign: CGFloat in [-1, 1] {
                soft(&ctx, f.ellipse(0.5 + sign * 0.255, 0.68, 0.05, 0.09, angle: -sign * 0.5), f, fill: colors.1, stroke: Palette.goldDark)
            }
        }
    }

    // MARK: 顔

    private static func eyes(_ ctx: inout GraphicsContext, _ f: ArtFrame, y: CGFloat = 0.345, dx: CGFloat = 0.058) {
        for sign: CGFloat in [-1, 1] {
            ctx.fill(f.circle(0.5 + sign * dx, y, 0.016), with: .color(Palette.ink))
            ctx.fill(f.circle(0.5 + sign * dx - 0.004, y - 0.005, 0.005), with: .color(.white))
        }
    }

    private static func cheeks(_ ctx: inout GraphicsContext, _ f: ArtFrame) {
        for sign: CGFloat in [-1, 1] {
            ctx.fill(f.ellipse(0.5 + sign * 0.10, 0.388, 0.03, 0.018), with: .color(Palette.cheek.opacity(0.7)))
        }
    }

    private static func smile(_ ctx: inout GraphicsContext, _ f: ArtFrame, y: CGFloat) {
        let style = StrokeStyle(lineWidth: f.len(0.007), lineCap: .round)
        ctx.stroke(f.quad(0.5, y, 0.465, y + 0.008, control: 0.485, y + 0.03), with: .color(Palette.ink), style: style)
        ctx.stroke(f.quad(0.5, y, 0.535, y + 0.008, control: 0.515, y + 0.03), with: .color(Palette.ink), style: style)
    }

    private static func drawFace(_ s: Species, _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        switch s {
        case .plain:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            let nose = f.poly([P(0.478, 0.362), P(0.522, 0.362), P(0.5, 0.428)])
            soft(&ctx, nose, f, fill: Palette.carrot, stroke: Color(red: 0.85, green: 0.42, blue: 0.10))
            for i in 0..<5 {
                let x = 0.5 + CGFloat(i - 2) * 0.027
                let y = 0.447 + CGFloat(2 - abs(i - 2)) * 0.006
                ctx.fill(f.circle(x, y, 0.0085), with: .color(Palette.ink))
            }
        case .usagi:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            ctx.fill(f.ellipse(0.5, 0.372, 0.014, 0.01), with: .color(Color(red: 0.95, green: 0.50, blue: 0.60)))
            smile(&ctx, f, y: 0.388)
        case .neko:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            ctx.fill(f.poly([P(0.488, 0.368), P(0.512, 0.368), P(0.5, 0.384)]), with: .color(Color(red: 0.95, green: 0.50, blue: 0.60)))
            smile(&ctx, f, y: 0.392)
            let thin = StrokeStyle(lineWidth: f.len(0.004), lineCap: .round)
            for sign: CGFloat in [-1, 1] {
                ctx.stroke(f.line(0.5 + sign * 0.08, 0.382, 0.5 + sign * 0.155, 0.362), with: .color(Palette.ink.opacity(0.45)), style: thin)
                ctx.stroke(f.line(0.5 + sign * 0.08, 0.392, 0.5 + sign * 0.16, 0.392), with: .color(Palette.ink.opacity(0.45)), style: thin)
                ctx.stroke(f.line(0.5 + sign * 0.08, 0.402, 0.5 + sign * 0.155, 0.422), with: .color(Palette.ink.opacity(0.45)), style: thin)
            }
        case .kuma:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            ctx.fill(f.ellipse(0.5, 0.405, 0.065, 0.05), with: .color(Color(red: 1.0, green: 0.93, blue: 0.86)))
            ctx.fill(f.ellipse(0.5, 0.388, 0.02, 0.013), with: .color(Palette.ink))
            smile(&ctx, f, y: 0.402)
        case .inu:
            for sign: CGFloat in [-1, 1] {
                soft(&ctx, f.ellipse(0.5 + sign * 0.155, 0.33, 0.05, 0.10, angle: -sign * 0.3), f,
                     fill: Color(red: 0.90, green: 0.76, blue: 0.58), stroke: Color(red: 0.70, green: 0.52, blue: 0.36))
            }
            eyes(&ctx, f)
            cheeks(&ctx, f)
            ctx.fill(f.ellipse(0.5, 0.378, 0.022, 0.016), with: .color(Palette.ink))
            smile(&ctx, f, y: 0.396)
        case .penguin:
            eyes(&ctx, f, y: 0.34)
            cheeks(&ctx, f)
            soft(&ctx, f.poly([P(0.47, 0.368), P(0.53, 0.368), P(0.5, 0.412)]), f,
                 fill: Color(red: 1.0, green: 0.70, blue: 0.25), stroke: Color(red: 0.85, green: 0.48, blue: 0.10))
        case .hiyoko:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            soft(&ctx, f.poly([P(0.478, 0.37), P(0.522, 0.37), P(0.5, 0.405)]), f,
                 fill: Color(red: 1.0, green: 0.60, blue: 0.22), stroke: Color(red: 0.85, green: 0.42, blue: 0.10))
            let style = StrokeStyle(lineWidth: f.len(0.012), lineCap: .round)
            let tuft = Color(red: 0.98, green: 0.82, blue: 0.42)
            ctx.stroke(f.line(0.5, 0.195, 0.5, 0.135), with: .color(tuft), style: style)
            ctx.stroke(f.line(0.47, 0.20, 0.44, 0.15), with: .color(tuft), style: style)
            ctx.stroke(f.line(0.53, 0.20, 0.56, 0.15), with: .color(tuft), style: style)
        case .daruma:
            let brow = StrokeStyle(lineWidth: f.len(0.014), lineCap: .round)
            for sign: CGFloat in [-1, 1] {
                ctx.stroke(f.quad(0.5 + sign * 0.105, 0.335, 0.5 + sign * 0.02, 0.325, control: 0.5 + sign * 0.07, 0.295),
                           with: .color(Palette.ink), style: brow)
                ctx.fill(f.circle(0.5 + sign * 0.06, 0.357, 0.022), with: .color(.white))
                ctx.stroke(f.circle(0.5 + sign * 0.06, 0.357, 0.022), with: .color(Palette.ink), lineWidth: f.len(0.004))
                ctx.fill(f.circle(0.5 + sign * 0.06, 0.357, 0.011), with: .color(Palette.ink))
            }
            ctx.fill(f.ellipse(0.5, 0.39, 0.014, 0.01), with: .color(Color(red: 0.95, green: 0.50, blue: 0.55)))
            let mustache = StrokeStyle(lineWidth: f.len(0.009), lineCap: .round)
            for sign: CGFloat in [-1, 1] {
                ctx.stroke(f.quad(0.5, 0.41, 0.5 + sign * 0.095, 0.425, control: 0.5 + sign * 0.05, 0.445),
                           with: .color(Palette.ink), style: mustache)
            }
        case .tenshi:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            smile(&ctx, f, y: 0.395)
        case .ousama:
            eyes(&ctx, f)
            cheeks(&ctx, f)
            ctx.fill(f.circle(0.5, 0.385, 0.017), with: .color(Palette.carrot))
            for sign: CGFloat in [-1, 1] {
                soft(&ctx, f.ellipse(0.5 + sign * 0.035, 0.418, 0.036, 0.022, angle: sign * 0.3), f, fill: Palette.snow)
            }
        }
    }

    // MARK: 種類ごとの印（輪っか・王冠）

    private static func drawSignature(_ s: Species, _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        if s == .tenshi {
            ctx.stroke(f.ellipse(0.5, 0.135, 0.085, 0.022), with: .color(Palette.gold), lineWidth: f.len(0.014))
        } else if s == .ousama {
            let crown = f.poly([P(0.405, 0.215), P(0.395, 0.105), P(0.452, 0.16), P(0.5, 0.085), P(0.548, 0.16), P(0.605, 0.105), P(0.595, 0.215)])
            soft(&ctx, crown, f, fill: Palette.gold, stroke: Palette.goldDark)
            ctx.fill(f.circle(0.5, 0.19, 0.013), with: .color(Color(red: 0.90, green: 0.25, blue: 0.30)))
            ctx.fill(f.circle(0.44, 0.195, 0.009), with: .color(Color(red: 0.30, green: 0.55, blue: 0.95)))
            ctx.fill(f.circle(0.56, 0.195, 0.009), with: .color(Color(red: 0.30, green: 0.75, blue: 0.50)))
        }
    }

    // MARK: 飾り

    private static func drawDecoration(_ d: Decoration, _ s: Species, _ ctx: inout GraphicsContext, _ f: ArtFrame) {
        let tone = Palette.tone(d.hue)
        switch d.kind {
        case .bucketHat:
            soft(&ctx, f.rrect(0.40, 0.115, 0.20, 0.115, 0.045), f, fill: tone.base, stroke: tone.dark)
            ctx.fill(f.rrect(0.40, 0.195, 0.20, 0.022, 0), with: .color(tone.dark))
            soft(&ctx, f.ellipse(0.5, 0.235, 0.165, 0.032), f, fill: tone.base, stroke: tone.dark)
        case .topHat:
            soft(&ctx, f.ellipse(0.5, 0.215, 0.15, 0.026), f, fill: Palette.ink, stroke: Palette.ink)
            soft(&ctx, f.rrect(0.405, 0.065, 0.19, 0.15, 0.012), f, fill: Palette.ink, stroke: Palette.ink)
            ctx.fill(f.rrect(0.405, 0.175, 0.19, 0.03, 0), with: .color(tone.base))
        case .santaHat:
            var hat = Path()
            hat.move(to: f.pt(0.35, 0.245))
            hat.addQuadCurve(to: f.pt(0.64, 0.10), control: f.pt(0.38, 0.06))
            hat.addQuadCurve(to: f.pt(0.65, 0.245), control: f.pt(0.68, 0.14))
            hat.closeSubpath()
            soft(&ctx, hat, f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, f.rrect(0.33, 0.225, 0.34, 0.045, 0.022), f, fill: Palette.snow)
            soft(&ctx, f.circle(0.64, 0.10, 0.034), f, fill: Palette.snow)
        case .knitCap:
            var cap = Path()
            cap.move(to: f.pt(0.325, 0.30))
            cap.addCurve(to: f.pt(0.675, 0.30), control1: f.pt(0.30, 0.085), control2: f.pt(0.70, 0.085))
            cap.closeSubpath()
            soft(&ctx, cap, f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, f.rrect(0.32, 0.265, 0.36, 0.052, 0.02), f, fill: tone.dark, stroke: tone.dark)
            soft(&ctx, f.circle(0.5, 0.135, 0.03), f, fill: Palette.snow)
        case .earmuffs:
            ctx.stroke(f.quad(0.335, 0.37, 0.665, 0.37, control: 0.5, 0.02), with: .color(Palette.ink.opacity(0.7)),
                       style: StrokeStyle(lineWidth: f.len(0.012), lineCap: .round))
            soft(&ctx, f.circle(0.33, 0.375, 0.046), f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, f.circle(0.67, 0.375, 0.046), f, fill: tone.base, stroke: tone.dark)
        case .flowerCrown:
            for i in 0..<5 {
                let x = 0.38 + CGFloat(i) * 0.06
                let dx = x - 0.5
                let y = 0.36 - (0.17 * 0.17 - dx * dx).squareRoot() - 0.004
                let petal = Palette.tone(d.hue + i)
                for k in 0..<5 {
                    let a = CGFloat(k) * 2 * .pi / 5
                    ctx.fill(f.circle(x + cos(a) * 0.016, y + sin(a) * 0.016, 0.012), with: .color(petal.base))
                }
                ctx.fill(f.circle(x, y, 0.009), with: .color(Palette.gold))
            }
        case .ribbon:
            let left = f.poly([P(0.60, 0.235), P(0.545, 0.205), P(0.545, 0.265)])
            let right = f.poly([P(0.60, 0.235), P(0.655, 0.205), P(0.655, 0.265)])
            soft(&ctx, left, f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, right, f, fill: tone.base, stroke: tone.dark)
            ctx.fill(f.circle(0.60, 0.235, 0.017), with: .color(tone.dark))
        case .sunglasses:
            for sign: CGFloat in [-1, 1] {
                ctx.fill(f.ellipse(0.5 + sign * 0.057, 0.347, 0.048, 0.034), with: .color(Palette.ink))
                ctx.fill(f.ellipse(0.5 + sign * 0.057 - 0.012, 0.337, 0.012, 0.005, angle: -0.4), with: .color(.white.opacity(0.5)))
            }
            ctx.stroke(f.line(0.49, 0.34, 0.51, 0.34), with: .color(Palette.ink), lineWidth: f.len(0.008))
        case .roundGlasses:
            for sign: CGFloat in [-1, 1] {
                ctx.stroke(f.circle(0.5 + sign * 0.058, 0.347, 0.038), with: .color(tone.dark), lineWidth: f.len(0.010))
            }
            ctx.stroke(f.line(0.49, 0.34, 0.51, 0.34), with: .color(tone.dark), lineWidth: f.len(0.008))
        case .scarf:
            soft(&ctx, f.ellipse(0.5, 0.50, 0.17, 0.042), f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, f.rrect(0.56, 0.50, 0.075, 0.17, 0.02), f, fill: tone.base, stroke: tone.dark)
            ctx.fill(f.rrect(0.56, 0.585, 0.075, 0.016, 0), with: .color(tone.dark))
            ctx.fill(f.rrect(0.56, 0.625, 0.075, 0.016, 0), with: .color(tone.dark))
        case .bowtie:
            soft(&ctx, f.poly([P(0.5, 0.505), P(0.435, 0.475), P(0.435, 0.535)]), f, fill: tone.base, stroke: tone.dark)
            soft(&ctx, f.poly([P(0.5, 0.505), P(0.565, 0.475), P(0.565, 0.535)]), f, fill: tone.base, stroke: tone.dark)
            ctx.fill(f.circle(0.5, 0.505, 0.016), with: .color(tone.dark))
        case .buttons:
            for y in [0.62, 0.70, 0.78] as [CGFloat] {
                ctx.fill(f.circle(0.5, y, 0.019), with: .color(tone.dark))
            }
        case .stripe:
            let bodyPath = f.circle(0.5, 0.70, 0.25)
            let band1 = f.rrect(0.2, 0.63, 0.6, 0.045, 0)
            let band2 = f.rrect(0.2, 0.72, 0.6, 0.045, 0)
            ctx.drawLayer { layer in
                layer.clip(to: bodyPath)
                layer.fill(band1, with: .color(tone.base.opacity(0.9)))
                layer.fill(band2, with: .color(tone.base.opacity(0.9)))
            }
        case .mittens:
            break // 腕の描画時に一緒に描く
        }
    }
}
