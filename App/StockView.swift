import SwiftUI

/// 手元のゆきだまの一覧。タップすると削ったり色を塗ったりできる。
struct StockView: View {
    @Environment(GameStore.self) private var store

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if store.state.stock.isEmpty {
                    ContentUnavailableView {
                        Label("ゆきだまがありません", systemImage: "circle.dotted")
                    } description: {
                        Text("ホームで雪玉を転がして形を整え、「作品に使う」を押すと、ここに増えます。")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(store.state.stock) { piece in
                                Button {
                                    store.sculptingPieceID = piece.id
                                } label: {
                                    card(piece)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        Text("タップして形を整え直せます（取り出したあとは、大きくはなりません）。「さくひん」で組み合わせて飾れます。")
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("ゆきだま")
        }
    }

    private func card(_ piece: SnowPiece) -> some View {
        VStack(spacing: 8) {
            PieceThumbnail(piece: piece)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(spacing: 2) {
                Text("\(formatSteps(piece.steps))歩ぶん")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("直径 \(formatLength(meters: piece.diameter))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
