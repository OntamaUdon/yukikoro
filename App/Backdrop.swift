import SwiftUI

/// 時間帯で変わる空の色
struct SkyTheme {
    let top: Color
    let bottom: Color
    let isDark: Bool

    var text: Color { isDark ? .white : Palette.ink }
    var secondaryText: Color { isDark ? Color.white.opacity(0.75) : Palette.ink.opacity(0.65) }

    static func current(_ date: Date = Date()) -> SkyTheme {
        var hour = Calendar.current.component(.hour, from: date)
        #if DEBUG
        if let override = DemoMode.hour { hour = override }
        #endif
        switch hour {
        case 5..<8:
            return SkyTheme(top: Color(red: 0.99, green: 0.84, blue: 0.80), bottom: Color(red: 0.80, green: 0.89, blue: 0.98), isDark: false)
        case 8..<16:
            return SkyTheme(top: Color(red: 0.74, green: 0.88, blue: 0.98), bottom: Color(red: 0.92, green: 0.96, blue: 1.0), isDark: false)
        case 16..<19:
            return SkyTheme(top: Color(red: 0.96, green: 0.78, blue: 0.72), bottom: Color(red: 0.62, green: 0.71, blue: 0.90), isDark: false)
        default:
            return SkyTheme(top: Color(red: 0.11, green: 0.17, blue: 0.33), bottom: Color(red: 0.30, green: 0.37, blue: 0.62), isDark: true)
        }
    }
}

struct SkyBackground: View {
    let theme: SkyTheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.top, theme.bottom], startPoint: .top, endPoint: .bottom)
            if theme.isDark {
                Canvas { ctx, size in
                    for i in 0..<40 {
                        let seed = Double(i) * 37.7
                        let x = (sin(seed) * 0.5 + 0.5) * size.width
                        let y = (sin(seed * 1.3) * 0.5 + 0.5) * size.height * 0.55
                        let s = 1.0 + (sin(seed * 2.1) * 0.5 + 0.5) * 1.6
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(0.75)))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// ゆっくり降り続ける雪
struct SnowFall: View {
    var isDark: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<60 {
                    let seed = Double(i) * 12.9898
                    let rx = fraction(sin(seed) * 43758.5453)
                    let ry = fraction(sin(seed * 1.7) * 24634.6345)
                    let rs = fraction(sin(seed * 2.3) * 9137.31)
                    let speed = 0.015 + 0.03 * rs
                    let diameter = 2.0 + 3.5 * rs
                    let y = fraction(ry + t * speed) * (size.height + 20) - 10
                    let x = rx * size.width + sin(t * 0.5 + seed) * 14
                    let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(isDark ? 0.8 : 0.95)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func fraction(_ v: Double) -> Double { v - floor(v) }
}

/// なだらかな雪の丘
struct HillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.height * 0.22))
        p.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.10),
            control1: CGPoint(x: rect.width * 0.30, y: -rect.height * 0.04),
            control2: CGPoint(x: rect.width * 0.70, y: rect.height * 0.30)
        )
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

struct SnowGround: View {
    let isDark: Bool

    var body: some View {
        ZStack {
            HillShape()
                .fill(LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.62, green: 0.69, blue: 0.88), Color(red: 0.42, green: 0.50, blue: 0.74)]
                        : [Color(red: 0.88, green: 0.94, blue: 1.0), Color(red: 0.76, green: 0.86, blue: 0.96)],
                    startPoint: .top, endPoint: .bottom))
                .offset(y: 24)
            HillShape()
                .fill(LinearGradient(
                    colors: isDark
                        ? [Color(red: 0.80, green: 0.85, blue: 0.97), Color(red: 0.55, green: 0.62, blue: 0.85)]
                        : [Color.white, Color(red: 0.86, green: 0.93, blue: 0.99)],
                    startPoint: .top, endPoint: .bottom))
                .scaleEffect(x: -1, y: 1)
                .offset(y: 56)
        }
    }
}
