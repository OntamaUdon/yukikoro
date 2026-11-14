import SwiftUI

struct HomeView: View {
    @Environment(GameStore.self) private var store
    @State private var rollAngle: Double = 0
    @State private var confirming = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let theme = SkyTheme.current(timeline.date)
            ZStack {
                SkyBackground(theme: theme)
                SnowFall(isDark: theme.isDark)
                GeometryReader { geo in
                    content(theme: theme, size: geo.size)
                }
            }
        }
    }

    @ViewBuilder
    private func content(theme: SkyTheme, size: CGSize) -> some View {
        let steps = store.state.rollingSteps
        let groundTop = size.height * 0.46
        let maxDiameter = min(size.width * 0.74, 290)
        let diameter = BallScale.diameter(steps: steps, minimum: 56, maximum: maxDiameter)
        let frameSide = diameter / 0.92

        ZStack(alignment: .top) {
            SnowGround(isDark: theme.isDark)
                .frame(width: size.width, height: size.height - groundTop)
                .position(x: size.width / 2, y: groundTop + (size.height - groundTop) / 2)
                .ignoresSafeArea(edges: .bottom)

            RollingBall(rotation: rollAngle)
                .frame(width: frameSide, height: frameSide)
                .position(x: size.width / 2, y: groundTop + 34 - diameter / 2 + frameSide * 0.06)

            header(theme: theme)
                .frame(width: size.width)
                .position(x: size.width / 2, y: 70)

            panel(theme: theme)
                .padding(.horizontal, 20)
                .frame(width: size.width)
                .position(x: size.width / 2, y: size.height - 150)
        }
        .onChange(of: steps) { oldValue, newValue in
            guard newValue > oldValue else { return }
            withAnimation(.easeInOut(duration: 1.6)) {
                rollAngle += 0.5 + Double(newValue - oldValue) * 0.004
            }
        }
    }

    private func header(theme: SkyTheme) -> some View {
        VStack(spacing: 4) {
            Text("ゆきころ")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(theme.text)
            Text("今日は \(formatSteps(store.todaySteps)) 歩")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func panel(theme: SkyTheme) -> some View {
        let state = store.state
        return VStack(spacing: 10) {
            Text("いま転がしている雪玉")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(formatSteps(state.rollingSteps)) 歩")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.6), value: state.rollingSteps)
            Text(hint(for: state))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .confirmationDialog("この大きさで雪だるまにする？", isPresented: $confirming, titleVisibility: .visible) {
            Button("雪だるまにする") { store.completeSnowman() }
            Button("もう少し転がす", role: .cancel) {}
        } message: {
            if let tier = state.currentTier {
                Text("\(tier.adjective)大きさ（\(formatSteps(state.rollingSteps))歩）の雪だるまができます。")
            }
        }
    }

    private func hint(for state: GameState) -> String {
        guard let tier = state.currentTier else {
            return "\(SizeTier.minimumSteps)歩から雪だるまにできます。のんびり歩こう。"
        }
        if let next = state.nextTier {
            return "いまは「\(tier.adjective)」サイズ。\(formatSteps(next.minSteps))歩で「\(next.adjective)」サイズになるよ。"
        }
        return "ばかでかい雪玉になりました。いつでも雪だるまにできます。"
    }
}
