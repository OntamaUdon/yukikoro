import SwiftUI

struct HomeView: View {
    @Environment(GameStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let state = store.state
        let daypart = Daypart.current(hour: Int(SkyClock.hour()))
        ZStack(alignment: .bottom) {
            BallSceneView(steps: state.rollingSteps, shape: state.rollingShape, daypart: daypart, yaw: nil)
                .id(daypart)
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
            chip(icon: "circle.dotted", text: "ゆきだま \(state.stock.count)こ")
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
                Text(state.isAtCap ? "最大の大きさ" : "ころがし中")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Palette.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(Palette.tint)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(formatSteps(state.rollingSteps)) 歩")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.6), value: state.rollingSteps)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("直径")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(formatLength(meters: state.rollingDiameter))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress(for: state))
                    .tint(Palette.tint)
                Text(hint(for: state))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    store.sculptingRolling = true
                } label: {
                    Label("整える", systemImage: "scissors")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    confirming = true
                } label: {
                    Label("作品に使う", systemImage: "tray.and.arrow.down")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!state.canComplete)
            }
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
        .confirmationDialog("この雪玉を作品に使う？", isPresented: $confirming, titleVisibility: .visible) {
            Button("作品に使う") { store.makePiece() }
            Button("もう少し転がす", role: .cancel) {}
        } message: {
            Text("\(formatSteps(state.rollingSteps))歩ぶん・直径\(formatLength(meters: state.rollingDiameter))のゆきだまとして取り出します。取り出すと、もう大きくはなりません。次の雪玉を転がし始めます。")
        }
    }

    /// 最大の大きさまでの進み具合（0〜1）
    private func progress(for state: GameState) -> Double {
        min(1, max(0, Double(state.rollingSteps) / Double(Snow.maxSteps)))
    }

    private func hint(for state: GameState) -> String {
        if state.rollingSteps < Snow.minimumSteps {
            return "\(Snow.minimumSteps)歩から、ゆきだまにできます。"
        }
        if state.isAtCap {
            let carry = state.reserveSteps > 0 ? "（持ち越し \(formatSteps(state.reserveSteps))歩）" : ""
            return "最大の大きさに達しました。作品に使うと、次の雪玉へ歩数を持ち越せます。\(carry)"
        }
        return "削って形を整えながら転がせます。大きくなっても、今の形のまま一回り大きくなります。"
    }
}
