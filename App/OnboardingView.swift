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
                    Text("歩くと、ゆきんこたちが雪玉をころころ転がします。")
                    Text("雪玉をタップすると、ぎゅっと固まります。")
                    Text("歩いた歩数で、仲間や機械を買って、\nどこまでも大きく育てよう。")
                }
                .font(Storybook.rounded(16, .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Storybook.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .storyCard(corner: 26)
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
