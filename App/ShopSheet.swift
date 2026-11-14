import SwiftUI

/// おみせ。歩数で、雪玉を転がす仲間や機械を買う。
struct ShopSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private func formatForce(_ newtons: Double) -> String {
        if newtons < 1_000 { return String(format: "%.0fN", newtons) }
        if newtons < 1e6 { return String(format: "%.1fkN", newtons / 1_000) }
        return String(format: "%.1fMN", newtons / 1e6)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summaryCard
                    ForEach(Shop.items) { item in
                        row(item)
                    }
                }
                .padding(16)
            }
            .background(
                LinearGradient(colors: [Color(red: 0.84, green: 0.92, blue: 1.0), Storybook.paper], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle("おみせ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .font(Storybook.rounded(16))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var summaryCard: some View {
        let state = store.state
        let team = state.team
        let resistance = SnowPhysics.rollingResistance * SnowPhysics.gravity * state.mass
        let easiness = SnowPhysics.easiness(mass: state.mass, team: team)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("つかえる歩数")
                    .font(Storybook.rounded(14, .semibold))
                Spacer()
                Text("\(formatSteps(state.points))歩")
                    .font(Storybook.rounded(24))
                    .monospacedDigit()
            }
            Divider()
            line("みんなの力", formatForce(team.force + team.lift * state.mass * SnowPhysics.gravity))
            line("雪玉をころがす抵抗", formatForce(resistance))
            line("1歩で転がる距離", formatLength(meters: SnowPhysics.pushDistance(mass: state.mass, team: team)))
            line("いきおい", easiness >= 0.995 ? "すいすい" : String(format: "%.2f%%", easiness * 100))
            Text("雪玉が重くなるほど、押すのに力がいります。力が足りなくなると、どんどん進まなくなります。")
                .font(Storybook.rounded(12, .medium))
                .foregroundStyle(Storybook.ink.opacity(0.7))
        }
        .foregroundStyle(Storybook.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storyCard(corner: 26)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Storybook.rounded(14, .medium))
                .foregroundStyle(Storybook.ink.opacity(0.75))
            Spacer()
            Text(value)
                .font(Storybook.rounded(14))
                .monospacedDigit()
        }
    }

    private func row(_ item: ShopItem) -> some View {
        let state = store.state
        let unlocked = state.isUnlocked(item)
        let price = state.price(item)
        let owned = state.ownedCount(item.id)
        let affordable = state.canBuy(item)
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(Storybook.accent.opacity(unlocked ? 0.18 : 0.08))
                Image(systemName: unlocked ? item.symbol : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(unlocked ? Storybook.accent : Storybook.ink.opacity(0.35))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(unlocked ? item.name : "？？？")
                        .font(Storybook.rounded(16))
                    if owned > 0 {
                        Text("×\(owned)")
                            .font(Storybook.rounded(14))
                            .foregroundStyle(Storybook.accent)
                    }
                }
                if unlocked {
                    Text(item.detail)
                        .font(Storybook.rounded(11, .medium))
                        .foregroundStyle(Storybook.ink.opacity(0.7))
                    Text(effectText(item))
                        .font(Storybook.rounded(11, .semibold))
                        .foregroundStyle(Storybook.ink.opacity(0.85))
                } else {
                    Text("雪玉が\(formatLength(meters: item.unlockDiameter).replacingOccurrences(of: "約", with: ""))になると、買えるようになります")
                        .font(Storybook.rounded(11, .medium))
                        .foregroundStyle(Storybook.ink.opacity(0.6))
                }
            }
            Spacer(minLength: 4)

            if unlocked {
                Button {
                    store.buy(item)
                } label: {
                    VStack(spacing: 0) {
                        Text("買う")
                            .font(Storybook.rounded(14))
                        Text("\(formatSteps(price))歩")
                            .font(Storybook.rounded(11, .semibold))
                            .monospacedDigit()
                    }
                    .frame(minWidth: 62)
                }
                .buttonStyle(StoryButtonStyle(kind: affordable ? .primary : .soft, compact: true))
                .disabled(!affordable)
            }
        }
        .foregroundStyle(Storybook.ink)
        .padding(14)
        .storyCard(corner: 24)
        .opacity(unlocked ? 1 : 0.8)
    }

    private func effectText(_ item: ShopItem) -> String {
        switch item.kind {
        case .pusher:
            return "力 +\(formatForce(item.force))　1歩で \(formatLength(meters: item.reach).replacingOccurrences(of: "約", with: ""))"
        case .gravity:
            return "雪玉の重さの +\(Int(Shop.liftPerGravity * 100))% の力・転がる距離が \(Shop.gravityReachGrowth) 倍"
        }
    }
}
