import SwiftUI

/// 作品の一覧。ゆきだまを組み合わせた雪の彫刻を飾っておく場所。
struct ArtworksView: View {
    @Environment(GameStore.self) private var store
    @State private var composing: Artwork?
    @State private var deleting: Artwork?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if store.state.artworks.isEmpty {
                    ContentUnavailableView {
                        Label("まだ作品がありません", systemImage: "sparkles")
                    } description: {
                        Text("ゆきだまを積んだり並べたりして、雪の彫刻を作ってみましょう。")
                    } actions: {
                        Button("作品をつくる") { composing = store.newArtwork() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.state.artworks) { artwork in
                                Button {
                                    composing = artwork
                                } label: {
                                    card(artwork)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("削除する", systemImage: "trash", role: .destructive) { deleting = artwork }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("さくひん")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = store.newArtwork()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(item: $composing) { artwork in
                ComposeView(artwork: artwork)
            }
            .confirmationDialog("この作品を消しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("消す", role: .destructive) {
                    if let deleting { store.deleteArtwork(id: deleting.id) }
                    deleting = nil
                }
                Button("やめる", role: .cancel) { deleting = nil }
            } message: {
                Text("使っていたゆきだまは、「ゆきだま」に戻ります。")
            }
            .onAppear {
                #if DEBUG
                if DemoMode.isOn, DemoMode.composes, composing == nil {
                    composing = store.state.artworks.first
                }
                #endif
            }
        }
    }

    private func card(_ artwork: Artwork) -> some View {
        VStack(spacing: 8) {
            ArtworkThumbnail(artwork: artwork, size: CGSize(width: 300, height: 300))
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 2) {
                Text(artwork.name)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("ゆきだま \(artwork.placements.count)こ")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
