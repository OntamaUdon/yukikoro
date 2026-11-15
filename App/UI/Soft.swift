import SwiftUI
import UIKit

/// やわらかいニューモーフィズム + 雪のイメージ。背景と同じ色の面に、左上の白い光と右下の青みのかげを付けて、浮かせる。
/// 読みやすさのため、文字は濃い色。押せる所は、かげだけでなく、形・アイコンでも分かるようにする。
enum Soft {
    private static func dynamic(light: (CGFloat, CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> UIColor {
        UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        }
    }

    static let uiBackground = dynamic(light: (0.905, 0.937, 0.976, 1), dark: (0.105, 0.133, 0.200, 1))
    static let uiLight = dynamic(light: (1, 1, 1, 0.95), dark: (0.20, 0.25, 0.36, 0.75))
    static let uiShade = dynamic(light: (0.62, 0.70, 0.84, 0.60), dark: (0.02, 0.04, 0.08, 0.70))
    static let uiInk = dynamic(light: (0.13, 0.18, 0.30, 1), dark: (0.93, 0.96, 1.0, 1))
    static let uiAccent = dynamic(light: (0.22, 0.48, 0.88, 1), dark: (0.48, 0.70, 1.0, 1))

    static let background = Color(uiBackground)
    static let highlight = Color(uiLight)
    static let shade = Color(uiShade)
    static let ink = Color(uiInk)
    static let subInk = Color(uiInk).opacity(0.62)
    static let accent = Color(uiAccent)
    static let good = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.45, green: 0.82, blue: 0.62, alpha: 1) : UIColor(red: 0.16, green: 0.55, blue: 0.38, alpha: 1) })
    static let warn = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1.0, green: 0.62, blue: 0.50, alpha: 1) : UIColor(red: 0.80, green: 0.28, blue: 0.22, alpha: 1) })
    static let gold = Color(red: 0.96, green: 0.72, blue: 0.20)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: 面

/// 浮いた面（背景と同じ色）
struct SoftRaised: View {
    var radius: CGFloat = 24
    var depth: CGFloat = 1
    var fill: AnyShapeStyle = AnyShapeStyle(Soft.background)

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .shadow(color: Soft.highlight, radius: 7 * depth, x: -5 * depth, y: -5 * depth)
            .shadow(color: Soft.shade, radius: 9 * depth, x: 6 * depth, y: 7 * depth)
    }
}

/// へこんだ面（押している間、棒の溝、入力の欄）
struct SoftInset: View {
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Soft.background)
            .overlay(
                shape.stroke(Soft.shade, lineWidth: 5)
                    .blur(radius: 4)
                    .offset(x: 2, y: 3)
                    .mask(shape)
            )
            .overlay(
                shape.stroke(Soft.highlight, lineWidth: 5)
                    .blur(radius: 4)
                    .offset(x: -2, y: -3)
                    .mask(shape)
            )
    }
}

extension View {
    /// 浮いたカード
    func softCard(radius: CGFloat = 26, depth: CGFloat = 1) -> some View {
        background(SoftRaised(radius: radius, depth: depth))
    }

    /// へこんだ面
    func softWell(radius: CGFloat = 20) -> some View {
        background(SoftInset(radius: radius))
    }

    /// 画面の背景（雪のようなうす青の白）
    func softScreen() -> some View {
        background(SoftBackground().ignoresSafeArea())
    }
}

struct SoftBackground: View {
    var body: some View {
        ZStack {
            Soft.background
            LinearGradient(colors: [Color.white.opacity(0.35), Color.clear], startPoint: .top, endPoint: .center)
                .blendMode(.plusLighter)
                .opacity(0.5)
        }
    }
}

// MARK: ボタン

struct SoftButtonStyle: ButtonStyle {
    var prominent = false
    var radius: CGFloat = 22
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let tint = AnyShapeStyle(LinearGradient(colors: [Soft.accent.opacity(0.95), Soft.accent.opacity(0.78)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        configuration.label
            .font(Soft.font(17))
            .foregroundStyle(prominent ? Color.white : Soft.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                if configuration.isPressed {
                    SoftInset(radius: radius)
                } else if prominent {
                    SoftRaised(radius: radius, depth: 0.8, fill: tint)
                } else {
                    SoftRaised(radius: radius, depth: 0.8)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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
                if configuration.isPressed {
                    Circle().fill(Soft.background)
                        .overlay(Circle().stroke(Soft.shade, lineWidth: 4).blur(radius: 3).offset(x: 2, y: 3).mask(Circle()))
                } else {
                    Circle().fill(Soft.background)
                        .shadow(color: Soft.highlight, radius: 5, x: -4, y: -4)
                        .shadow(color: Soft.shade, radius: 7, x: 4, y: 5)
                }
            }
    }
}

// MARK: 部品

/// 棒（溝の中を、色つきの棒がのびる）
struct SoftBar: View {
    var fraction: Double
    var tint: Color = Soft.accent
    var height: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                SoftInset(radius: height / 2)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, fraction))))
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

/// 雪玉の絵（丸いふくらみ。大きさは見た目の目安）
struct SnowBallDisc: View {
    var size: CGFloat
    var face = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white, Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.74, green: 0.82, blue: 0.95)],
                    center: .init(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.78))
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.45, green: 0.55, blue: 0.75).opacity(0.35), radius: size * 0.08, x: size * 0.04, y: size * 0.06)
            if face {
                VStack(spacing: size * 0.05) {
                    HStack(spacing: size * 0.2) {
                        Circle().fill(Color(red: 0.14, green: 0.17, blue: 0.27)).frame(width: size * 0.09, height: size * 0.09)
                        Circle().fill(Color(red: 0.14, green: 0.17, blue: 0.27)).frame(width: size * 0.09, height: size * 0.09)
                    }
                    Capsule().fill(Color(red: 1.0, green: 0.58, blue: 0.20)).frame(width: size * 0.20, height: size * 0.08)
                }
                .offset(y: size * 0.02)
            }
        }
        .frame(width: size, height: size)
    }
}
