#if DEBUG
import SwiftUI

/// 起動引数で画面の見た目を確認するためのデバッグ専用機能（Release には含まれない）。
/// 例: -yukikoro-demo -yukikoro-tab 1 -yukikoro-hour 22
enum DemoMode {
    static var args: [String] { CommandLine.arguments }
    static var isOn: Bool { args.contains("-yukikoro-demo") }
    static var showsCompletion: Bool { args.contains("-yukikoro-complete") }
    static var gallery3DPage: Int? { value("-yukikoro-gallery3d").flatMap(Int.init) }
    static var ballSteps: Int? { value("-yukikoro-ball").flatMap(Int.init) }
    static var snapPage: Int? { value("-yukikoro-snap").flatMap(Int.init) }

    static func value(_ key: String) -> String? {
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var hour: Int? { value("-yukikoro-hour").flatMap(Int.init) }
    static var yaw: Float? { value("-yukikoro-yaw").flatMap(Float.init) }
    static var tab: Int { value("-yukikoro-tab").flatMap(Int.init) ?? 0 }
    static var steps: Int { value("-yukikoro-steps").flatMap(Int.init) ?? 4_200 }

    /// 図鑑が全部埋まった状態
    static func state() -> GameState {
        var s = GameState()
        s.onboarded = true
        s.initialized = true
        var rng = SplitMix64(seed: 20_261_114)
        var index = 0
        for species in Species.allCases {
            for tier in SizeTier.allCases where tier >= species.rarity.minTier {
                let steps = tier.minSteps + 300
                let decorations = SnowmanFactory.pickDecorations(species: species, tier: tier, using: &rng)
                s.snowmen.append(Snowman(
                    id: UUID(), species: species, tier: tier, steps: steps,
                    madeAt: Date().addingTimeInterval(-Double(index) * 86_400),
                    decorations: decorations
                ))
                s.totalSteps += steps
                index += 1
            }
        }
        s.rollingSteps = steps
        s.totalSteps += steps
        s.credited[DayKey.key(for: Date())] = 5_200
        return s
    }
}

/// 3D の雪だるまを大きく並べて確認する画面
struct Gallery3DView: View {
    let page: Int
    var useSnapshots = false

    private struct Item: Identifiable {
        let species: Species
        let decorations: [Decoration]
        var id: String { species.rawValue }
    }

    private var items: [Item] {
        var rng = SplitMix64(seed: 77)
        let slice = Array(Species.allCases.dropFirst(page * 6).prefix(6))
        var result: [Item] = []
        for species in slice {
            let decorations = SnowmanFactory.pickDecorations(species: species, tier: .xl, using: &rng)
            result.append(Item(species: species, decorations: decorations))
        }
        return result
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.84, green: 0.92, blue: 1.0), Color(red: 0.96, green: 0.98, blue: 1.0)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(items) { item in
                    VStack(spacing: 2) {
                        if useSnapshots {
                            SnowmanThumbnail(Snowman(id: UUID(), species: item.species, tier: .xl, steps: 0, madeAt: Date(), decorations: item.decorations), size: CGSize(width: 190, height: 190))
                                .frame(width: 170, height: 170)
                        } else {
                            SnowmanSceneView(species: item.species, decorations: item.decorations, interactive: false)
                                .frame(width: 170, height: 170)
                        }
                        Text(item.species.displayName)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct BallDemoView: View {
    let steps: Int

    var body: some View {
        BallSceneView(steps: steps, daypart: Daypart.now(), yaw: DemoMode.yaw)
            .ignoresSafeArea()
    }
}
#endif
