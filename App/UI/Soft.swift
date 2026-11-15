import SwiftUI
import UIKit

/// ソフトクレイモーフィズム + 雪。
/// - 背景は「雪の夕ぐれ」の、青みの空色。白い雪玉が、白い背景にとけないようにするため。雪は、舞う雪のつぶと、白いふっくらしたカードで出す。
/// - カードやボタンは、粘土のようにふくらんだ面: 明るい面、内がわの左上の白い光、右下の青いかげ、下へのびる青いやわらかい影。
/// - 文字は濃い紺。押せる所は、形・アイコンでも分かるようにする。
enum Soft {
    private typealias RGBA = (CGFloat, CGFloat, CGFloat, CGFloat)

    private static func dynamic(light: RGBA, dark: RGBA) -> UIColor {
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        }
    }

    // 画面の背景（上から下へ）
    static let uiSkyTop = dynamic(light: (0.56, 0.72, 0.93, 1), dark: (0.06, 0.09, 0.19, 1))
    static let uiSkyBottom = dynamic(light: (0.76, 0.86, 0.97, 1), dark: (0.13, 0.19, 0.33, 1))
    // 粘土の面
    static let uiSurface = dynamic(light: (0.965, 0.980, 1.0, 1), dark: (0.21, 0.28, 0.43, 1))
    static let uiWell = dynamic(light: (0.79, 0.87, 0.97, 1), dark: (0.11, 0.16, 0.27, 1))
    static let uiInk = dynamic(light: (0.10, 0.16, 0.30, 1), dark: (0.94, 0.97, 1.0, 1))
    static let uiAccent = dynamic(light: (0.16, 0.40, 0.86, 1), dark: (0.50, 0.72, 1.0, 1))

    static let skyTop = Color(uiSkyTop)
    static let skyBottom = Color(uiSkyBottom)
    static let surface = Color(uiSurface)
    static let well = Color(uiWell)
    static let ink = Color(uiInk)
    static let subInk = Color(uiInk).opacity(0.72)
    static let accent = Color(uiAccent)

    /// 内がわの光（左上）
    static let innerLight = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 1, alpha: 0.95) })
    /// 内がわのかげ（右下）
    static let innerShade = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.02, green: 0.05, blue: 0.12, alpha: 0.65) : UIColor(red: 0.50, green: 0.64, blue: 0.88, alpha: 0.60) })
    /// 面の下へのびる、やわらかい影
    static let drop = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.0, green: 0.02, blue: 0.08, alpha: 0.55) : UIColor(red: 0.20, green: 0.36, blue: 0.68, alpha: 0.38) })

    static let good = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.85, blue: 0.64, alpha: 1) : UIColor(red: 0.10, green: 0.50, blue: 0.34, alpha: 1) })
    static let warn = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0, green: 0.66, blue: 0.54, alpha: 1) : UIColor(red: 0.78, green: 0.24, blue: 0.20, alpha: 1) })
    static let gold = Color(red: 0.98, green: 0.74, blue: 0.20)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: 面

/// ふくらんだ粘土の面
struct SoftRaised: View {
    var radius: CGFloat = 26
    var depth: CGFloat = 1
    var fill: AnyShapeStyle = AnyShapeStyle(Soft.surface)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(fill)
            // 内がわの、左上の白い光
            .overlay(
                shape.stroke(Soft.innerLight, lineWidth: 7 * depth)
                    .blur(radius: 4 * depth)
                    .offset(x: 3 * depth, y: 3 * depth)
                    .mask(shape)
            )
            // 内がわの、右下の青いかげ
            .overlay(
                shape.stroke(Soft.innerShade, lineWidth: 9 * depth)
                    .blur(radius: 6 * depth)
                    .offset(x: -4 * depth, y: -5 * depth)
                    .mask(shape)
            )
            .shadow(color: Soft.drop, radius: 14 * depth, x: 0, y: 11 * depth)
    }
}

/// へこんだ面（棒の溝、数字の入れもの）
struct SoftInset: View {
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Soft.well)
            .overlay(
                shape.stroke(Soft.innerShade, lineWidth: 6)
                    .blur(radius: 4)
                    .offset(x: 2, y: 3)
                    .mask(shape)
            )
            .overlay(
                shape.stroke(Soft.innerLight, lineWidth: 5)
                    .blur(radius: 3)
                    .offset(x: -2, y: -3)
                    .mask(shape)
                    .opacity(0.7)
            )
    }
}

extension View {
    /// ふくらんだカード
    func softCard(radius: CGFloat = 26, depth: CGFloat = 1) -> some View {
        background(SoftRaised(radius: radius, depth: depth))
    }

    /// へこんだ面
    func softWell(radius: CGFloat = 20) -> some View {
        background(SoftInset(radius: radius))
    }

    /// 画面の背景（雪の夕ぐれの空色 + 舞う雪）
    func softScreen() -> some View {
        background(SoftBackground().ignoresSafeArea())
    }
}

struct SoftBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Soft.skyTop, Soft.skyBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.35), Color.clear], center: .init(x: 0.2, y: 0.0), startRadius: 0, endRadius: 420)
            SnowfallView()
        }
    }
}

/// 舞う雪のつぶ（軽い飾り。動きをへらす設定のときは止める）
struct SnowfallView: View {
    var count = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func fract(_ v: Double) -> Double { v - floor(v) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    let seed = Double(i) + 1
                    let baseX = fract(sin(seed * 12.9898) * 43_758.5453) * size.width
                    let x = baseX + sin(t * 0.5 + seed) * 12
                    let speed = 12 + 20 * fract(seed * 0.37)
                    let y = (fract(seed * 0.618) * (size.height + 30) + t * speed).truncatingRemainder(dividingBy: size.height + 30) - 15
                    let r = 1.3 + 2.8 * fract(seed * 0.91)
                    let alpha = 0.35 + 0.45 * fract(seed * 0.53)
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(Color.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: ボタン

struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    var radius: CGFloat = 24
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = AnyShapeStyle(LinearGradient(colors: [Color(red: 0.34, green: 0.60, blue: 0.98), Color(red: 0.15, green: 0.38, blue: 0.84)],
                                                startPoint: .top, endPoint: .bottom))
        configuration.label
            .font(Soft.font(17))
            .foregroundStyle(prominent ? Color.white : Soft.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background {
                if prominent {
                    SoftRaised(radius: radius, depth: configuration.isPressed ? 0.45 : 0.8, fill: tint)
                } else {
                    SoftRaised(radius: radius, depth: configuration.isPressed ? 0.45 : 0.8)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SoftIconButtonStyle: ButtonStyle {
    var size: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(Soft.accent)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Soft.surface)
                    .overlay(Circle().stroke(Soft.innerLight, lineWidth: 5).blur(radius: 3).offset(x: 2, y: 2).mask(Circle()))
                    .overlay(Circle().stroke(Soft.innerShade, lineWidth: 6).blur(radius: 4).offset(x: -3, y: -3).mask(Circle()))
                    .shadow(color: Soft.drop, radius: configuration.isPressed ? 4 : 9, x: 0, y: configuration.isPressed ? 3 : 7)
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: 部品

/// 棒（溝の中を、色つきの棒がのびる）
struct SoftBar: View {
    var fraction: Double
    var tint: Color = Soft.accent
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                SoftInset(radius: height / 2)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().fill(Color.white.opacity(0.35)).frame(height: height * 0.22).padding(.horizontal, height * 0.3).offset(y: -height * 0.18), alignment: .top)
                    .frame(width: max(height - 4, (geo.size.width - 4) * min(1, max(0, fraction))))
                    .padding(2)
            }
        }
        .frame(height: height)
    }
}

/// 小さな丸いふくらみ（数字や印）
struct SoftChip: View {
    var symbol: String?
    var text: String
    var tint: Color = Soft.ink

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text).monospacedDigit()
        }
        .font(Soft.font(13, .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .softWell(radius: 14)
    }
}

// MARK: 雪玉の絵

/// 雪玉の絵。ひと目で雪玉と分かるように: でこぼこの輪かく、ふんわり固まった雪のかたまり、うす青いかげ、白いつや、きらきらの結晶、足もとのかげ。
struct SnowBallDisc: View {
    var size: CGFloat
    /// 見た目のちがい（雪玉ごとに、でこぼこが変わる）
    var seed: UInt64 = 7

    var body: some View {
        Canvas { context, canvasSize in
            let radius = min(canvasSize.width, canvasSize.height) / 2 * 0.90
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 - radius * 0.04)
            var generator = SplitMix64(seed: seed &* 2_654_435_761 &+ 12_345)
            func random() -> CGFloat { CGFloat(generator.next() % 10_000) / 10_000 }

            // 足もとのかげ
            let shadowRect = CGRect(x: center.x - radius * 0.86, y: center.y + radius * 0.80, width: radius * 1.72, height: radius * 0.34)
            context.fill(Path(ellipseIn: shadowRect), with: .radialGradient(
                Gradient(colors: [Color(red: 0.20, green: 0.36, blue: 0.68).opacity(0.40), Color.clear]),
                center: CGPoint(x: shadowRect.midX, y: shadowRect.midY), startRadius: 0, endRadius: radius * 0.9))

            // でこぼこの輪かく
            let n = 30
            var points: [CGPoint] = []
            for k in 0..<n {
                let a = Double(k) / Double(n) * 2 * .pi
                let rr = radius * (1 + (random() - 0.5) * 0.07)
                points.append(CGPoint(x: center.x + CGFloat(cos(a)) * rr, y: center.y + CGFloat(sin(a)) * rr))
            }
            func mid(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2) }
            var outline = Path()
            outline.move(to: mid(points[n - 1], points[0]))
            for i in 0..<n {
                outline.addQuadCurve(to: mid(points[i], points[(i + 1) % n]), control: points[i])
            }
            outline.closeSubpath()

            // 雪のからだ（左上が白く、右下がうす青い）
            context.fill(outline, with: .radialGradient(
                Gradient(colors: [
                    Color.white,
                    Color(red: 0.95, green: 0.975, blue: 1.0),
                    Color(red: 0.83, green: 0.90, blue: 0.98),
                    Color(red: 0.66, green: 0.77, blue: 0.94),
                ]),
                center: CGPoint(x: center.x - radius * 0.32, y: center.y - radius * 0.38),
                startRadius: 0, endRadius: radius * 1.45))

            context.drawLayer { layer in
                layer.clip(to: outline)
                // ふんわり固まった雪のかたまり（左上は白、右下は青いかげ）
                for _ in 0..<22 {
                    let a = Double(random()) * 2 * .pi
                    let d = random() * radius * 0.85
                    let cr = radius * (0.08 + 0.16 * random())
                    let p = CGPoint(x: center.x + CGFloat(cos(a)) * d, y: center.y + CGFloat(sin(a)) * d)
                    let lowerRight = (p.x - center.x) + (p.y - center.y) > 0
                    let color = lowerRight
                        ? Color(red: 0.55, green: 0.68, blue: 0.90).opacity(0.20)
                        : Color.white.opacity(0.55)
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2)), with: .color(color))
                }
                // 小さなつぶつぶ（雪のざらざら）
                for _ in 0..<90 {
                    let a = Double(random()) * 2 * .pi
                    let d = CGFloat(sqrt(Double(random()))) * radius
                    let cr = radius * (0.012 + 0.03 * random())
                    let p = CGPoint(x: center.x + CGFloat(cos(a)) * d, y: center.y + CGFloat(sin(a)) * d)
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2)),
                               with: .color(Color(red: 0.50, green: 0.64, blue: 0.88).opacity(0.16)))
                }
                // ふちの青いかげ（右下ほど濃い）
                layer.stroke(outline, with: .linearGradient(
                    Gradient(colors: [Color.clear, Color(red: 0.42, green: 0.56, blue: 0.86).opacity(0.55)]),
                    startPoint: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.3),
                    endPoint: CGPoint(x: center.x + radius * 0.9, y: center.y + radius * 0.9)), lineWidth: radius * 0.34)
                // 左上の白いつや
                let shine = CGRect(x: center.x - radius * 0.72, y: center.y - radius * 0.78, width: radius * 0.8, height: radius * 0.5)
                layer.fill(Path(ellipseIn: shine), with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0)]),
                    center: CGPoint(x: shine.midX, y: shine.midY), startRadius: 0, endRadius: radius * 0.45))
            }

            // きらきらの結晶
            for _ in 0..<7 {
                let a = Double(random()) * 2 * .pi
                let d = CGFloat(sqrt(Double(random()))) * radius * 0.78
                let s = radius * (0.05 + 0.07 * random())
                let p = CGPoint(x: center.x + CGFloat(cos(a)) * d, y: center.y + CGFloat(sin(a)) * d)
                var star = Path()
                star.move(to: CGPoint(x: p.x - s, y: p.y)); star.addLine(to: CGPoint(x: p.x + s, y: p.y))
                star.move(to: CGPoint(x: p.x, y: p.y - s)); star.addLine(to: CGPoint(x: p.x, y: p.y + s))
                context.stroke(star, with: .color(Color.white.opacity(0.95)), style: StrokeStyle(lineWidth: max(0.8, s * 0.28), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
