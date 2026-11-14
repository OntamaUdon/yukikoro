import SwiftUI

struct SettingsView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var versionTaps = 0
    @State private var confirmReset = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("歩数について") {
                    Text("ヘルスケアに記録された歩数をもとに雪玉が育ちます。Apple Watch で数えた歩数も含まれます。歩いたのに増えないときは、ヘルスケアの「データアクセスとデバイス」でゆきころの歩数の読み取りが許可されているか確認してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("設定アプリを開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }

                Section("きろく") {
                    LabeledContent("これまでに転がした歩数", value: "\(formatSteps(store.state.totalSteps))歩")
                    LabeledContent("つくったゆきだま", value: "\(store.state.totalPieceCount)こ")
                    LabeledContent("つくった作品", value: "\(store.state.artworks.count)点")
                }

                Section("このアプリについて") {
                    Text("歩数のデータは端末の中だけで使い、外部には送信しません。広告も入っていません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        versionTaps += 1
                        if versionTaps >= 5 {
                            store.developerMode.toggle()
                            versionTaps = 0
                        }
                    } label: {
                        LabeledContent("バージョン", value: versionText)
                            .foregroundStyle(.primary)
                    }
                }

                if store.developerMode {
                    Section("テスト用（TestFlight での確認用）") {
                        Button("+500歩") { store.addDebugSteps(500) }
                        Button("+3,000歩") { store.addDebugSteps(3_000) }
                        Button("+10,000歩") { store.addDebugSteps(10_000) }
                        Button("+20,000歩") { store.addDebugSteps(20_000) }
                    }
                }

                Section {
                    Button("データをリセットする", role: .destructive) {
                        confirmReset = true
                    }
                }
            }
            .navigationTitle("せってい")
            .confirmationDialog("すべてのデータを消してはじめからにしますか？", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("リセットする", role: .destructive) { store.resetAll() }
                Button("やめる", role: .cancel) {}
            } message: {
                Text("つくったゆきだまと作品がすべて消えます。元に戻せません。")
            }
        }
    }
}
