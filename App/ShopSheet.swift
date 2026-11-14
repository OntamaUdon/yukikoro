import SwiftUI

/// おみせ。歩数と、木を倒して手に入れた資材で、雪玉を転がす仲間や機械を買う。
struct ShopSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    walletRow
                    powerCard
                    ForEach(Shop.items) { item in
                        itemCard(item)
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
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

    // MARK: 持ち物

    private var walletRow: some View {
        let state = store.state
        return HStack(spacing: 12) {
            walletPill(symbol: "figure.walk", title: "つかえる歩数", value: "\(formatSteps(state.points))歩", tint: Storybook.accent)
            walletPill(symbol: "tree.fill", title: "資材", value: formatSteps(state.materials), tint: Color(red: 0.36, green: 0.62, blue: 0.40))
        }
    }

    private func walletPill(symbol: String, title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(Storybook.rounded(12, .semibold))
                    .foregroundStyle(Storybook.ink.opacity(0.65))
                Text(value)
                    .font(Storybook.rounded(20))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Storybook.ink)
        .padding(12)
        .frame(maxWidth: .infinity)
        .storyCard(corner: 22)
    }

    // MARK: いまの力

    private var powerCard: some View {
        let state = store.state
        let team = state.team
        let force = team.force + team.lift * state.mass * SnowPhysics.gravity
        let resistance = SnowPhysics.rollingResistance * SnowPhysics.gravity * state.mass
        let needed = state.toppleForceNeeded
        return VStack(alignment: .leading, spacing: 12) {
            bar("みんなの力", value: force, maximum: max(needed ?? force, force, resistance), tint: Storybook.accent)
            bar("雪玉の重さ", value: resistance, maximum: max(needed ?? force, force, resistance), tint: Color(red: 0.62, green: 0.62, blue: 0.74))
            if let needed {
                bar("木を倒す力", value: needed, maximum: max(needed, force, resistance), tint: Color(red: 0.36, green: 0.62, blue: 0.40))
            }
        }
        .foregroundStyle(Storybook.ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storyCard(corner: 26)
    }

    /// 力の大きさ比べの棒（桁が大きく違うので、対数で描く）
    private func bar(_ title: String, value: Double, maximum: Double, tint: Color) -> some View {
        let fraction = min(1, max(0.02, log10(max(value, 1) + 1) / max(log10(maximum + 1), 1)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(Storybook.rounded(13, .semibold))
                    .foregroundStyle(Storybook.ink.opacity(0.8))
                Spacer()
                Text(formatForce(value))
                    .font(Storybook.rounded(13))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Storybook.ink.opacity(0.08))
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
        }
    }

    // MARK: 商品

    private func itemCard(_ item: ShopItem) -> some View {
        let state = store.state
        let unlocked = state.isUnlocked(item)
        let owned = state.ownedCount(item.id)
        let price = state.price(item)
        let materials = state.materialPrice(item)
        let affordable = state.canBuy(item)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: unlocked ? item.symbol : "lock.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(unlocked ? Storybook.accent : Storybook.ink.opacity(0.35))
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Storybook.accent.opacity(unlocked ? 0.16 : 0.08)))
                    if owned > 0 {
                        Text("\(owned)")
                            .font(Storybook.rounded(13))
                            .foregroundStyle(.white)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Circle().fill(Storybook.accent))
                            .offset(x: 6, y: -6)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(unlocked ? item.name : "？？？")
                        .font(Storybook.rounded(18))
                    if unlocked {
                        effectChips(item)
                    } else {
                        Text("\(formatLength(meters: item.unlockDiameter).replacingOccurrences(of: "約", with: "")) で解放")
                            .font(Storybook.rounded(13, .medium))
                            .foregroundStyle(Storybook.ink.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
            }

            if unlocked {
                Button {
                    store.buy(item)
                } label: {
                    HStack(spacing: 8) {
                        Text("買う")
                        Spacer()
                        Text("\(formatSteps(price))歩")
                            .monospacedDigit()
                        if materials > 0 {
                            Text("＋ 資材 \(formatSteps(materials))")
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(StoryButtonStyle(kind: affordable ? .primary : .soft, compact: true))
                .disabled(!affordable)

            }
        }
        .foregroundStyle(Storybook.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .storyCard(corner: 26)
        .opacity(unlocked ? 1 : 0.75)
    }

    private func effectChips(_ item: ShopItem) -> some View {
        HStack(spacing: 8) {
            switch item.kind {
            case .pusher:
                chip("力 +\(formatForce(item.force))")
                chip("1歩 \(formatLength(meters: item.reach).replacingOccurrences(of: "約", with: ""))")
            case .gravity:
                chip("重さの +\(Int(Shop.liftPerGravity * 100))% の力")
                chip("1歩 ×\(String(format: "%.1f", Shop.gravityReachGrowth))")
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Storybook.rounded(12))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Storybook.accent.opacity(0.12)))
    }
}
