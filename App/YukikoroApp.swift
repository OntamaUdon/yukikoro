import SwiftUI

@main
struct YukikoroApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let page = DemoMode.galleryPage {
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
