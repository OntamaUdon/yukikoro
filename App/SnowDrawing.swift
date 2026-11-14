import SwiftUI
import simd

/// 雪玉を2Dで描く（横から見た輪郭に、雪の陰影と細かな粒をつける）。3Dは使わないので軽い。
enum SnowPainter {
    /// 輪郭の線
    static func outline(_ shape: SnowShape, center: CGPoint, radius: CGFloat, angle: Float) -> Path {
        var path = Path()
        for k in 0..<shape.radii.count {
            let d = SnowShape.rotated(k, by: angle)
            let r = CGFloat(shape.radii[k]) * radius
            let p = CGPoint(x: center.x + CGFloat(d.x) * r, y: center.y - CGFloat(d.y) * r)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    static func draw(_ shape: SnowShape, in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, angle: Float) {
        guard radius > 0.5 else { return }
        let path = outline(shape, center: center, radius: radius, angle: angle)
        let t = shape.tintRGB
        func color(_ r: Float, _ g: Float, _ b: Float) -> Color {
            Color(red: Double(min(1, r)), green: Double(min(1, g)), blue: Double(min(1, b)))
        }
        let light = color(t.x * 0.5 + 0.5, t.y * 0.5 + 0.5, t.z * 0.5 + 0.5)
        let base = color(t.x * 0.93, t.y * 0.96, t.z)
        let shade = color(t.x * 0.60, t.y * 0.70, t.z * 0.88)

        // 陰影（左上から光が当たる）
        let highlight = CGPoint(x: center.x - radius * 0.38, y: center.y - radius * 0.42)
        ctx.fill(path, with: .radialGradient(
            Gradient(stops: [.init(color: light, location: 0), .init(color: base, location: 0.42), .init(color: shade, location: 1)]),
            center: highlight, startRadius: 0, endRadius: radius * 2.0))

        // 雪の粒（輪郭の中だけ。雪玉が回ると一緒に回る）
        ctx.drawLayer { layer in
            layer.clip(to: path)
            var g = SplitMix64(seed: UInt64(shape.seed) &+ 99)
            let c = cos(angle), s = sin(angle)
            for _ in 0..<34 {
                let ux = Float(g.next() % 2_000) / 1_000 - 1
                let uy = Float(g.next() % 2_000) / 1_000 - 1
                let size = CGFloat(g.next() % 100) / 100 * 0.035 + 0.012
                let wx = ux * c - uy * s, wy = ux * s + uy * c
                let p = CGPoint(x: center.x + CGFloat(wx) * radius * 0.95, y: center.y - CGFloat(wy) * radius * 0.95)
                let rect = CGRect(x: p.x - size * radius, y: p.y - size * radius, width: size * radius * 2, height: size * radius * 2)
                let bright = g.next() % 3 != 0
                layer.fill(Path(ellipseIn: rect), with: .color(bright ? Color.white.opacity(0.45) : shade.opacity(0.16)))
            }
        }
        ctx.stroke(path, with: .color(shade.opacity(0.55)), lineWidth: max(0.8, radius * 0.012))
    }

    /// 地面に落ちるやわらかい影
    static func drawGroundShadow(in ctx: inout GraphicsContext, centerX: CGFloat, groundY: CGFloat, width: CGFloat, opacity: Double) {
        guard width > 1 else { return }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: max(1, width * 0.06)))
            let rect = CGRect(x: centerX - width / 2, y: groundY - width * 0.07, width: width, height: width * 0.14)
            layer.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.12, green: 0.18, blue: 0.34).opacity(opacity)))
        }
    }
}

/// 雪玉の絵。大きさと向きはなめらかにアニメーションする。
struct SnowBallView: View, Animatable {
    var shape: SnowShape
    /// 基準の半径（点）
    var radius: Double
    /// 向き（ラジアン）
    var angle: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(radius, angle) }
        set {
            radius = newValue.first
            angle = newValue.second
        }
    }

    var body: some View {
        let side = max(2, CGFloat(radius) * 2 * CGFloat(shape.maxExtent) + 6)
        Canvas { ctx, size in
            SnowPainter.draw(shape, in: &ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: CGFloat(radius), angle: Float(angle))
        }
        .frame(width: side, height: side)
    }
}

/// ゆきだまの小さな絵
struct PieceThumbnail: View {
    let piece: SnowPiece

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [Color(red: 0.80, green: 0.90, blue: 0.99), Color(red: 0.95, green: 0.98, blue: 1.0)],
                               startPoint: .top, endPoint: .bottom)
                SnowBallView(shape: piece.shape, radius: Double(side) * 0.40 / Double(max(1, piece.shape.maxExtent)), angle: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// 作品の絵（横から見た2D）。一覧のサムネイルや、共有する画像にも使う。
struct ArtworkStageView: View {
    let placements: [Placement]
    var selectedID: UUID?
    let camera: ArtworkCamera
    let daypart: Daypart
    /// 背景を自分で描くか（メイン画面では、背景は別に描くので false）
    var showsBackground = true

    var body: some View {
        ZStack {
            if showsBackground { StoryBackground(daypart: daypart) }
            Canvas { ctx, size in
                for p in placements {
                    let lift = max(0, p.position.y - p.piece.radius)
                    let width = CGFloat(p.reach) * camera.scale * 2 * 0.9
                    SnowPainter.drawGroundShadow(in: &ctx, centerX: camera.point(p.position).x, groundY: camera.groundY,
                                                 width: width, opacity: max(0.08, 0.32 - Double(lift) * 0.12))
                }
                for p in placements {
                    let c = camera.point(p.position)
                    SnowPainter.draw(p.piece.shape, in: &ctx, center: c, radius: CGFloat(p.piece.radius) * camera.scale, angle: p.angle)
                    if p.id == selectedID {
                        let r = CGFloat(p.reach) * camera.scale + 6
                        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                        ctx.stroke(ring, with: .color(Color(red: 0.25, green: 0.55, blue: 1.0)), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    }
                }
            }
        }
    }
}

/// 一覧に出す作品の小さな絵
struct ArtworkThumbnail: View {
    let artwork: Artwork

    var body: some View {
        GeometryReader { geo in
            ArtworkStageView(placements: artwork.placements, camera: ArtworkCamera.fitting(artwork.placements, size: geo.size),
                             daypart: Daypart.current(hour: Int(SkyClock.hour())))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
