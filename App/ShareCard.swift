import SwiftUI

/// SNS などで共有するための画像
struct ShareCardView: View {
    let snowman: Snowman

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.74, green: 0.88, blue: 0.98), Color(red: 0.93, green: 0.97, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 0) {
                Text("ゆきころ")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .padding(.top, 26)
                Spacer(minLength: 0)
                SnowmanView(snowman)
                    .frame(width: 260, height: 260)
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text(snowman.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text("\(formatSteps(snowman.steps))歩ぶん転がしたよ")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                }
                .padding(.bottom, 34)
            }
        }
        .frame(width: 360, height: 450)
    }
}

@MainActor
enum ShareImage {
    static func render(_ snowman: Snowman) -> Image? {
        let renderer = ImageRenderer(content: ShareCardView(snowman: snowman))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

/// 共有ボタン。画像を作ってから表示する。
struct ShareButton: View {
    let snowman: Snowman
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview(snowman.name, image: image)) {
                    Label("画像をシェアする", systemImage: "square.and.arrow.up")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task {
            image = ShareImage.render(snowman)
        }
    }
}
