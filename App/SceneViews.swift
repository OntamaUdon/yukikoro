import SwiftUI
import SceneKit

/// 雪だるまを 3D で表示する。指でぐるっと回せる。
struct SnowmanSceneView: UIViewRepresentable {
    let species: Species
    let decorations: [Decoration]
    var interactive = true
    var popIn = false

    init(_ snowman: Snowman, interactive: Bool = true, popIn: Bool = false) {
        species = snowman.species
        decorations = snowman.decorations
        self.interactive = interactive
        self.popIn = popIn
    }

    init(species: Species, decorations: [Decoration] = [], interactive: Bool = true, popIn: Bool = false) {
        self.species = species
        self.decorations = decorations
        self.interactive = interactive
        self.popIn = popIn
    }

    func makeUIView(context: Context) -> SCNView {
        let built = SnowmanScene.make(species: species, decorations: decorations)
        let view = SCNView()
        view.scene = built.scene
        view.pointOfView = built.camera
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = interactive
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3(0, 0.95, 0)
        view.defaultCameraController.maximumVerticalAngle = 35
        view.defaultCameraController.minimumVerticalAngle = -5
        view.isPlaying = true
        if popIn {
            let node = built.snowman
            node.removeAllActions()
            node.scale = SCNVector3(0.01, 0.01, 0.01)
            let grow = SCNAction.scale(to: 1.0, duration: 0.7)
            grow.timingFunction = { t in
                // 少しだけ行き過ぎてから戻る
                let c1: Float = 1.70158
                let c3 = c1 + 1
                let x = t - 1
                return 1 + c3 * x * x * x + c1 * x * x
            }
            node.runAction(grow)
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

/// ホームの「転がる雪玉」
struct BallSceneView: UIViewRepresentable {
    let steps: Int
    let daypart: Daypart

    func makeCoordinator() -> BallScene {
        BallScene(daypart: daypart)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true
        view.allowsCameraControl = false
        context.coordinator.update(steps: steps)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(steps: steps)
    }
}

/// 図鑑などで使う静止画のサムネイル（3D を一度だけ描画して使い回す）
struct SnowmanThumbnail: View {
    let species: Species
    let decorations: [Decoration]
    var size: CGSize = CGSize(width: 160, height: 160)
    @State private var image: UIImage?

    init(_ snowman: Snowman, size: CGSize = CGSize(width: 160, height: 160)) {
        species = snowman.species
        decorations = snowman.decorations
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .task {
            image = await SnowmanSnapshot.image(species: species, decorations: decorations, size: size)
        }
    }
}
