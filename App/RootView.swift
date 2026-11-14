import SwiftUI

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.tab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "snowflake") }
                .tag(0)
            StockView()
                .tabItem { Label("ゆきだま", systemImage: "circle.dotted") }
                .tag(1)
            ArtworksView()
                .tabItem { Label("さくひん", systemImage: "sparkles") }
                .tag(2)
            RecordsView()
                .tabItem { Label("きろく", systemImage: "chart.bar.fill") }
                .tag(3)
            SettingsView()
                .tabItem { Label("せってい", systemImage: "gearshape") }
                .tag(4)
        }
        .fullScreenCover(isPresented: .constant(!store.state.onboarded)) {
            OnboardingView()
        }
        .fullScreenCover(isPresented: $store.sculptingRolling) {
            SculptView(shape: store.state.rollingShape, title: "雪玉を整える",
                       radius: Float(BallScale.radius(steps: store.state.rollingSteps)),
                       onDone: { shape in
                           store.updateRolling(shape: shape)
                           store.sculptingRolling = false
                       },
                       onCancel: { store.sculptingRolling = false })
        }
        .fullScreenCover(item: sculptingPiece) { piece in
            SculptView(shape: piece.shape, title: "ゆきだまを整える", radius: piece.radius,
                       onDone: { shape in
                           store.updateStock(id: piece.id, shape: shape)
                           store.sculptingPieceID = nil
                       },
                       onCancel: { store.sculptingPieceID = nil })
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// 整える画面に出すゆきだま
    private var sculptingPiece: Binding<SnowPiece?> {
        Binding(
            get: { store.state.stock.first { $0.id == store.sculptingPieceID } },
            set: { if $0 == nil { store.sculptingPieceID = nil } }
        )
    }
}
