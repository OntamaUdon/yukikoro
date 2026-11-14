import SwiftUI

struct RootView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainView()
            .id(store.resetCount)
            .fullScreenCover(isPresented: .constant(!store.state.onboarded)) {
                OnboardingView()
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
