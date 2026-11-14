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
