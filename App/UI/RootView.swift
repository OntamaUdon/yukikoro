import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Int = {
        #if DEBUG
        return DemoMode.isOn ? DemoMode.tab : 0
        #else
        return 0
        #endif
    }()

    var body: some View {
        TabView(selection: $selection) {
            MapScreen()
                .tabItem { Label("ちず", systemImage: "map.fill") }
                .tag(0)
            RankingScreen()
                .tabItem { Label("ランキング", systemImage: "trophy.fill") }
                .tag(1)
            RecordScreen()
                .tabItem { Label("きろく", systemImage: "book.closed.fill") }
                .tag(2)
            SettingsScreen()
                .tabItem { Label("せってい", systemImage: "gearshape.fill") }
                .tag(3)
        }
        .tint(Soft.accent)
        .overlay(alignment: .top) { bannerView }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.banner)
        .fullScreenCover(isPresented: .constant(!model.player.onboarded)) {
            OnboardingView()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if model.player.onboarded && !model.isDemo { model.location.start() }
            await model.bootstrap()
            while !Task.isCancelled {
                await model.refreshSteps()
                await model.refreshTowers()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    @ViewBuilder
    private var bannerView: some View {
        if let banner = model.banner {
            HStack(spacing: 10) {
                Image(systemName: banner.isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(banner.isGood ? Soft.good : Soft.warn)
                Text(banner.text)
                    .font(Soft.font(14, .semibold))
                    .foregroundStyle(Soft.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .softCard(radius: 22, depth: 0.8)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var starting = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            SnowBallDisc(size: 150)
            Text("ゆきころ")
                .font(Soft.font(34))
                .foregroundStyle(Soft.ink)
            VStack(alignment: .leading, spacing: 14) {
                point("figure.walk", "歩くと、雪玉が育ちます")
                point("map.fill", "近くの雪だるまの上に、雪玉をのせます")
                point("person.2.fill", "ほかの人の雪玉の上に、のせ合って、高く積みます")
                point("trophy.fill", "1週間で、いちばん高い雪だるまを競います")
            }
            .padding(22)
            .softCard(radius: 26)
            .padding(.horizontal, 24)
            Text("歩数（ヘルスケア）と、いまの場所を使います。あなたの場所は、サーバーに送りません。")
                .font(Soft.font(12, .medium))
                .foregroundStyle(Soft.subInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                starting = true
                Task { await model.completeOnboarding() }
            } label: {
                Text("はじめる")
            }
            .buttonStyle(SoftButtonStyle(prominent: true))
            .disabled(starting)
            .padding(.horizontal, 32)
            .padding(.bottom, 30)
        }
        .softScreen()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Soft.accent)
                .frame(width: 32)
            Text(text)
                .font(Soft.font(15, .semibold))
                .foregroundStyle(Soft.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
