import SwiftUI
import Charts

/// きろくと設定（右上の歯車から開く）
struct MenuSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false

    private struct Day: Identifiable {
        let id: String
        let date: Date
        let steps: Int
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = DayKey.key(for: date)
            return Day(id: key, date: date, steps: store.state.walkedSteps(on: key))
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weekCard
                    totalsCard
                    stepsCard
                    dataCard
                    aboutCard
                }
                .padding(16)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.84, green: 0.92, blue: 1.0), Storybook.paper], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("メニュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(Storybook.rounded(16))
                }
            }
        }
        .presentationDetents([.large])
        .confirmationDialog("すべてのデータを消してはじめからにしますか？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("リセットする", role: .destructive) {
                store.resetAll()
                dismiss()
            }
            Button("やめる", role: .cancel) {}
        } message: {
            Text("雪玉も仲間も、はじめからやり直しになります。元に戻せません。")
        }
    }

    // MARK: カード

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(Storybook.rounded(17))
                .foregroundStyle(Storybook.ink)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storyCard(corner: 26)
    }

    private var weekCard: some View {
        let list = days
        let total = list.reduce(0) { $0 + $1.steps }
        return card("この7日間の歩数", icon: "figure.walk") {
            Chart(list) { day in
                BarMark(x: .value("日", day.date, unit: .day), y: .value("歩数", day.steps))
                    .foregroundStyle(Storybook.accent.gradient)
                    .cornerRadius(6)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 170)
            row("7日間の合計", "\(formatSteps(total))歩")
            row("1日の平均", "\(formatSteps(total / 7))歩")
        }
    }

    private var totalsCard: some View {
        let state = store.state
        return card("これまで", icon: "snowflake") {
            row("雪玉の直径", formatLength(meters: state.diameter))
            row("雪玉の重さ", formatMass(kg: state.mass))
            row("雪玉の密度", String(format: "%.0f kg/m³", state.density))
            row("歩いた歩数の合計", "\(formatSteps(state.totalSteps))歩")
            row("買い物に使った歩数", "\(formatSteps(state.spent))歩")
        }
    }

    private var stepsCard: some View {
        card("歩数について", icon: "heart.text.square") {
            Text("ヘルスケアに記録された歩数をもとに雪玉が育ちます。Apple Watch で数えた歩数も含まれます。歩いたのに増えないときは、ヘルスケアの「データアクセスとデバイス」で、歩数の読み取りが許可されているか確認してください。")
                .font(Storybook.rounded(14, .medium))
                .foregroundStyle(Storybook.ink.opacity(0.8))
            Button("設定アプリを開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(StoryButtonStyle(kind: .soft, compact: true))
        }
    }

    private var dataCard: some View {
        card("データ", icon: "tray.full") {
            Button("データをリセットする") { confirmReset = true }
                .buttonStyle(StoryButtonStyle(kind: .soft, compact: true))
        }
    }

    private var aboutCard: some View {
        card("このアプリについて", icon: "info.circle") {
            Text("歩数のデータは端末の中だけで使い、外部には送信しません。広告も入っていません。")
                .font(Storybook.rounded(14, .medium))
                .foregroundStyle(Storybook.ink.opacity(0.8))
            row("バージョン", versionText)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Storybook.rounded(15, .medium))
                .foregroundStyle(Storybook.ink.opacity(0.75))
            Spacer()
            Text(value)
                .font(Storybook.rounded(15))
                .foregroundStyle(Storybook.ink)
                .monospacedDigit()
        }
    }
}
