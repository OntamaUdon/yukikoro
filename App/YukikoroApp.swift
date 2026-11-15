import SwiftUI

@main
struct YukikoroApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // 画面確認用: -yukikoro-style pastel|mint|frost|snowDusk、-yukikoro-flatmap（ビルを平らに）
        if let style = DemoMode.value("-yukikoro-style") { UserDefaults.standard.set(style, forKey: SoftStyle.storageKey) }
        if DemoMode.args.contains("-yukikoro-flatmap") { UserDefaults.standard.set(false, forKey: "mapBuildings") }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Soft.accent)
        }
    }
}
