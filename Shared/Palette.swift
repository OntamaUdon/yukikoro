import SwiftUI

struct Tone {
    let base: Color
    let dark: Color
}

enum Palette {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    static let snow = Color(red: 0.98, green: 0.99, blue: 1.0)
    static let snowShade = Color(red: 0.78, green: 0.86, blue: 0.96)
    static let outline = Color(red: 0.55, green: 0.68, blue: 0.85)
    static let ink = Color(red: 0.19, green: 0.22, blue: 0.32)
    static let cheek = Color(red: 1.0, green: 0.66, blue: 0.72)
    static let carrot = Color(red: 1.0, green: 0.60, blue: 0.22)
    static let twig = Color(red: 0.47, green: 0.33, blue: 0.24)
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.30)
    static let goldDark = Color(red: 0.86, green: 0.62, blue: 0.14)
    static let tint = Color(red: 0.34, green: 0.56, blue: 0.86)

    static let tones: [Tone] = [
        Tone(base: Color(red: 0.93, green: 0.36, blue: 0.38), dark: Color(red: 0.74, green: 0.22, blue: 0.27)),
        Tone(base: Color(red: 0.36, green: 0.62, blue: 0.92), dark: Color(red: 0.22, green: 0.44, blue: 0.76)),
        Tone(base: Color(red: 0.40, green: 0.77, blue: 0.56), dark: Color(red: 0.24, green: 0.58, blue: 0.40)),
        Tone(base: Color(red: 1.00, green: 0.78, blue: 0.30), dark: Color(red: 0.90, green: 0.60, blue: 0.15)),
        Tone(base: Color(red: 1.00, green: 0.62, blue: 0.76), dark: Color(red: 0.88, green: 0.42, blue: 0.60)),
        Tone(base: Color(red: 0.65, green: 0.54, blue: 0.90), dark: Color(red: 0.48, green: 0.38, blue: 0.74)),
    ]

    static func tone(_ hue: Int) -> Tone {
        let n = tones.count
        return tones[((hue % n) + n) % n]
    }
}

/// 描画領域を 0〜1 の単位正方形として扱うための座標変換
struct ArtFrame {
    let origin: CGPoint
    let u: CGFloat

    init(rect: CGRect) {
        let side = min(rect.width, rect.height)
        u = side
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * u, y: origin.y + y * u)
    }

    func len(_ v: CGFloat) -> CGFloat { v * u }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: origin.x + (cx - r) * u, y: origin.y + (cy - r) * u, width: 2 * r * u, height: 2 * r * u))
    }

    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat = 0) -> Path {
        let base = Path(ellipseIn: CGRect(x: -rx * u, y: -ry * u, width: 2 * rx * u, height: 2 * ry * u))
        return base
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: origin.x + cx * u, y: origin.y + cy * u))
    }

    func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: origin.x + x * u, y: origin.y + y * u, width: w * u, height: h * u), cornerRadius: r * u)
    }

    func poly(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: pt(first.x, first.y))
        for q in points.dropFirst() {
            p.addLine(to: pt(q.x, q.y))
        }
        p.closeSubpath()
        return p
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var p = Path()
        p.move(to: pt(x1, y1))
        p.addLine(to: pt(x2, y2))
        return p
    }

    func quad(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, control cx: CGFloat, _ cy: CGFloat) -> Path {
        var p = Path()
        p.move(to: pt(x1, y1))
        p.addQuadCurve(to: pt(x2, y2), control: pt(cx, cy))
        return p
    }
}
