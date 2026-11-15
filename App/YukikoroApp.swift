import SwiftUI

@main
struct YukikoroApp: App {
    @State private var model = AppModel()

    init() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = Soft.uiBackground
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: Soft.uiInk]
        nav.largeTitleTextAttributes = [.foregroundColor: Soft.uiInk]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Soft.accent)
        }
    }
}
