import SwiftUI
import simd

private struct SculptTarget: Identifiable {
    let id: UUID
    let shape: SnowShape
    let radius: Float
}

/// 作品をつくる画面（横から見た2D）。ゆきだまをドラッグで好きな所に置く。
/// 地面や下のゆきだまの近くで離すと、ぴたっと乗る。
struct ComposeView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ComposeModel
    @State private var showStock = false
    @State private var sculpt: SculptTarget?
    @State private var shareImage: UIImage?
    @State private var showShare = false
    @State private var frozenCamera: ArtworkCamera?
    @State private var dragging = false
    @State private var dragHit = false
    private let daypart = Daypart.current(hour: Int(SkyClock.hour()))

    init(artwork: Artwork) {
        _model = StateObject(wrappedValue: ComposeModel(artwork: artwork))
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                stage(size: geo.size)
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .onAppear {
            model.onChange = { store.saveArtwork($0) }
            #if DEBUG
            if DemoMode.isOn, DemoMode.selectsPiece { model.select(model.artwork.placements.first?.id) }
            #endif
        }
        .sheet(isPresented: $showStock) { stockPicker }
        .sheet(isPresented: $showShare) {
            if let shareImage { ActivityView(items: [shareImage]) }
        }
        .fullScreenCover(item: $sculpt) { target in
            SculptView(shape: target.shape, title: "ゆきだまを整える", radius: target.radius,
                       onDone: { shape in
                           model.updateShape(id: target.id, shape: shape)
                           sculpt = nil
                       },
                       onCancel: { sculpt = nil })
        }
    }

    // MARK: 舞台

    private func stage(size: CGSize) -> some View {
        let cam = frozenCamera ?? ArtworkCamera.fitting(model.artwork.placements, size: size)
        return ArtworkStageView(placements: model.artwork.placements, selectedID: model.selectedID, camera: cam, daypart: daypart)
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            frozenCamera = cam
                            dragHit = model.beginDrag(at: cam.world(value.startLocation))
                        }
                        if dragHit { model.drag(to: cam.world(value.location)) }
                    }
                    .onEnded { value in
                        if dragHit {
                            model.endDrag()
                        } else if hypot(value.translation.width, value.translation.height) < 8 {
                            model.select(nil)
                        }
                        dragging = false
                        dragHit = false
                        frozenCamera = nil
                    }
            )
    }

    // MARK: 上と下の操作

    private var topBar: some View {
        HStack(spacing: 10) {
            Button("完了") {
                model.commit()
                dismiss()
            }
            .font(.system(.body, design: .rounded, weight: .bold))
            TextField("作品の名前", text: $model.artwork.name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { model.commit() }
            Button {
                model.commit()
                shareImage = renderShareImage()
                showShare = shareImage != nil
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(model.artwork.placements.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    @MainActor
    private func renderShareImage() -> UIImage? {
        let size = CGSize(width: 360, height: 450)
        let view = ArtworkStageView(placements: model.artwork.placements,
                                    camera: ArtworkCamera.fitting(model.artwork.placements, size: size),
                                    daypart: daypart)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if let p = model.selected {
                selectedPanel(p)
            } else {
                Text(model.artwork.placements.isEmpty
                     ? "「ゆきだまを置く」で、作ったゆきだまを並べましょう。"
                     : "ゆきだまをドラッグして、好きな所に置けます。地面や下のゆきだまの近くで離すと、ぴたっと乗ります。")
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
        VStack(spacing: 6) {
            Text("直径 \(formatLength(meters: p.piece.diameter))")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                actionButton("まわす", "arrow.clockwise") { model.rotateSelected(by: -.pi / 4) }
                actionButton("おろす", "arrow.down.to.line") { model.settleSelected() }
                actionButton("整える", "scissors") {
                    sculpt = SculptTarget(id: p.id, shape: p.piece.shape, radius: p.piece.radius)
                }
                actionButton("もどす", "tray.and.arrow.down") {
                    if let piece = model.removeSelected() { store.returnToStock(piece) }
                }
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
                                model.add(taken)
                            }
                            showStock = false
                        } label: {
                            HStack(spacing: 14) {
                                PieceThumbnail(piece: piece)
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
