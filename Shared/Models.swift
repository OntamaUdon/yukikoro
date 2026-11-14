import Foundation
import SwiftUI

// MARK: - サイズ段階

enum SizeTier: Int, Codable, CaseIterable, Comparable, Identifiable {
    case s = 0, m, l, xl

    var id: Int { rawValue }

    static func < (lhs: SizeTier, rhs: SizeTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 雪だるまにできる最小の歩数
    static let minimumSteps = 500

    var minSteps: Int {
        switch self {
        case .s: return 500
        case .m: return 3_000
        case .l: return 8_000
        case .xl: return 15_000
        }
    }

    var label: String {
        switch self {
        case .s: return "S"
        case .m: return "M"
        case .l: return "L"
        case .xl: return "XL"
        }
    }

    var adjective: String {
        switch self {
        case .s: return "ちいさな"
        case .m: return "ふつうの"
        case .l: return "おおきな"
        case .xl: return "ばかでかい"
        }
    }

    /// 図鑑などで大きさを見比べるための描画倍率
    var drawScale: CGFloat {
        switch self {
        case .s: return 0.52
        case .m: return 0.68
        case .l: return 0.84
        case .xl: return 1.0
        }
    }

    static func tier(forSteps steps: Int) -> SizeTier? {
        if steps >= SizeTier.xl.minSteps { return .xl }
        if steps >= SizeTier.l.minSteps { return .l }
        if steps >= SizeTier.m.minSteps { return .m }
        if steps >= SizeTier.s.minSteps { return .s }
        return nil
    }
}

// MARK: - レア度

enum Rarity: Int, Codable, CaseIterable {
    case common = 0, uncommon, rare, special

    var label: String {
        switch self {
        case .common: return "ふつう"
        case .uncommon: return "めずらしい"
        case .rare: return "レア"
        case .special: return "とくべつ"
        }
    }

    /// この種類が出始めるサイズ
    var minTier: SizeTier {
        switch self {
        case .common: return .s
        case .uncommon: return .m
        case .rare: return .l
        case .special: return .xl
        }
    }
}

// MARK: - 種類

enum Species: String, Codable, CaseIterable, Identifiable {
    case plain, usagi, neko, kuma, inu, penguin, hiyoko, daruma, tenshi, ousama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plain: return "雪だるま"
        case .usagi: return "ゆきうさぎ"
        case .neko: return "ゆきねこ"
        case .kuma: return "ゆきぐま"
        case .inu: return "ゆきいぬ"
        case .penguin: return "ペンギン"
        case .hiyoko: return "ひよこ"
        case .daruma: return "だるま"
        case .tenshi: return "てんし"
        case .ousama: return "おうさま"
        }
    }

    var rarity: Rarity {
        switch self {
        case .plain, .usagi, .neko: return .common
        case .kuma, .inu, .penguin: return .uncommon
        case .hiyoko, .daruma: return .rare
        case .tenshi, .ousama: return .special
        }
    }

    var hasEars: Bool {
        switch self {
        case .usagi, .neko, .kuma, .inu: return true
        default: return false
        }
    }

    /// 頭に自前の飾り（輪っか・王冠）があるため帽子を付けない
    var blocksHeadwear: Bool {
        self == .tenshi || self == .ousama
    }

    /// 枝の腕を持つか（ペンギン・ひよこ・てんしは別の形）
    var hasTwigArms: Bool {
        switch self {
        case .penguin, .hiyoko, .tenshi: return false
        default: return true
        }
    }

    func allows(_ kind: DecorationKind) -> Bool {
        switch kind.slot {
        case .head:
            if blocksHeadwear { return false }
            if hasEars { return kind == .ribbon }
            return true
        case .face:
            return self != .daruma
        case .neck, .body:
            return true
        case .arms:
            return hasTwigArms
        }
    }
}

// MARK: - 飾り

enum DecorationSlot: String, Codable, CaseIterable {
    case head, face, neck, body, arms
}

enum DecorationKind: String, Codable, CaseIterable {
    case bucketHat, topHat, santaHat, knitCap, earmuffs, flowerCrown, ribbon
    case sunglasses, roundGlasses
    case scarf, bowtie
    case buttons, stripe
    case mittens

    var slot: DecorationSlot {
        switch self {
        case .bucketHat, .topHat, .santaHat, .knitCap, .earmuffs, .flowerCrown, .ribbon: return .head
        case .sunglasses, .roundGlasses: return .face
        case .scarf, .bowtie: return .neck
        case .buttons, .stripe: return .body
        case .mittens: return .arms
        }
    }

    var displayName: String {
        switch self {
        case .bucketHat: return "バケツぼうし"
        case .topHat: return "シルクハット"
        case .santaHat: return "サンタぼうし"
        case .knitCap: return "ニットぼう"
        case .earmuffs: return "みみあて"
        case .flowerCrown: return "はなかんむり"
        case .ribbon: return "リボン"
        case .sunglasses: return "サングラス"
        case .roundGlasses: return "まるめがね"
        case .scarf: return "マフラー"
        case .bowtie: return "ちょうネクタイ"
        case .buttons: return "ボタン"
        case .stripe: return "ボーダー"
        case .mittens: return "てぶくろ"
        }
    }
}

struct Decoration: Codable, Hashable {
    static let hueCount = 6

    var kind: DecorationKind
    var hue: Int
}

// MARK: - 雪だるま

struct Snowman: Codable, Identifiable, Hashable {
    var id: UUID
    var species: Species
    var tier: SizeTier
    var steps: Int
    var madeAt: Date
    var decorations: [Decoration]

    var name: String { tier.adjective + species.displayName }

    /// 図鑑の1マス（種類×サイズ）を表すキー
    var kindKey: String { Snowman.kindKey(species: species, tier: tier) }

    static func kindKey(species: Species, tier: SizeTier) -> String {
        "\(species.rawValue)-\(tier.rawValue)"
    }
}

struct CompletionResult: Identifiable {
    let snowman: Snowman
    let isNewKind: Bool
    var id: UUID { snowman.id }
}
