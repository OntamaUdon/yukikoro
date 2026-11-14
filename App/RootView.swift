import SwiftUI

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "snowflake") }
            CollectionView()
                .tabItem { Label("ずかん", systemImage: "square.grid.2x2") }
            SettingsView()
                .tabItem { Label("せってい", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: .constant(!store.state.onboarded)) {
            OnboardingView()
        }
        .sheet(item: $store.pendingResult) { result in
            CompletionView(result: result)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}
