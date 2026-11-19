import SwiftUI
import ARKit
import RealityKit

/// 塔を、カメラの景色の中に、実寸で立てる（AR）。
/// - 地面に向けると、自動で置く。画面をタップすると、その場所に置きなおす。
/// - LiDAR のある iPhone は、手前の物（壁・車・人など）のうしろに、雪玉がかくれる。
///   ただし、LiDAR が測れるのは、数 m まで。遠くのビルなどのうしろには、かくれない。
/// - 塔の位置は、いまいる場所の目の前（GPS の塔の位置には、合わせない）。
struct ARTowerScreen: View {
    let diameters: [Double]
    let height: Double
    @Environment(\.dismiss) private var dismiss
    @State private var placed = false
    @State private var resetToken = 0

    var body: some View {
        ZStack {
            if ARTowerView.isSupported {
                ARTowerView(diameters: diameters, resetToken: resetToken, onPlaced: { placed = $0 })
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
                Text("この端末では、ARが使えません")
                    .font(Soft.font(16, .medium))
                    .foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(SoftIconButtonStyle(size: 44))
                    .accessibilityLabel("閉じる")
                }
                Spacer()
                VStack(spacing: 8) {
                    Text(hint)
                        .font(Soft.font(14, .semibold))
                        .foregroundStyle(Soft.ink)
                        .multilineTextAlignment(.center)
                    Text(ARTowerView.supportsOcclusion
                         ? "手前の物のうしろには、かくれます（数mまで）"
                         : "この端末は、物のうしろにかくれる表示が、できません")
                        .font(Soft.font(11, .medium))
                        .foregroundStyle(Soft.subInk)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        SoftChip(symbol: "arrow.up.to.line", text: formatLength(meters: height))
                        Button {
                            placed = false
                            resetToken += 1
                        } label: {
                            Label("置きなおす", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(SoftButtonStyle(radius: 18))
                    }
                }
                .padding(16)
                .softCard(radius: 24)
            }
            .padding(16)
        }
        .softScreen()
        .statusBarHidden(false)
    }

    private var hint: String {
        placed ? "画面をタップすると、その場所に置きなおせます"
               : "地面にカメラを向けて、ゆっくり動かしてください"
    }
}

struct ARTowerView: UIViewRepresentable {
    let diameters: [Double]
    let resetToken: Int
    let onPlaced: (Bool) -> Void

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
    static var supportsOcclusion: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.diameters = diameters
        coordinator.onPlaced = onPlaced
        coordinator.lastResetToken = resetToken
        guard Self.isSupported else { return view }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        if Self.supportsOcclusion {
            // LiDAR: 手前の物のかたちを測って、そのうしろの雪玉を、隠す
            configuration.sceneReconstruction = .mesh
            view.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        view.session.delegate = coordinator
        view.session.run(configuration)
        coordinator.startedAt = Date()
        view.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPlaced = onPlaced
        if coordinator.lastResetToken != resetToken {
            coordinator.lastResetToken = resetToken
            coordinator.reset()
        }
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        weak var view: ARView?
        var diameters: [Double] = []
        var onPlaced: (Bool) -> Void = { _ in }
        var lastResetToken = 0
        var startedAt = Date()
        private var anchor: AnchorEntity?
        private var isPlaced = false

        // MARK: 置く

        func reset() {
            if let anchor { view?.scene.removeAnchor(anchor) }
            anchor = nil
            isPlaced = false
            startedAt = Date()
            notify(false)
        }

        private func notify(_ value: Bool) {
            let callback = onPlaced
            DispatchQueue.main.async { callback(value) }
        }

        private func place(at position: SIMD3<Float>) {
            guard let view else { return }
            if let anchor { view.scene.removeAnchor(anchor) }
            let newAnchor = AnchorEntity(world: position)
            newAnchor.addChild(Self.makeTower(diameters: diameters))
            view.scene.addAnchor(newAnchor)
            anchor = newAnchor
            isPlaced = true
            notify(true)
        }

        /// 画面の中心の先の地面を探して、見つかれば置く。4 秒たっても見つからなければ、目の前の、足もとの高さに置く
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard !isPlaced, let view else { return }
            if let hit = view.raycast(from: view.center, allowing: .estimatedPlane, alignment: .horizontal).first {
                place(at: hit.worldTransform.translation)
            } else if Date().timeIntervalSince(startedAt) > 4 {
                let camera = frame.camera.transform
                let origin = camera.translation
                let forward = SIMD3<Float>(-camera.columns.2.x, 0, -camera.columns.2.z)
                let length = simd_length(forward)
                guard length > 0.01 else { return }
                let base = Float(diameters.first ?? 3)
                let distance = max(8, base * 1.5 + 4)
                var position = origin + (forward / length) * distance
                position.y = origin.y - 1.4   // 目の高さから、足もとまで、約 1.4m
                place(at: position)
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            if let hit = view.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first {
                place(at: hit.worldTransform.translation)
            }
        }

        // MARK: 塔のかたち

        /// 雪玉を、下から積む（玉と玉は、下の玉の 6% ぶん重ねる。3D の塔と同じ）。直径は、メートルのまま。
        static func makeTower(diameters: [Double]) -> Entity {
            let root = Entity()
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1))
            material.roughness = .init(floatLiteral: 0.95)
            material.metallic = .init(floatLiteral: 0)
            var y: Float = 0
            for diameter in diameters {
                let d = Float(diameter)
                let ball = ModelEntity(mesh: .generateSphere(radius: d / 2), materials: [material])
                ball.position = [0, y + d / 2, 0]
                root.addChild(ball)
                y += d * 0.94
            }
            return root
        }
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
}
