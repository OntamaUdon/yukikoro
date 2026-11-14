import SwiftUI

/// 雪だるまの表示。`scale` で図鑑用に小さく（足元そろえで）描ける。
struct SnowmanView: View {
    let species: Species
    let decorations: [Decoration]
    var scale: CGFloat = 1.0

    init(_ snowman: Snowman, scale: CGFloat = 1.0) {
        species = snowman.species
        decorations = snowman.decorations
        self.scale = scale
    }

    init(species: Species, decorations: [Decoration] = [], scale: CGFloat = 1.0) {
        self.species = species
        self.decorations = decorations
        self.scale = scale
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * scale
            let rect = CGRect(x: (size.width - side) / 2, y: size.height - side, width: side, height: side)
            SnowmanArt.draw(species: species, decorations: decorations, in: &context, rect: rect)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// 転がっている雪玉。`rotation` を withAnimation で変えると、ころころ回って見える。
struct RollingBall: View, Animatable {
    var rotation: Double

    var animatableData: Double {
        get { rotation }
        set { rotation = newValue }
    }

    var body: some View {
        Canvas { context, size in
            SnowballArt.draw(in: &context, rect: CGRect(origin: .zero, size: size), rotation: rotation)
        }
        .accessibilityHidden(true)
    }
}

enum BallScale {
    /// 歩数に対する雪玉の大きさ（0〜1）。2万歩で最大。
    static func fraction(_ steps: Int) -> Double {
        min(1, max(0, (Double(steps) / 20_000).squareRoot()))
    }

    static func diameter(steps: Int, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        minimum + (maximum - minimum) * CGFloat(fraction(steps))
    }
}

/// 歩数の表示用フォーマット
func formatSteps(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}
