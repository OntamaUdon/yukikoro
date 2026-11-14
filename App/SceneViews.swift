import SwiftUI
import SceneKit

/// ホームの「転がる雪玉」
struct BallSceneView: UIViewRepresentable {
    let steps: Int

    func makeCoordinator() -> BallScene {
        BallScene(hourProvider: { SkyClock.hour() })
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

/// ゆきだまの小さな絵（3D を一度だけ描画して使い回す）
struct PieceThumbnail: View {
    let piece: SnowPiece
    var size = CGSize(width: 160, height: 160)
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: piece.shape) {
            image = SceneSnapshot.piece(piece, size: size)
        }
    }
}

/// 作品の小さな絵
struct ArtworkThumbnail: View {
    let artwork: Artwork
    var size = CGSize(width: 200, height: 200)
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: artwork.updatedAt) {
            image = SceneSnapshot.artwork(artwork, hour: SkyClock.hour(), size: size)
        }
    }
}
