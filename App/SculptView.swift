import SwiftUI
import simd

/// 雪玉を成形する画面（横から見た2D）。
/// 雪玉の左側に、縦の刃が浮いている。指で上下左右に動かすと、刃が雪玉に当たった所から、通った側が自動で削れる。
/// 雪玉は、回転ボタンを押している間まわる（刃を押さえたまま回せば、回りながら削れる）。
struct SculptView: View {
    let title: String
    let onDone: (SnowShape) -> Void
    let onCancel: () -> Void

    @StateObject private var model: SculptModel
    @State private var dragging = false
    @State private var confirmCancel = false
    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let daypart = Daypart.current(hour: Int(SkyClock.hour()))

    /// - Parameter radius: この雪玉の基準の半径（直径の表示に使う）
    init(shape: SnowShape, title: String, radius: Float, onDone: @escaping (SnowShape) -> Void, onCancel: @escaping () -> Void) {
        _model = StateObject(wrappedValue: SculptModel(shape: shape, baseRadius: radius))
        self.title = title
        self.onDone = onDone
        self.onCancel = onCancel
    }

    private static let swatches: [Color] = [
        Color(red: 1.00, green: 1.00, blue: 1.00),
        Color(red: 0.98, green: 0.62, blue: 0.62),
        Color(red: 0.99, green: 0.78, blue: 0.55),
        Color(red: 0.99, green: 0.93, blue: 0.55),
        Color(red: 0.65, green: 0.88, blue: 0.62),
        Color(red: 0.62, green: 0.84, blue: 0.98),
        Color(red: 0.62, green: 0.68, blue: 0.98),
        Color(red: 0.82, green: 0.68, blue: 0.95),
        Color(red: 0.98, green: 0.72, blue: 0.84),
        Color(red: 0.72, green: 0.58, blue: 0.46),
    ]

    var body: some View {
        ZStack {
            DaypartBackground(daypart: daypart)
                .ignoresSafeArea()
            if daypart == .day {
                Color.white.opacity(0.10).ignoresSafeArea()
            }
            GeometryReader { geo in
                stage(size: geo.size)
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }
        }
        .onReceive(timer) { now in model.tick(now: now) }
        .confirmationDialog("変えた内容を捨てますか？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("捨てる", role: .destructive) { onCancel() }
            Button("続ける", role: .cancel) {}
        }
    }

    // MARK: 舞台（雪玉と刃）

    private func stage(size: CGSize) -> some View {
        let radius = size.width * 0.24
        let center = CGPoint(x: size.width / 2, y: size.height * 0.40)
        return Canvas { ctx, _ in
            SnowPainter.drawGroundShadow(in: &ctx, centerX: center.x, groundY: center.y + radius * 1.12, width: radius * 2.2, opacity: 0.25)
            SnowPainter.draw(model.shape, in: &ctx, center: center, radius: radius, angle: model.angle)
            drawBlade(&ctx, center: center, radius: radius)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        model.beginBlade()
                    }
                    model.dragBlade(translation: SIMD2<Float>(Float(value.translation.width / radius),
                                                              Float(-value.translation.height / radius)))
                }
                .onEnded { _ in
                    dragging = false
                    model.endBlade()
                }
        )
    }

    private func drawBlade(_ ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let h = CGFloat(model.bladeSize.height) * radius
        let x = center.x + CGFloat(model.bladeX) * radius
        let yMid = center.y - CGFloat(model.bladeY) * radius
        let width = max(7, radius * 0.07)
        let rect = CGRect(x: x - width / 2, y: yMid - h / 2, width: width, height: h)
        let plate = Path(roundedRect: rect, cornerRadius: width / 2)
        ctx.fill(plate, with: .color(Color(red: 0.80, green: 0.92, blue: 1.0).opacity(model.bladeActive ? 0.95 : 0.78)))
        ctx.stroke(plate, with: .color(Color(red: 0.25, green: 0.45, blue: 0.85)), lineWidth: 1.5)
        // 握る所（指で動かす印）
        let grip = CGRect(x: x - 16, y: yMid - 16, width: 32, height: 32)
        ctx.fill(Path(ellipseIn: grip), with: .color(Color(red: 0.25, green: 0.45, blue: 0.85).opacity(0.85)))
        ctx.stroke(Path(ellipseIn: grip), with: .color(.white), lineWidth: 2)
        // 進む向きの印
        var arrow = Path()
        arrow.move(to: CGPoint(x: x + width / 2 + 4, y: yMid - 7))
        arrow.addLine(to: CGPoint(x: x + width / 2 + 13, y: yMid))
        arrow.addLine(to: CGPoint(x: x + width / 2 + 4, y: yMid + 7))
        ctx.stroke(arrow, with: .color(Color(red: 0.25, green: 0.45, blue: 0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    // MARK: 上と下の操作

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button("やめる") {
                    if model.hasChanges { confirmCancel = true } else { onCancel() }
                }
                Spacer()
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(model.undoCount == 0)
                Menu {
                    Button("さいしょの形にもどす", role: .destructive) { model.reset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button("完了") { onDone(model.shape) }
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            Text("直径 \(formatLength(meters: model.diameter))")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            Text("指で刃を動かします。刃が雪玉に当たると、通った側が削れます。")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text("刃")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Picker("刃の大きさ", selection: $model.bladeSize) {
                    ForEach(BladeSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            colorRow

            HStack(spacing: 10) {
                Text("回す")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                spinButton(direction: 1, label: "左回り", symbol: "arrow.counterclockwise")
                spinButton(direction: -1, label: "右回り", symbol: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// 押している間だけ回るボタン。別の指で刃を動かしながらでも押せる。
    private func spinButton(direction: Int, label: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(label).font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Palette.tint.opacity(model.spin == direction ? 0.35 : 0.15), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.spin = direction }
                .onEnded { _ in if model.spin == direction { model.spin = 0 } }
        )
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            Text("色")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, color in
                        Button {
                            model.setTint(rgb(of: color))
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(
                                    Circle().stroke(Palette.tint, lineWidth: 3)
                                        .opacity(isCurrent(color) ? 1 : 0)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 4)
            }
            ColorPicker("", selection: Binding(
                get: { Color(red: Double(model.shape.tintRGB.x), green: Double(model.shape.tintRGB.y), blue: Double(model.shape.tintRGB.z)) },
                set: { model.setTint(rgb(of: $0)) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }

    private func rgb(of color: Color) -> SIMD3<Float> {
        let ui = UIColor(color)
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD3<Float>(Float(r), Float(g), Float(b))
    }

    private func isCurrent(_ color: Color) -> Bool {
        simd_distance(rgb(of: color), model.shape.tintRGB) < 0.02
    }
}
