import SwiftUI

extension Daypart {
    /// いまの時間帯（デバッグ起動時は引数で上書きできる）
    static func now(_ date: Date = Date()) -> Daypart {
        var hour = Calendar.current.component(.hour, from: date)
        #if DEBUG
        if let override = DemoMode.hour { hour = override }
        #endif
        return Daypart.current(hour: hour)
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
