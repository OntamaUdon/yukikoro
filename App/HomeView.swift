import SwiftUI

struct HomeView: View {
    @Environment(GameStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let theme = SkyTheme.current()
        let state = store.state
        ZStack(alignment: .bottom) {
            BallSceneView(
                steps: state.rollingSteps,
                isDark: theme.isDark,
                skyTop: UIColor(theme.top),
                skyBottom: UIColor(theme.bottom)
            )
            .id(theme.isDark)
            .ignoresSafeArea()

            VStack {
                header(state: state)
                Spacer()
            }

            panel(state: state)
        }
    }

    // MARK: 上部: 今日の歩数など

    private func header(state: GameState) -> some View {
        HStack(spacing: 10) {
            chip(icon: "figure.walk", text: "今日 \(formatSteps(store.todaySteps))歩")
            chip(icon: "snowflake", text: "雪だるま \(state.snowmen.count)体")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
    }

    // MARK: 下部: 雪玉の情報とボタン

    private func panel(state: GameState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("いま転がしている雪玉")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.currentTier.map { "\($0.adjective)サイズ" } ?? "ころがし中")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Palette.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(Palette.tint)
            }

            Text("\(formatSteps(state.rollingSteps)) 歩")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.6), value: state.rollingSteps)

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress(for: state))
                    .tint(Palette.tint)
                Text(hint(for: state))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Button {
                confirming = true
            } label: {
                Text("雪だるまにする")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!state.canComplete)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.12), radius: 14, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .confirmationDialog("この大きさで雪だるまにする？", isPresented: $confirming, titleVisibility: .visible) {
            Button("雪だるまにする") { store.completeSnowman() }
            Button("もう少し転がす", role: .cancel) {}
        } message: {
            if let tier = state.currentTier {
                Text("\(tier.adjective)サイズ（\(formatSteps(state.rollingSteps))歩）の雪だるまができます。")
            }
        }
    }

    /// 次のサイズまでの進み具合（0〜1）
    private func progress(for state: GameState) -> Double {
        guard let next = state.nextTier else { return 1 }
        let lower = state.currentTier?.minSteps ?? 0
        let span = Double(next.minSteps - lower)
        return min(1, max(0, Double(state.rollingSteps - lower) / max(span, 1)))
    }

    private func hint(for state: GameState) -> String {
        guard let tier = state.currentTier else {
            return "\(SizeTier.minimumSteps)歩から雪だるまにできます。"
        }
        if let next = state.nextTier {
            return "いまは「\(tier.adjective)」サイズ。\(formatSteps(next.minSteps))歩で「\(next.adjective)」サイズになります。"
        }
        return "いちばん大きな「\(tier.adjective)」サイズです。いつでも雪だるまにできます。"
    }
}
