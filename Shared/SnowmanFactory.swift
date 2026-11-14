import Foundation

/// テストで結果を固定できるシード付き乱数
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum SnowmanFactory {
    /// サイズごとの出現重み（common, uncommon, rare, special）
    static func weights(for tier: SizeTier) -> [Int] {
        switch tier {
        case .s: return [100, 0, 0, 0]
        case .m: return [70, 30, 0, 0]
        case .l: return [45, 30, 25, 0]
        case .xl: return [25, 30, 25, 20]
        }
    }

    static func decorationCountRange(for tier: SizeTier) -> ClosedRange<Int> {
        switch tier {
        case .s: return 1...2
        case .m: return 1...3
        case .l: return 2...3
        case .xl: return 2...4
        }
    }

    static func pickSpecies<G: RandomNumberGenerator>(tier: SizeTier, using g: inout G) -> Species {
        let w = weights(for: tier)
        let total = w.reduce(0, +)
        var roll = Int.random(in: 0..<total, using: &g)
        var chosen = Rarity.common
        for rarity in Rarity.allCases {
            let weight = w[rarity.rawValue]
            if roll < weight {
                chosen = rarity
                break
            }
            roll -= weight
        }
        let pool = Species.allCases.filter { $0.rarity == chosen }
        return pool.randomElement(using: &g) ?? .plain
    }

    static func pickDecorations<G: RandomNumberGenerator>(species: Species, tier: SizeTier, using g: inout G) -> [Decoration] {
        let slots = DecorationSlot.allCases.filter { slot in
            DecorationKind.allCases.contains { $0.slot == slot && species.allows($0) }
        }
        let wanted = Int.random(in: decorationCountRange(for: tier), using: &g)
        let chosen = Array(slots.shuffled(using: &g).prefix(wanted))
        var result: [Decoration] = []
        for slot in DecorationSlot.allCases where chosen.contains(slot) {
            let kinds = DecorationKind.allCases.filter { $0.slot == slot && species.allows($0) }
            guard let kind = kinds.randomElement(using: &g) else { continue }
            let hue = Int.random(in: 0..<Decoration.hueCount, using: &g)
            result.append(Decoration(kind: kind, hue: hue))
        }
        return result
    }

    static func make<G: RandomNumberGenerator>(tier: SizeTier, steps: Int, date: Date, using g: inout G) -> Snowman {
        let species = pickSpecies(tier: tier, using: &g)
        let decorations = pickDecorations(species: species, tier: tier, using: &g)
        return Snowman(
            id: UUID(),
            species: species,
            tier: tier,
            steps: steps,
            madeAt: date,
            decorations: decorations
        )
    }
}
