import SwiftUI

struct OnboardingView: View {
    @Environment(GameStore.self) private var store
    @State private var busy = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.74, green: 0.88, blue: 0.98), Color(red: 0.96, green: 0.98, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            SnowFall()
            VStack(spacing: 22) {
                Spacer()
                SnowmanView(species: .plain, decorations: [
                    Decoration(kind: .knitCap, hue: 0),
                    Decoration(kind: .scarf, hue: 1),
                ])
                .frame(maxWidth: 240)
                Text("ゆきころ")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                VStack(spacing: 10) {
                    Text("歩くと、足元の雪玉がころころ大きくなります。")
                    Text("好きな大きさで雪だるまにして、\nいろんな子を集めよう。")
                    Text("ノルマも期限もありません。のんびりどうぞ。")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
                Spacer()
                VStack(spacing: 10) {
                    Button {
                        busy = true
                        Task {
                            await store.completeOnboarding()
                            busy = false
                        }
                    } label: {
                        Text("はじめる")
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
                    Text("歩数を読み取るために、ヘルスケアへのアクセスをおたずねします。データは端末の外には送信されません。")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }
}
