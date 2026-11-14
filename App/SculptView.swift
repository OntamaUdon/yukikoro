import SwiftUI
import SceneKit
import simd

/// 雪玉を成形する操作の中身。
/// カメラは雪玉を真横から見る位置に固定。地面に垂直な刃（ヘラ）が雪玉の左側に浮いていて、
/// 指で上下左右に動かす。刃が雪玉に当たると、通った側が自動で削れる。
/// 雪玉の向きは、3つの軸まわりの回転ボタンで変える（削りながらでも回せる）。
@MainActor
final class SculptController: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    @Published var shape: SnowShape
    @Published var bladeSize: BladeSize = .medium {
        didSet { updateBladeNode() }
    }
    @Published var tintColor: UIColor
    @Published private(set) var undoCount = 0
    @Published var reverseSpin = false

    let scene: SCNScene
    let cameraNode = SCNNode()
    private let meshNode = SCNNode()
    private let bladeNode = SCNNode()
    private let material = SnowMaterial.make()
    private var rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var undoStack: [SnowShape] = []
    private let original: SnowShape
    private let baseRadius: Float
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0

    // 刃の位置（画面の座標。左側から入る）
    private var bladeX: Float = -2.0
    private var bladeY: Float = 0
    private var bladeActive = false
    private var bladeMoved = false
    private var strokeStartBlade = SIMD2<Float>(0, 0)
    private var strokeStartPoint = SIMD2<Float>(0, 0)
    private var strokeUndoPushed = false
    private var spin = SIMD3<Float>(0, 0, 0)
    private weak var view: SCNView?

    static let bladeXRange: ClosedRange<Float> = -2.3 ... -0.2
    static let bladeYRange: ClosedRange<Float> = -1.9 ... 1.9

    var hasChanges: Bool { shape != original }

    /// 雪玉の直径（メートル）。削った形の最大幅で測る。
    var diameter: Double { 2 * Double(baseRadius) * Double(shape.maxExtent) }

    init(shape: SnowShape, baseRadius: Float) {
        self.shape = shape
        self.baseRadius = baseRadius
        original = shape
        tintColor = UIColor(red: CGFloat(shape.tintRGB.x), green: CGFloat(shape.tintRGB.y), blue: CGFloat(shape.tintRGB.z), alpha: 1)
        let newScene = SCNScene()
        scene = newScene
        super.init()

        let daypart = Daypart.current(hour: Int(SkyClock.hour()))
        PhotoSky.apply(to: newScene, daypart: daypart, background: true)
        PhotoSky.addSun(to: newScene, daypart: daypart, intensity: 1100)

        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
        newScene.rootNode.addChildNode(meshNode)

        let box = SCNBox(width: 0.04, height: 1, length: 4, chamferRadius: 0.01)
        let bm = SCNMaterial()
        bm.lightingModel = .constant
        bm.diffuse.contents = UIColor(red: 0.75, green: 0.9, blue: 1.0, alpha: 0.55)
        bm.isDoubleSided = true
        bm.writesToDepthBuffer = false
        box.materials = [bm]
        bladeNode.geometry = box
        bladeNode.renderingOrder = 10
        newScene.rootNode.addChildNode(bladeNode)
        updateBladeNode()

        let cam = SCNCamera()
        cam.projectionDirection = .horizontal
        cam.fieldOfView = 40
        PhotoSky.configure(camera: cam, exposure: daypart == .day ? -0.5 : -0.2)
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 0, 6.8)
        newScene.rootNode.addChildNode(cameraNode)
    }

    // MARK: 準備と後片付け

    func attach(view: SCNView) {
        self.view = view
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    // MARK: 刃

    private func updateBladeNode() {
        (bladeNode.geometry as? SCNBox)?.height = CGFloat(bladeSize.height)
        bladeNode.simdPosition = SIMD3<Float>(bladeX, bladeY, 0)
    }

    /// 画面上の点を、雪玉の中心を通る奥行き0の面（z=0）の座標にする
    private func worldPoint(_ p: CGPoint, in view: SCNView) -> SIMD2<Float>? {
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let dz = far.z - near.z
        guard abs(dz) > 1e-6 else { return nil }
        let t = (0 - near.z) / dz
        return SIMD2<Float>(near.x + (far.x - near.x) * t, near.y + (far.y - near.y) * t)
    }

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        switch g.state {
        case .began:
            guard let w = worldPoint(g.location(in: view), in: view) else { return }
            bladeActive = true
            strokeStartPoint = w
            strokeStartBlade = SIMD2<Float>(bladeX, bladeY)
            strokeUndoPushed = false
        case .changed:
            guard bladeActive, let w = worldPoint(g.location(in: view), in: view) else { return }
            let d = w - strokeStartPoint
            bladeX = min(Self.bladeXRange.upperBound, max(Self.bladeXRange.lowerBound, strokeStartBlade.x + d.x))
            bladeY = min(Self.bladeYRange.upperBound, max(Self.bladeYRange.lowerBound, strokeStartBlade.y + d.y))
            bladeNode.simdPosition = SIMD3<Float>(bladeX, bladeY, 0)
            bladeMoved = true
            applyCut()
        case .ended, .cancelled, .failed:
            bladeActive = false
        default:
            break
        }
    }

    /// 刃が当たっている所を削る
    private func applyCut() {
        guard bladeActive else { return }
        var next = shape
        let half = bladeSize.height / 2
        let changed = next.cutBlade(rotation: rotation, planeX: bladeX, bandLow: bladeY - half, bandHigh: bladeY + half)
        guard changed else { return }
        if !strokeUndoPushed {
            pushUndo()
            strokeUndoPushed = true
        }
        shape = next
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }

    // MARK: 回転

    /// 回転ボタン。axis は 0=横軸 1=縦軸 2=奥行きの軸。押している間だけ回る。
    func setSpin(axis: Int, active: Bool) {
        guard (0..<3).contains(axis) else { return }
        spin[axis] = active ? 1 : 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTime == 0 ? 0 : Float(min(0.05, now - lastTime))
        lastTime = now
        var rotated = false
        if spin != SIMD3<Float>(0, 0, 0) {
            let axes: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
            let direction: Float = reverseSpin ? -1 : 1
            for i in 0..<3 where spin[i] != 0 {
                let q = simd_quatf(angle: 1.6 * dt * direction, axis: axes[i])
                rotation = simd_normalize(q * rotation)
            }
            meshNode.simdOrientation = rotation
            rotated = true
        }
        // 指で刃を押さえている間は、雪玉が回っても削り続ける
        if bladeActive, rotated || bladeMoved {
            bladeMoved = false
            applyCut()
        }
    }

    // MARK: 色・やり直し

    func setTint(_ color: UIColor) {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        pushUndo()
        tintColor = color
        shape.setTint(SIMD3<Float>(Float(r), Float(g), Float(b)))
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }

    private func pushUndo() {
        undoStack.append(shape)
        if undoStack.count > 25 { undoStack.removeFirst() }
        undoCount = undoStack.count
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        shape = last
        undoCount = undoStack.count
        let t = last.tintRGB
        tintColor = UIColor(red: CGFloat(t.x), green: CGFloat(t.y), blue: CGFloat(t.z), alpha: 1)
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }

    func reset() {
        pushUndo()
        shape = SnowShape.pristine(seed: shape.seed)
        tintColor = .white
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }
}

struct SculptCanvas: UIViewRepresentable {
    let controller: SculptController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.allowsCameraControl = false
        view.backgroundColor = .black
        controller.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: ()) {
        // 表示タイマーを止める（止めないとコントローラーが残り続ける）
        (uiView.gestureRecognizers ?? []).forEach { uiView.removeGestureRecognizer($0) }
    }
}

/// 雪玉を成形する画面
struct SculptView: View {
    let title: String
    let onDone: (SnowShape) -> Void
    let onCancel: () -> Void

    @StateObject private var c: SculptController
    @State private var confirmCancel = false

    /// - Parameter radius: この雪玉の基準の半径（直径の表示に使う）
    init(shape: SnowShape, title: String, radius: Float, onDone: @escaping (SnowShape) -> Void, onCancel: @escaping () -> Void) {
        _c = StateObject(wrappedValue: SculptController(shape: shape, baseRadius: radius))
        self.title = title
        self.onDone = onDone
        self.onCancel = onCancel
    }

    private static let swatches: [UIColor] = [
        UIColor(white: 1.0, alpha: 1),
        UIColor(red: 0.98, green: 0.62, blue: 0.62, alpha: 1),
        UIColor(red: 0.99, green: 0.78, blue: 0.55, alpha: 1),
        UIColor(red: 0.99, green: 0.93, blue: 0.55, alpha: 1),
        UIColor(red: 0.65, green: 0.88, blue: 0.62, alpha: 1),
        UIColor(red: 0.62, green: 0.84, blue: 0.98, alpha: 1),
        UIColor(red: 0.62, green: 0.68, blue: 0.98, alpha: 1),
        UIColor(red: 0.82, green: 0.68, blue: 0.95, alpha: 1),
        UIColor(red: 0.98, green: 0.72, blue: 0.84, alpha: 1),
        UIColor(red: 0.72, green: 0.58, blue: 0.46, alpha: 1),
    ]

    var body: some View {
        ZStack {
            SculptCanvas(controller: c)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                panel
            }
        }
        .onDisappear { c.stop() }
        .confirmationDialog("変えた内容を捨てますか？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("捨てる", role: .destructive) { onCancel() }
            Button("続ける", role: .cancel) {}
        }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Button("やめる") {
                    if c.hasChanges { confirmCancel = true } else { onCancel() }
                }
                Spacer()
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    c.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(c.undoCount == 0)
                Menu {
                    Button("さいしょの形にもどす", role: .destructive) { c.reset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button("完了") { onDone(c.shape) }
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            Text("直径 \(formatLength(meters: c.diameter))")
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
                Picker("刃の大きさ", selection: $c.bladeSize) {
                    ForEach(BladeSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }

            colorRow

            HStack(spacing: 8) {
                Text("回す")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                spinButton(axis: 0, label: "横軸", symbol: "arrow.up.arrow.down")
                spinButton(axis: 1, label: "縦軸", symbol: "arrow.left.arrow.right")
                spinButton(axis: 2, label: "奥軸", symbol: "arrow.clockwise")
                Toggle("逆", isOn: $c.reverseSpin)
                    .toggleStyle(.button)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
    private func spinButton(axis: Int, label: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Palette.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in c.setSpin(axis: axis, active: true) }
                .onEnded { _ in c.setSpin(axis: axis, active: false) }
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
                            c.setTint(color)
                        } label: {
                            Circle()
                                .fill(Color(color))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(
                                    Circle().stroke(Palette.tint, lineWidth: 3)
                                        .opacity(c.tintColor.isEqual(color) ? 1 : 0)
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
                get: { Color(c.tintColor) },
                set: { c.setTint(UIColor($0)) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}
