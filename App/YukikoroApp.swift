import SwiftUI

@main
struct YukikoroApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = DemoMode.gallery3DPage {
                Gallery3DView(page: page)
            } else if let page = DemoMode.snapPage {
                Gallery3DView(page: page, useSnapshots: true)
            } else if let steps = DemoMode.ballSteps {
                BallDemoView(steps: steps)
            } else if let page = DemoMode.galleryPage {
                GalleryView(page: page)
            } else {
                RootView()
                    .environment(store)
                    .tint(Palette.tint)
            }
            #else
            RootView()
                .environment(store)
                .tint(Palette.tint)
            #endif
        }
    }
}
