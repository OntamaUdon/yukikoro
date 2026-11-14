import SwiftUI
import simd

/// 切り落とした雪の破片（下へ落ちて消える）
private struct FallingFragment: Identifiable {
    let id = UUID()
    let points: [CGPoint]
    let color: Color
    let start: Date
    let drift: CGFloat
}

/// 育てる画面での、雪玉の置き場所（画面の座標）
private struct GrowGeometry {
    var center: CGPoint
    /// 基準の半径（点）
    var radius: CGFloat

    func unit(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2<Float>(Float((p.x - center.x) / radius), Float(-(p.y - center.y) / radius))
    }

    /// 雪玉の座標（回転前・単位）を画面の点にする
    func point(_ local: SIMD2<Float>, angle: Float) -> CGPoint {
        let c = cos(angle), s = sin(angle)
        let x = local.x * c - local.y * s
        let y = local.x * s + local.y * c
        return CGPoint(x: center.x + CGFloat(x) * radius, y: center.y - CGFloat(y) * radius)
    }
}

/// ゆきころさんぽのメイン画面。育てる（転がして、指でなぞって切る）と、飾る（ゆきだまを並べる）を、1つの画面で行き来する。
struct MainView: View {
    enum Mode { case grow, decorate }

    @Environment(GameStore.self) private var store
    @StateObject private var compose: ComposeModel
    @State private var mode: Mode
    /// 育てる画面で整えているゆきだま。nil なら、いま転がしている雪玉
    @State private var focusPiece: UUID?
    @State private var angle: Double = 0
    @State private var baseAngle: Double = 0
    @State private var history = ShapeHistory()
    @State private var strokeStart: CGPoint?
    @State private var strokeNow: CGPoint?
    @State private var preview: LineCut.Result?
    @State private var rotating = false
    @State private var blockStroke = false
    @State private var fragments: [FallingFragment] = []
    @State private var showColors = false
    @State private var showMenu = false
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @State private var frozenCamera: ArtworkCamera?
    @State private var dragging = false
    @State private var dragHit = false
    @AppStorage("didCut") private var didCut = false

    private let swatches: [Color] = [
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

    init(artwork: Artwork) {
        _compose = StateObject(wrappedValue: ComposeModel(artwork: artwork))
        var initial = Mode.grow
        #if DEBUG
        if DemoMode.isOn, DemoMode.decorates { initial = .decorate }
        #endif
        _mode = State(initialValue: initial)
    }

    private var daypart: Daypart { Daypart.current(hour: Int(SkyClock.hour())) }

    // MARK: 整えている雪玉

    private var focusShape: SnowShape {
        if let id = focusPiece, let p = compose.artwork.placements.first(where: { $0.id == id }) { return p.piece.shape }
        return store.state.rollingShape
    }

    private var focusRadiusMeters: Double {
        if let id = focusPiece, let p = compose.artwork.placements.first(where: { $0.id == id }) { return Double(p.piece.radius) }
        return BallScale.radius(steps: store.state.rollingSteps)
    }

    private var focusDiameter: Double { 2 * focusRadiusMeters * Double(focusShape.maxExtent) }

    private func setFocusShape(_ shape: SnowShape) {
        if let id = focusPiece {
            compose.updateShape(id: id, shape: shape)
        } else {
            store.updateRolling(shape: shape)
        }
    }

    // MARK: 本体

    var body: some View {
        ZStack {
            StoryBackground(daypart: daypart)
                .ignoresSafeArea()
            SnowFall(isDark: daypart.isDark)
            GeometryReader { geo in
                Group {
                    if mode == .grow {
                        growStage(size: geo.size)
                    } else {
                        decorateStage(size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                card
            }
        }
        .sheet(isPresented: $showMenu) { MenuSheet() }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivityView(items: [shareImage]) }
        }
        .onAppear {
            compose.onChange = { store.saveArtwork($0) }
            #if DEBUG
            if DemoMode.isOn, DemoMode.selectsPiece, mode == .decorate { compose.select(compose.artwork.placements.first?.id) }
            #endif
        }
        .onChange(of: store.state.rollingSteps) { old, new in
            history.clear()
            guard new > old, mode == .grow, focusPiece == nil else { return }
            let r = max(0.02, BallScale.radius(steps: new))
            let turn = min(3 * Double.pi, max(0.5, Double(new - old) * 0.02 / r))
            withAnimation(.easeInOut(duration: 1.4)) {
                angle -= turn
                baseAngle = angle
            }
        }
    }

    // MARK: 育てる

    private func growGeometry(size: CGSize) -> GrowGeometry {
        let maxR = size.width * 0.34
        let fraction = BallScale.displayFraction(radius: focusRadiusMeters)
        let r = max(5, maxR * CGFloat(fraction) / CGFloat(max(1, focusShape.maxExtent)))
        let groundY = size.height * 0.60
        return GrowGeometry(center: CGPoint(x: size.width / 2, y: groundY - r * 0.98), radius: r)
    }

    private func growStage(size: CGSize) -> some View {
        let g = growGeometry(size: size)
        let shape = preview?.shape ?? focusShape
        let groundY = size.height * 0.60
        return ZStack {
            Canvas { ctx, _ in
                SnowPainter.drawGroundShadow(in: &ctx, centerX: size.width / 2, groundY: groundY, width: g.radius * 2.4, opacity: 0.28)
            }
            SnowBallView(shape: shape, radius: Double(g.radius), angle: angle)
                .position(g.center)
            TimelineView(.animation(paused: fragments.isEmpty && preview == nil)) { timeline in
                Canvas { ctx, _ in
                    drawOverlay(&ctx, geometry: g, now: timeline.date)
                }
            }
            .allowsHitTesting(false)

            if !didCut && focusPiece == nil {
                hint("指でなぞって、雪玉を切ってみよう", icon: "hand.draw.fill")
                    .position(x: size.width / 2, y: max(150, g.center.y - g.radius - 54))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(cutGesture(g))
        .simultaneousGesture(rotateGesture)
        .animation(.easeOut(duration: 1.0), value: g.radius)
    }

    private func hint(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(Storybook.rounded(15))
        .foregroundStyle(Storybook.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .storyCard(corner: 22)
    }

    private func cutGesture(_ g: GrowGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !rotating, !blockStroke else { return }
                strokeStart = value.startLocation
                strokeNow = value.location
                preview = LineCut.apply(to: focusShape, angle: Float(angle), from: g.unit(value.startLocation), to: g.unit(value.location))
            }
            .onEnded { _ in
                defer { blockStroke = false }
                guard !rotating, !blockStroke, let result = preview else {
                    cancelStroke()
                    return
                }
                commitCut(result, g)
            }
    }

    private var rotateGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                rotating = true
                blockStroke = true
                cancelStroke()
                angle = baseAngle - value.radians
            }
            .onEnded { _ in
                baseAngle = angle
                rotating = false
            }
    }

    private func cancelStroke() {
        strokeStart = nil
        strokeNow = nil
        preview = nil
    }

    private func commitCut(_ result: LineCut.Result, _ g: GrowGeometry) {
        history.push(focusShape)
        let points = result.fragment.map { g.point($0, angle: Float(angle)) }
        let t = result.shape.tintRGB
        let fragment = FallingFragment(points: points, color: Color(red: Double(t.x), green: Double(t.y), blue: Double(t.z)),
                                       start: Date(), drift: CGFloat.random(in: -40...40))
        fragments.append(fragment)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.3))
            fragments.removeAll { $0.id == fragment.id }
        }
        setFocusShape(result.shape)
        didCut = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        cancelStroke()
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, geometry g: GrowGeometry, now: Date) {
        // なぞっている線と、切り落とされる所
        if let a = strokeStart, let b = strokeNow {
            if let preview {
                var path = Path()
                for (i, p) in preview.fragment.enumerated() {
                    let pt = g.point(p, angle: Float(angle))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(red: 1.0, green: 0.45, blue: 0.45).opacity(0.38)))
                ctx.stroke(path, with: .color(Color(red: 1.0, green: 0.4, blue: 0.4).opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 7, lineCap: .round))
            ctx.stroke(line, with: .color(Storybook.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [9, 8]))
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - 11, y: b.y - 11, width: 22, height: 22)), with: .color(Storybook.accent.opacity(0.85)))
            ctx.stroke(Path(ellipseIn: CGRect(x: b.x - 11, y: b.y - 11, width: 22, height: 22)), with: .color(.white), lineWidth: 2.5)
        }
        // 落ちていく破片
        for f in fragments {
            let t = now.timeIntervalSince(f.start)
            guard t >= 0, t < 1.3 else { continue }
            var path = Path()
            for (i, p) in f.points.enumerated() {
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            let fall = CGFloat(0.5 * 1_900 * t * t)
            ctx.drawLayer { layer in
                layer.opacity = max(0, 1 - t / 1.0)
                layer.translateBy(x: f.drift * CGFloat(t), y: fall)
                layer.fill(path, with: .color(f.color.opacity(0.92)))
                layer.stroke(path, with: .color(Color.white.opacity(0.7)), lineWidth: 1.2)
            }
        }
    }

    // MARK: 飾る

    private func decorateStage(size: CGSize) -> some View {
        let cam = frozenCamera ?? ArtworkCamera.fitting(compose.artwork.placements, size: size, bottomInset: 250)
        return ZStack {
            ArtworkStageView(placements: compose.artwork.placements, selectedID: compose.selectedID, camera: cam, daypart: daypart, showsBackground: false)
            if compose.artwork.placements.isEmpty {
                hint("下のトレイから、ゆきだまを置こう", icon: "arrow.down")
                    .position(x: size.width / 2, y: size.height * 0.34)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !dragging {
                        dragging = true
                        frozenCamera = cam
                        dragHit = compose.beginDrag(at: cam.world(value.startLocation))
                    }
                    if dragHit { compose.drag(to: cam.world(value.location)) }
                }
                .onEnded { value in
                    if dragHit {
                        compose.endDrag()
                    } else if hypot(value.translation.width, value.translation.height) < 8 {
                        compose.select(nil)
                    }
                    dragging = false
                    dragHit = false
                    frozenCamera = nil
                }
        )
    }

    // MARK: 上の帯

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "figure.walk")
                Text("今日 \(formatSteps(store.todaySteps))歩")
                    .monospacedDigit()
            }
            .font(Storybook.rounded(15))
            .foregroundStyle(Storybook.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .storyCard(corner: 20)

            // 一時的なテスト用（歩数を増やす）
            Menu {
                Button("+100歩") { store.addDebugSteps(100) }
                Button("+1,000歩") { store.addDebugSteps(1_000) }
                Button("+5,000歩") { store.addDebugSteps(5_000) }
                Button("+20,000歩") { store.addDebugSteps(20_000) }
            } label: {
                Text("テスト＋")
                    .font(Storybook.rounded(13))
                    .foregroundStyle(Storybook.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Storybook.warm.opacity(0.9)))
            }

            Spacer()

            if mode == .decorate, !compose.artwork.placements.isEmpty {
                Button {
                    compose.commit()
                    shareImage = renderShareImage()
                    showShare = shareImage != nil
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(StoryRoundButtonStyle())
            }
            Button {
                showMenu = true
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(StoryRoundButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    @MainActor
    private func renderShareImage() -> UIImage? {
        let size = CGSize(width: 360, height: 450)
        let view = ArtworkStageView(placements: compose.artwork.placements,
                                    camera: ArtworkCamera.fitting(compose.artwork.placements, size: size),
                                    daypart: daypart)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: 下のカード

    private var card: some View {
        VStack(spacing: 12) {
            modePill
            if mode == .grow {
                growControls
            } else {
                decorateControls
            }
        }
        .padding(16)
        .storyCard(corner: 32)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var modePill: some View {
        HStack(spacing: 4) {
            pillSegment("育てる", icon: "snowflake", selected: mode == .grow) {
                if mode != .grow { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .grow } }
            }
            pillSegment("飾る", icon: "sparkles", selected: mode == .decorate) {
                if mode != .decorate {
                    finishEditing()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .decorate }
                }
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.7)))
    }

    private func pillSegment(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(Storybook.rounded(16))
            .foregroundStyle(selected ? Color.white : Storybook.ink.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Capsule().fill(selected ? Storybook.accent : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // 育てる

    private var growControls: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                if focusPiece == nil {
                    Text("\(formatSteps(store.state.rollingSteps))歩")
                        .font(Storybook.rounded(30))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.6), value: store.state.rollingSteps)
                } else {
                    Text("ゆきだまを整え中")
                        .font(Storybook.rounded(20))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("直径")
                        .font(Storybook.rounded(11, .semibold))
                        .foregroundStyle(Storybook.ink.opacity(0.6))
                    Text(formatLength(meters: focusDiameter))
                        .font(Storybook.rounded(20))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(Storybook.ink)

            if showColors { colorRow }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showColors.toggle() }
                } label: {
                    Circle()
                        .fill(Color(red: Double(focusShape.tintRGB.x), green: Double(focusShape.tintRGB.y), blue: Double(focusShape.tintRGB.z)))
                        .overlay(Circle().stroke(Storybook.ink.opacity(0.25), lineWidth: 1.5))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(StoryRoundButtonStyle())

                Button {
                    if let previous = history.pop() { setFocusShape(previous) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(StoryRoundButtonStyle())
                .disabled(!history.canUndo)
                .opacity(history.canUndo ? 1 : 0.45)

                Spacer()

                if focusPiece == nil {
                    Button {
                        placeRolling()
                    } label: {
                        Label("飾りに置く", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                } else {
                    Button {
                        finishEditing()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .decorate }
                    } label: {
                        Label("できた", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                }
            }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                        Button {
                            setTint(rgb(of: color))
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Storybook.ink.opacity(0.2), lineWidth: 1.5))
                                .overlay(
                                    Circle().stroke(Storybook.accent, lineWidth: 3)
                                        .opacity(simd_distance(rgb(of: color), focusShape.tintRGB) < 0.02 ? 1 : 0)
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
                get: { Color(red: Double(focusShape.tintRGB.x), green: Double(focusShape.tintRGB.y), blue: Double(focusShape.tintRGB.z)) },
                set: { setTint(rgb(of: $0)) }
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

    private func setTint(_ rgb: SIMD3<Float>) {
        var s = focusShape
        guard s.tintRGB != rgb else { return }
        history.push(s)
        s.setTint(rgb)
        setFocusShape(s)
    }

    /// 転がしている雪玉を、ゆきだまとして取り出し、舞台に置く
    private func placeRolling() {
        guard let piece = store.makePiece(), let taken = store.takeFromStock(id: piece.id) else { return }
        compose.add(taken)
        history.clear()
        angle = 0
        baseAngle = 0
        showColors = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .decorate }
    }

    /// 置いたゆきだまの整え直しを終える
    private func finishEditing() {
        guard let id = focusPiece else { return }
        compose.setAngle(id: id, angle: Float(angle))
        focusPiece = nil
        history.clear()
        angle = 0
        baseAngle = 0
        showColors = false
    }

    // 飾る

    private var decorateControls: some View {
        VStack(spacing: 12) {
            if let p = compose.selected {
                VStack(spacing: 8) {
                    Text("直径 \(formatLength(meters: p.piece.diameter))")
                        .font(Storybook.rounded(13, .semibold))
                        .foregroundStyle(Storybook.ink.opacity(0.7))
                    HStack(spacing: 8) {
                        actionButton("まわす", "arrow.clockwise") { compose.rotateSelected(by: -.pi / 4) }
                        actionButton("おろす", "arrow.down.to.line") { compose.settleSelected() }
                        actionButton("切る", "scissors") { startEditing(p) }
                        actionButton("もどす", "tray.and.arrow.down") {
                            if let piece = compose.removeSelected() { store.returnToStock(piece) }
                        }
                    }
                }
            }
            tray
        }
    }

    private func startEditing(_ p: Placement) {
        focusPiece = p.id
        angle = Double(p.angle)
        baseAngle = angle
        history.clear()
        showColors = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = .grow }
    }

    private func actionButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold))
                Text(label).font(Storybook.rounded(12))
            }
            .foregroundStyle(Storybook.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.85)))
            .shadow(color: Storybook.shadow, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    /// 手元のゆきだま（タップで舞台に置く）
    private var tray: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.state.stock.isEmpty ? "手元のゆきだま：なし（「育てる」で作れます）" : "手元のゆきだま（タップで置く）")
                .font(Storybook.rounded(12, .semibold))
                .foregroundStyle(Storybook.ink.opacity(0.6))
            if !store.state.stock.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.state.stock) { piece in
                            Button {
                                if let taken = store.takeFromStock(id: piece.id) { compose.add(taken) }
                            } label: {
                                VStack(spacing: 3) {
                                    PieceThumbnail(piece: piece)
                                        .frame(width: 58, height: 58)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                        .shadow(color: Storybook.shadow, radius: 4, y: 2)
                                    Text(formatLength(meters: piece.diameter))
                                        .font(Storybook.rounded(10, .semibold))
                                        .foregroundStyle(Storybook.ink.opacity(0.7))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 共有シートを開く
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
