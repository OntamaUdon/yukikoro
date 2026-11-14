import SwiftUI

struct CollectionView: View {
    @Environment(GameStore.self) private var store
    @State private var selected: Snowman?

    private let pageBackground = LinearGradient(
        colors: [Color(red: 0.93, green: 0.97, blue: 1.0), Color(red: 0.86, green: 0.92, blue: 0.99)],
        startPoint: .top, endPoint: .bottom
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    summary
                    ForEach(Species.allCases) { species in
                        SpeciesCard(species: species, state: store.state) { selected = $0 }
                    }
                    history
                }
                .padding()
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle("ずかん")
            .sheet(item: $selected) { snowman in
                SnowmanDetailView(snowman: snowman)
            }
        }
    }

    private var summary: some View {
        let found = store.state.discoveredKindCount
        let total = GameState.totalKindCount
        return VStack(spacing: 6) {
            Text("\(found) / \(total)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("みつけた雪だるま（種類 × 大きさ）")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(found), total: Double(max(total, 1)))
                .tint(Palette.tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var history: some View {
        let list = Array(store.state.snowmen.reversed().prefix(40))
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("つくった雪だるま")
                    .font(.system(.headline, design: .rounded))
                ForEach(list) { snowman in
                    Button { selected = snowman } label: {
                        HStack(spacing: 12) {
                            SnowmanView(snowman)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snowman.name)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                Text("\(formatSteps(snowman.steps))歩 ・ \(snowman.madeAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

private struct SpeciesCard: View {
    let species: Species
    let state: GameState
    let onSelect: (Snowman) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(species.displayName)
                    .font(.system(.headline, design: .rounded))
                Text(species.rarity.label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(rarityColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(rarityColor)
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(SizeTier.allCases) { tier in
                    cell(tier)
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func cell(_ tier: SizeTier) -> some View {
        let available = tier >= species.rarity.minTier
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(available ? Color(red: 0.90, green: 0.95, blue: 1.0) : Color.gray.opacity(0.10))
                if let found = state.latest(species: species, tier: tier) {
                    Button { onSelect(found) } label: {
                        SnowmanView(found, scale: 0.95)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                } else if available {
                    Image(systemName: "questionmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.outline.opacity(0.7))
                } else {
                    Image(systemName: "minus")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 74)
            Text(tier.label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var rarityColor: Color {
        switch species.rarity {
        case .common: return .gray
        case .uncommon: return Color(red: 0.25, green: 0.60, blue: 0.45)
        case .rare: return Color(red: 0.30, green: 0.45, blue: 0.85)
        case .special: return Color(red: 0.85, green: 0.55, blue: 0.10)
        }
    }
}
