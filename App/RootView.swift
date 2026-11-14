import SwiftUI

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = RootView.initialTab

    private static var initialTab: Int {
        #if DEBUG
        return DemoMode.isOn ? DemoMode.tab : 0
        #else
        return 0
        #endif
    }

    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "snowflake") }
                .tag(0)
            CollectionView()
                .tabItem { Label("ずかん", systemImage: "square.grid.2x2") }
                .tag(1)
            RecordsView()
                .tabItem { Label("きろく", systemImage: "chart.bar.fill") }
                .tag(2)
            SettingsView()
                .tabItem { Label("せってい", systemImage: "gearshape") }
                .tag(3)
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
