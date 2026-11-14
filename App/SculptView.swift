import SwiftUI
import SceneKit
import simd

/// 雪玉を削ったり盛ったり色を塗ったりする編集の中身（3D の操作）。
@MainActor
final class SculptController: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    @Published var shape: SnowShape
    @Published var tool: SculptTool = .carve
    @Published var brushSize: Float = 0.32
    @Published var strength: Float = 1.0
    @Published var paintColor: UIColor = UIColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1)
    @Published private(set) var undoCount = 0

    let scene: SCNScene
    let cameraNode = SCNNode()
    private let rig: SkyRig
    private let meshNode = SCNNode()
    private let material = SnowMaterial.make()
    private let cursor = SCNNode()
    private var orbit = OrbitCamera(azimuth: 0.5, elevation: 0.25, distance: 4.6, target: .zero,
                                    minDistance: 2.4, maxDistance: 9, minElevation: -1.4, maxElevation: 1.4)
    private var undoStack: [SnowShape] = []
    private var strokePlane: (normal: SIMD3<Float>, depth: Float)?
    private weak var view: SCNView?
    private let original: SnowShape

    var hasChanges: Bool { shape != original }

    init(shape: SnowShape) {
        self.shape = shape
        original = shape
        let newScene = SCNScene()
        scene = newScene
        rig = SkyRig(scene: newScene, ground: false, shadows: false)
        super.init()
        rig.apply(hour: SkyClock.hour())

        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
        scene.rootNode.addChildNode(meshNode)

        let ball = SCNSphere(radius: 1)
        let cm = SCNMaterial()
        cm.lightingModel = .constant
        cm.diffuse.contents = UIColor(white: 1, alpha: 0.22)
        cm.writesToDepthBuffer = false
        ball.materials = [cm]
        cursor.geometry = ball
        cursor.isHidden = true
        cursor.renderingOrder = 10
        scene.rootNode.addChildNode(cursor)

        let cam = SCNCamera()
        cam.fieldOfView = 40
        SceneSetup.configure(camera: cam, exposure: -0.2)
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        orbit.apply(to: cameraNode)
    }

    func select(tool newTool: SculptTool) {
        tool = newTool
        cursor.isHidden = true
    }

    func attach(view: SCNView) {
        self.view = view
        let one = UIPanGestureRecognizer(target: self, action: #selector(onePan(_:)))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        let two = UIPanGestureRecognizer(target: self, action: #selector(twoPan(_:)))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        view.addGestureRecognizer(one)
        view.addGestureRecognizer(two)
        view.addGestureRecognizer(pinch)
    }

    // MARK: 操作

    @objc private func onePan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        if tool == .rotate {
            orbitBy(g, in: view)
            return
        }
        switch g.state {
        case .began:
            pushUndo()
            strokePlane = nil
            stroke(at: g.location(in: view), in: view)
        case .changed:
            stroke(at: g.location(in: view), in: view)
        case .ended, .cancelled, .failed:
            cursor.isHidden = true
            strokePlane = nil
        default:
            break
        }
    }

    @objc private func twoPan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        orbitBy(g, in: view)
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        orbit.zoom(scale: Float(g.scale))
        g.scale = 1
        orbit.apply(to: cameraNode)
    }

    private func orbitBy(_ g: UIPanGestureRecognizer, in view: SCNView) {
        let t = g.translation(in: view)
        g.setTranslation(.zero, in: view)
        orbit.rotate(dAzimuth: -Float(t.x) * 0.009, dElevation: Float(t.y) * 0.009)
        orbit.apply(to: cameraNode)
    }

    private func stroke(at point: CGPoint, in view: SCNView) {
        let options: [SCNHitTestOption: Any] = [
            .rootNode: meshNode,
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
        ]
        guard let hit = view.hitTest(point, options: options).first else {
            cursor.isHidden = true
            return
        }
        let local = SIMD3<Float>(Float(hit.localCoordinates.x), Float(hit.localCoordinates.y), Float(hit.localCoordinates.z))
        let length = simd_length(local)
        guard length > 1e-4 else { return }
        let dir = local / length

        cursor.isHidden = false
        cursor.simdPosition = SIMD3<Float>(Float(hit.worldCoordinates.x), Float(hit.worldCoordinates.y), Float(hit.worldCoordinates.z))
        cursor.simdScale = SIMD3<Float>(repeating: brushSize * 0.9)

        if tool == .flatten && strokePlane == nil {
            strokePlane = (dir, max(0.4, length * 0.99))
        }
        var color = SIMD3<Float>(1, 1, 1)
        if tool == .paint {
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            paintColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            color = SIMD3<Float>(Float(r), Float(g), Float(b))
        }
        shape.apply(tool: tool, direction: dir, size: brushSize, strength: strength, color: color, plane: strokePlane)
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }

    // MARK: やり直し

    private func pushUndo() {
        undoStack.append(shape)
        if undoStack.count > 25 { undoStack.removeFirst() }
        undoCount = undoStack.count
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        shape = last
        undoCount = undoStack.count
        meshNode.geometry = SculptMesh.geometry(for: shape, material: material)
    }

    func reset() {
        pushUndo()
        shape = SnowShape.pristine(seed: shape.seed)
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
}

/// 雪玉を削る・盛る・ならす・色を塗る画面
struct SculptView: View {
    let title: String
    let onDone: (SnowShape) -> Void
    let onCancel: () -> Void

    @StateObject private var c: SculptController
    @State private var confirmCancel = false

    init(shape: SnowShape, title: String, onDone: @escaping (SnowShape) -> Void, onCancel: @escaping () -> Void) {
        _c = StateObject(wrappedValue: SculptController(shape: shape))
        self.title = title
        self.onDone = onDone
        self.onCancel = onCancel
    }

    private static let swatches: [UIColor] = [
        UIColor(white: 1.0, alpha: 1),
        UIColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1),
        UIColor(red: 0.98, green: 0.58, blue: 0.20, alpha: 1),
        UIColor(red: 0.98, green: 0.85, blue: 0.25, alpha: 1),
        UIColor(red: 0.35, green: 0.75, blue: 0.40, alpha: 1),
        UIColor(red: 0.35, green: 0.75, blue: 0.95, alpha: 1),
        UIColor(red: 0.25, green: 0.40, blue: 0.90, alpha: 1),
        UIColor(red: 0.60, green: 0.40, blue: 0.85, alpha: 1),
        UIColor(red: 0.98, green: 0.60, blue: 0.75, alpha: 1),
        UIColor(red: 0.50, green: 0.33, blue: 0.22, alpha: 1),
        UIColor(white: 0.12, alpha: 1),
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
        .confirmationDialog("変えた内容を捨てますか？", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("捨てる", role: .destructive) { onCancel() }
            Button("続ける", role: .cancel) {}
        }
    }

    private var topBar: some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var panel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(SculptTool.allCases) { tool in
                    Button {
                        c.select(tool: tool)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tool.symbol)
                                .font(.system(size: 20))
                            Text(tool.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(c.tool == tool ? Palette.tint.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(c.tool == tool ? Palette.tint : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if c.tool == .rotate {
                Text("1本指でぐるっと回せます。つまんで拡大・縮小もできます。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    HStack {
                        Text("大きさ").font(.system(.caption, design: .rounded)).frame(width: 44, alignment: .leading)
                        Slider(value: $c.brushSize, in: 0.12...0.7)
                    }
                    HStack {
                        Text("強さ").font(.system(.caption, design: .rounded)).frame(width: 44, alignment: .leading)
                        Slider(value: $c.strength, in: 0.3...2)
                    }
                }
                if c.tool == .paint {
                    colorRow
                }
                Text("1本指でなぞる／2本指で回す・つまんで拡大")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
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

    private var colorRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, color in
                        Button {
                            c.paintColor = color
                        } label: {
                            Circle()
                                .fill(Color(color))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                                .overlay(
                                    Circle().stroke(Palette.tint, lineWidth: 3)
                                        .opacity(c.paintColor.isEqual(color) ? 1 : 0)
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
                get: { Color(c.paintColor) },
                set: { c.paintColor = UIColor($0) }
            ), supportsOpacity: false)
            .labelsHidden()
        }
    }
}
