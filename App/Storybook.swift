import SwiftUI

/// 絵本風のスタイル（やわらかい色・丸い形・ふわっとした影）
enum Storybook {
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let accent = Color(red: 0.36, green: 0.58, blue: 0.92)
    static let warm = Color(red: 0.99, green: 0.72, blue: 0.58)
    static let ink = Color(red: 0.24, green: 0.25, blue: 0.38)
    static let shadow = Color(red: 0.20, green: 0.28, blue: 0.50).opacity(0.18)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// ふわっとした紙のようなカード
    func storyCard(corner: CGFloat = 26) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Storybook.paper.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: Storybook.shadow, radius: 14, y: 6)
    }
}

/// 丸いボタン
struct StoryButtonStyle: ButtonStyle {
    enum Kind { case primary, soft }
    var kind: Kind = .soft
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Storybook.rounded(compact ? 15 : 17))
            .padding(.horizontal, compact ? 14 : 20)
            .padding(.vertical, compact ? 9 : 13)
            .foregroundStyle(kind == .primary ? Color.white : Storybook.ink)
            .background(Capsule().fill(kind == .primary ? Storybook.accent : Color.white.opacity(0.9)))
            .overlay(Capsule().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
            .shadow(color: Storybook.shadow, radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 丸い小さなボタン（アイコン用）
struct StoryRoundButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Storybook.rounded(18))
            .foregroundStyle(Storybook.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.92)))
            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
            .shadow(color: Storybook.shadow, radius: 5, y: 3)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 背景のイラスト用の画像（Resources/Backgrounds/ill_day.jpg など）。無いときは、コードで描いた絵を使う。
enum BackgroundImages {
    private static var cache: [String: UIImage] = [:]

    static func image(_ daypart: Daypart) -> UIImage? {
        let name = "ill_" + daypart.rawValue
        if let hit = cache[name] { return hit }
        for ext in ["jpg", "png"] {
            if let path = Bundle.main.path(forResource: name, ofType: ext), let image = UIImage(contentsOfFile: path) {
                cache[name] = image
                return image
            }
        }
        return nil
    }
}

/// 時間帯ごとの背景（絵本風のイラスト）
struct StoryBackground: View {
    let daypart: Daypart

    var body: some View {
        if let image = BackgroundImages.image(daypart) {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
        } else {
            Canvas { ctx, size in
                StoryScene.draw(&ctx, size: size, daypart: daypart)
            }
        }
    }
}

private struct StoryPalette {
    let skyTop: Color, skyBottom: Color, sun: Color
    let hillFar: Color, hillNear: Color
    let tree: Color, treeSnow: Color
    let snowTop: Color, snowBottom: Color

    static func of(_ d: Daypart) -> StoryPalette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch d {
        case .day:
            return StoryPalette(skyTop: c(0.60, 0.80, 0.97), skyBottom: c(0.90, 0.96, 1.0), sun: c(1.0, 0.93, 0.65),
                                hillFar: c(0.82, 0.90, 0.98), hillNear: c(0.90, 0.95, 1.0),
                                tree: c(0.38, 0.58, 0.55), treeSnow: c(0.97, 0.99, 1.0),
                                snowTop: c(0.98, 0.99, 1.0), snowBottom: c(0.86, 0.92, 0.99))
        case .dusk:
            return StoryPalette(skyTop: c(0.52, 0.48, 0.76), skyBottom: c(1.0, 0.80, 0.68), sun: c(1.0, 0.72, 0.50),
                                hillFar: c(0.74, 0.66, 0.84), hillNear: c(0.88, 0.78, 0.88),
                                tree: c(0.36, 0.36, 0.56), treeSnow: c(1.0, 0.93, 0.92),
                                snowTop: c(1.0, 0.92, 0.90), snowBottom: c(0.82, 0.76, 0.92))
        case .night:
            return StoryPalette(skyTop: c(0.07, 0.09, 0.26), skyBottom: c(0.28, 0.32, 0.58), sun: c(0.99, 0.96, 0.82),
                                hillFar: c(0.22, 0.28, 0.52), hillNear: c(0.28, 0.34, 0.60),
                                tree: c(0.12, 0.20, 0.36), treeSnow: c(0.70, 0.78, 0.95),
                                snowTop: c(0.62, 0.72, 0.92), snowBottom: c(0.38, 0.46, 0.72))
        }
    }
}

/// コードで描く、やわらかい雪景色
enum StoryScene {
    private static func hillY(_ x: CGFloat, w: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> CGFloat {
        let t = x / w * 2 * .pi
        return base + amp * sin(t + phase) + amp * 0.45 * sin(2.3 * t + phase * 1.7)
    }

    private static func hill(w: CGFloat, h: CGFloat, base: CGFloat, amp: CGFloat, phase: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h))
        var x: CGFloat = 0
        while x <= w + 6 {
            p.addLine(to: CGPoint(x: x, y: hillY(x, w: w, base: base, amp: amp, phase: phase)))
            x += 6
        }
        p.addLine(to: CGPoint(x: w, y: h))
        p.closeSubpath()
        return p
    }

    private static func pine(_ ctx: inout GraphicsContext, x: CGFloat, baseY: CGFloat, size: CGFloat, color: Color, snow: Color) {
        let trunk = CGRect(x: x - size * 0.06, y: baseY - size * 0.16, width: size * 0.12, height: size * 0.2)
        ctx.fill(Path(trunk), with: .color(color.opacity(0.9)))
        for i in 0..<3 {
            let f = CGFloat(i)
            let tierW = size * (0.62 - f * 0.17)
            let tierBase = baseY - size * (0.12 + f * 0.27)
            let tierTop = tierBase - size * 0.40
            var tri = Path()
            tri.move(to: CGPoint(x: x, y: tierTop))
            tri.addLine(to: CGPoint(x: x - tierW / 2, y: tierBase))
            tri.addLine(to: CGPoint(x: x + tierW / 2, y: tierBase))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(color))
            var cap = Path()
            cap.move(to: CGPoint(x: x, y: tierTop))
            cap.addLine(to: CGPoint(x: x - tierW * 0.22, y: tierTop + size * 0.13))
            cap.addQuadCurve(to: CGPoint(x: x + tierW * 0.22, y: tierTop + size * 0.13), control: CGPoint(x: x, y: tierTop + size * 0.19))
            cap.closeSubpath()
            ctx.fill(cap, with: .color(snow))
        }
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, daypart: Daypart) {
        let w = size.width, h = size.height
        let p = StoryPalette.of(daypart)

        // 空
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [p.skyTop, p.skyBottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.58)))

        // 星
        if daypart == .night {
            var g = SplitMix64(seed: 77)
            for _ in 0..<60 {
                let x = CGFloat(g.next() % 1_000) / 1_000 * w
                let y = CGFloat(g.next() % 1_000) / 1_000 * h * 0.40
                let r = CGFloat(g.next() % 3) * 0.5 + 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
            }
        }

        // 太陽・月
        let sunCenter: CGPoint
        let sunR: CGFloat
        switch daypart {
        case .day: sunCenter = CGPoint(x: w * 0.76, y: h * 0.17); sunR = w * 0.085
        case .dusk: sunCenter = CGPoint(x: w * 0.30, y: h * 0.40); sunR = w * 0.11
        case .night: sunCenter = CGPoint(x: w * 0.76, y: h * 0.15); sunR = w * 0.075
        }
        ctx.fill(Path(ellipseIn: CGRect(x: sunCenter.x - sunR * 2.2, y: sunCenter.y - sunR * 2.2, width: sunR * 4.4, height: sunR * 4.4)),
                 with: .radialGradient(Gradient(colors: [p.sun.opacity(0.55), p.sun.opacity(0)]), center: sunCenter, startRadius: sunR * 0.5, endRadius: sunR * 2.2))
        ctx.fill(Path(ellipseIn: CGRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR, width: sunR * 2, height: sunR * 2)), with: .color(p.sun))
        if daypart == .night {
            // 三日月にする
            let bite = CGRect(x: sunCenter.x - sunR * 0.55, y: sunCenter.y - sunR * 1.05, width: sunR * 2, height: sunR * 2)
            ctx.fill(Path(ellipseIn: bite), with: .color(p.skyTop.opacity(0.96)))
        }

        // 雲
        if daypart != .night {
            let cloud = Color.white.opacity(daypart == .day ? 0.9 : 0.55)
            for (fx, fy, fs) in [(0.18, 0.12, 1.0), (0.55, 0.22, 0.75), (0.86, 0.34, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
                let cx = w * fx, cy = h * fy, s = w * 0.12 * fs
                for (dx, dy, r) in [(-0.7, 0.1, 0.55), (0.0, -0.1, 0.8), (0.75, 0.08, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + dx * s - r * s, y: cy + dy * s - r * s * 0.8, width: r * s * 2, height: r * s * 1.6)), with: .color(cloud))
                }
            }
        }

        // 遠い丘・近い丘・木
        ctx.fill(hill(w: w, h: h, base: h * 0.47, amp: h * 0.022, phase: 0.8), with: .color(p.hillFar))
        let nearBase = h * 0.545, nearAmp = h * 0.016, nearPhase: CGFloat = 2.2
        ctx.fill(hill(w: w, h: h, base: nearBase, amp: nearAmp, phase: nearPhase), with: .color(p.hillNear))
        for (fx, sz) in [(0.05, 0.16), (0.13, 0.11), (0.21, 0.14), (0.80, 0.12), (0.89, 0.17), (0.97, 0.11)] as [(CGFloat, CGFloat)] {
            let x = w * fx
            pine(&ctx, x: x, baseY: hillY(x, w: w, base: nearBase, amp: nearAmp, phase: nearPhase) + 6, size: w * sz, color: p.tree, snow: p.treeSnow)
        }

        // 手前の雪原
        let fieldTop = h * 0.595
        let field = hill(w: w, h: h, base: fieldTop, amp: h * 0.008, phase: 4.0)
        ctx.fill(field, with: .linearGradient(Gradient(colors: [p.snowTop, p.snowBottom]), startPoint: CGPoint(x: 0, y: fieldTop), endPoint: CGPoint(x: 0, y: h)))
        // 雪のふくらみ
        var g = SplitMix64(seed: 31)
        for _ in 0..<7 {
            let x = CGFloat(g.next() % 1_000) / 1_000 * w
            let y = fieldTop + CGFloat(g.next() % 1_000) / 1_000 * (h - fieldTop) * 0.9 + h * 0.03
            let rw = w * (0.10 + CGFloat(g.next() % 100) / 100 * 0.16)
            ctx.fill(Path(ellipseIn: CGRect(x: x - rw, y: y, width: rw * 2, height: rw * 0.16)), with: .color(p.snowTop.opacity(0.65)))
        }
    }
}
