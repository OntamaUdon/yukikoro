import SwiftUI
import SceneKit
import simd

/// 作品を組み立てる（ゆきだまを置く・動かす・積む・向きを変える）操作の中身。
@MainActor
final class ComposeController: NSObject, ObservableObject, UIGestureRecognizerDelegate {
    @Published var artwork: Artwork
    @Published private(set) var selectedID: UUID?
    let world: ArtworkWorld
    var onChange: ((Artwork) -> Void)?
    private weak var view: SCNView?

    private enum Drag {
        case orbit
        case move(offset: SIMD2<Float>, planeY: Float, id: UUID)
    }
    private var drag: Drag = .orbit

    init(artwork: Artwork) {
        self.artwork = artwork
        world = ArtworkWorld(daypart: Daypart.current(hour: Int(SkyClock.hour())))
        super.init()
        world.sync(artwork.placements)
        world.frameAll(artwork.placements)
    }

    var selected: Placement? {
        guard let id = selectedID else { return nil }
        return artwork.placements.first { $0.id == id }
    }

    func attach(view: SCNView) {
        self.view = view
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        let one = UIPanGestureRecognizer(target: self, action: #selector(onePan(_:)))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(one)
        view.addGestureRecognizer(pinch)
    }

    // MARK: 操作

    private func pieceID(at point: CGPoint, in view: SCNView) -> UUID? {
        let options: [SCNHitTestOption: Any] = [.searchMode: SCNHitTestSearchMode.all.rawValue]
        for r in view.hitTest(point, options: options) {
            if let id = ArtworkWorld.pieceID(of: r.node) { return id }
        }
        return nil
    }

    private func planePoint(_ p: CGPoint, y: Float, in view: SCNView) -> SIMD3<Float>? {
        let near = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 0))
        let far = view.unprojectPoint(SCNVector3(Float(p.x), Float(p.y), 1))
        let o = SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z))
        let d = SIMD3<Float>(Float(far.x), Float(far.y), Float(far.z)) - o
        guard abs(d.y) > 1e-6 else { return nil }
        let t = (y - o.y) / d.y
        guard t > 0 else { return nil }
        var hit = o + d * t
        hit.x = min(40, max(-40, hit.x))
        hit.z = min(40, max(-40, hit.z))
        return hit
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        guard let view else { return }
        select(pieceID(at: g.location(in: view), in: view))
    }

    @objc private func onePan(_ g: UIPanGestureRecognizer) {
        guard let view else { return }
        switch g.state {
        case .began:
            let p = g.location(in: view)
            drag = .orbit
            if let id = pieceID(at: p, in: view), let placement = artwork.placements.first(where: { $0.id == id }) {
                select(id)
                if let hit = planePoint(p, y: placement.position.y, in: view) {
                    drag = .move(offset: SIMD2<Float>(placement.position.x - hit.x, placement.position.z - hit.z),
                                 planeY: placement.position.y, id: id)
                }
            }
        case .changed:
            switch drag {
            case .orbit:
                let t = g.translation(in: view)
                g.setTranslation(.zero, in: view)
                world.orbit.rotate(dAzimuth: -Float(t.x) * 0.009, dElevation: Float(t.y) * 0.009)
                world.applyOrbit()
            case let .move(offset, planeY, id):
                guard let hit = planePoint(g.location(in: view), y: planeY, in: view),
                      let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return }
                let x = hit.x + offset.x
                let z = hit.z + offset.y
                let r = artwork.placements[i].piece.radius
                artwork.placements[i].position = SIMD3<Float>(
                    x, Artwork.settleHeight(x: x, z: z, radius: r, among: artwork.placements, excluding: id), z)
                world.sync(artwork.placements, selected: selectedID)
            }
        case .ended, .cancelled, .failed:
            if case .move = drag { commit() }
            drag = .orbit
        default:
            break
        }
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        world.orbit.zoom(scale: Float(g.scale))
        g.scale = 1
        world.applyOrbit()
    }

    // MARK: 編集

    func select(_ id: UUID?) {
        selectedID = id
        world.sync(artwork.placements, selected: id)
    }

    /// 見た目を更新して、変更を保存する
    func commit() {
        artwork.updatedAt = Date()
        world.sync(artwork.placements, selected: selectedID)
        onChange?(artwork)
    }

    func add(_ piece: SnowPiece) {
        let r = piece.radius
        var x: Float = 0
        if let edge = artwork.placements.map({ $0.position.x + $0.piece.radius }).max() {
            x = edge + r + 0.2
        }
        let y = Artwork.settleHeight(x: x, z: 0, radius: r, among: artwork.placements)
        let isFirst = artwork.placements.isEmpty
        artwork.placements.append(Placement(piece: piece, position: SIMD3<Float>(x, y, 0)))
        selectedID = piece.id
        commit()
        world.frameAll(artwork.placements)
        _ = isFirst
    }

    /// 選んだゆきだまを作品から外す（呼び出し側でストックに戻す）
    func removeSelected() -> SnowPiece? {
        guard let id = selectedID, let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return nil }
        let piece = artwork.placements.remove(at: i).piece
        selectedID = nil
        commit()
        return piece
    }

    func rotateSelected(yaw: Float, pitch: Float) {
        guard let id = selectedID, let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return }
        let q = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0)) * artwork.placements[i].orientation
        artwork.placements[i].orientation = simd_normalize(q)
        commit()
    }

    func setHeight(_ y: Float) {
        guard let id = selectedID, let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return }
        artwork.placements[i].position.y = y
        world.sync(artwork.placements, selected: selectedID)
    }

    func settleSelected() {
        guard let id = selectedID, let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return }
        let p = artwork.placements[i]
        artwork.placements[i].position.y = Artwork.settleHeight(
            x: p.position.x, z: p.position.z, radius: p.piece.radius, among: artwork.placements, excluding: id)
        commit()
    }

    func updateShape(id: UUID, shape: SnowShape) {
        guard let i = artwork.placements.firstIndex(where: { $0.id == id }) else { return }
        artwork.placements[i].piece.shape = shape
        commit()
    }
}

struct ComposeCanvas: UIViewRepresentable {
    let controller: ComposeController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.world.scene
        view.pointOfView = controller.world.cameraNode
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

private struct SculptTarget: Identifiable {
    let id: UUID
    let shape: SnowShape
    let radius: Float
}

/// 作品をつくる画面
struct ComposeView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var c: ComposeController
    @State private var showStock = false
    @State private var sculpt: SculptTarget?
    @State private var shareImage: UIImage?
    @State private var showShare = false

    init(artwork: Artwork) {
        _c = StateObject(wrappedValue: ComposeController(artwork: artwork))
    }

    var body: some View {
        ZStack {
            ComposeCanvas(controller: c)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .onAppear {
            c.onChange = { store.saveArtwork($0) }
            #if DEBUG
            if DemoMode.isOn, DemoMode.selectsPiece { c.select(c.artwork.placements.first?.id) }
            #endif
        }
        .sheet(isPresented: $showStock) { stockPicker }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivityView(items: [shareImage]) }
        }
        .fullScreenCover(item: $sculpt) { target in
            SculptView(shape: target.shape, title: "ゆきだまを整える", radius: target.radius,
                       onDone: { shape in
                           c.updateShape(id: target.id, shape: shape)
                           sculpt = nil
                       },
                       onCancel: { sculpt = nil })
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("完了") {
                c.commit()
                dismiss()
            }
            .font(.system(.body, design: .rounded, weight: .bold))
            TextField("作品の名前", text: $c.artwork.name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { c.commit() }
            Button {
                c.commit()
                shareImage = SceneSnapshot.artwork(c.artwork, daypart: Daypart.current(hour: Int(SkyClock.hour())), size: CGSize(width: 360, height: 450), scale: 3, useCache: false)
                showShare = shareImage != nil
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(c.artwork.placements.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if let p = c.selected {
                selectedPanel(p)
            } else {
                Text(c.artwork.placements.isEmpty
                     ? "「ゆきだまを置く」で、作ったゆきだまを並べましょう。"
                     : "ゆきだまをドラッグで動かせます（別のゆきだまの上に重ねると積めます）。何もない所をなぞると見回せます。")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                showStock = true
            } label: {
                Label("ゆきだまを置く（\(store.state.stock.count)こ）", systemImage: "plus.circle.fill")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func selectedPanel(_ p: Placement) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                actionButton("まわす", "arrow.clockwise") { c.rotateSelected(yaw: .pi / 4, pitch: 0) }
                actionButton("かたむける", "arrow.triangle.2.circlepath") { c.rotateSelected(yaw: 0, pitch: .pi / 4) }
                actionButton("おろす", "arrow.down.to.line") { c.settleSelected() }
                actionButton("整える", "scissors") { sculpt = SculptTarget(id: p.id, shape: p.piece.shape, radius: p.piece.radius) }
                actionButton("もどす", "tray.and.arrow.down") {
                    if let piece = c.removeSelected() { store.returnToStock(piece) }
                }
            }
            HStack {
                Text("高さ").font(.system(.caption, design: .rounded)).frame(width: 36, alignment: .leading)
                Slider(
                    value: Binding(get: { c.selected?.position.y ?? 0 }, set: { c.setHeight($0) }),
                    in: p.piece.radius * 0.5...12,
                    onEditingChanged: { editing in if !editing { c.commit() } }
                )
            }
        }
    }

    private func actionButton(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Palette.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var stockPicker: some View {
        NavigationStack {
            Group {
                if store.state.stock.isEmpty {
                    ContentUnavailableView("ゆきだまがありません", systemImage: "circle.dotted",
                                           description: Text("ホームで雪玉を転がして形を整え、「作品に使う」を押すと増えます。"))
                } else {
                    List(store.state.stock) { piece in
                        Button {
                            if let taken = store.takeFromStock(id: piece.id) {
                                c.add(taken)
                            }
                            showStock = false
                        } label: {
                            HStack(spacing: 14) {
                                PieceThumbnail(piece: piece, size: CGSize(width: 120, height: 120))
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(formatSteps(piece.steps))歩ぶん")
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                    Text("直径 \(formatLength(meters: piece.diameter))")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("ゆきだまを置く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showStock = false } }
            }
        }
        .presentationDetents([.medium, .large])
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
