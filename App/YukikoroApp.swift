import SwiftUI

@main
struct YukikoroApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Palette.tint)
        }
    }
}
