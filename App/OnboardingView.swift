import SwiftUI

struct OnboardingView: View {
    @Environment(GameStore.self) private var store
    @State private var busy = false

    var body: some View {
        ZStack {
            StoryBackground(daypart: .day)
                .ignoresSafeArea()
            SnowFall()
            VStack(spacing: 22) {
                Spacer()
                SnowBallView(shape: .pristine(seed: 5), radius: 84, angle: 0)
                    .padding(.bottom, 4)
                Text("ゆきころさんぽ")
                    .font(Storybook.rounded(34))
                    .foregroundStyle(Storybook.ink)
                VStack(spacing: 10) {
                    Text("歩くと、足元の雪玉がころころ大きくなります。")
                    Text("指でなぞって切ったり、色をつけたりして、\n形を整えよう。")
                    Text("いくつも並べて、雪の彫刻をつくろう。")
                }
                .font(Storybook.rounded(16, .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Storybook.ink)
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(StoryButtonStyle(kind: .primary))
                    .disabled(busy)
                    Text("歩数を読み取るために、ヘルスケアへのアクセスをおたずねします。データは端末の外には送信されません。")
                        .font(Storybook.rounded(12, .medium))
                        .foregroundStyle(Storybook.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .storyCard(corner: 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
}
