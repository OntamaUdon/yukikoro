import Foundation

/// 買えるもの（雪玉を転がす仲間・機械・重力）
struct ShopItem: Identifiable, Equatable {
    enum Kind { case pusher, gravity }

    let id: String
    let name: String
    let detail: String
    /// SF Symbols
    let symbol: String
    let kind: Kind
    /// 押す力（ニュートン）
    let force: Double
    /// 1歩で転がる距離（メートル）。重力そうちは、買った数で決まる。
    let reach: Double
    let basePrice: Double
    /// 必要な資材（1つ目）。値段と同じ倍率で上がる。
    let baseMaterials: Double
    /// 1つ買うごとに値段が何倍になるか
    let priceGrowth: Double
    /// 雪玉の直径（メートル）がここまで大きくなると買えるようになる
    let unlockDiameter: Double
}

enum Shop {
    static let items: [ShopItem] = [
        ShopItem(id: "kid", name: "ゆきんこ", detail: "雪玉を押してくれる、小さな仲間", symbol: "figure.walk",
                 kind: .pusher, force: 120, reach: 0.7, basePrice: 100, baseMaterials: 0, priceGrowth: 1.12, unlockDiameter: 0),
        ShopItem(id: "big", name: "でかゆきんこ", detail: "力もちの大きな仲間", symbol: "figure.strengthtraining.traditional",
                 kind: .pusher, force: 900, reach: 0.7, basePrice: 1_500, baseMaterials: 0, priceGrowth: 1.12, unlockDiameter: 0.3),
        ShopItem(id: "plank", name: "そりいた", detail: "板で雪玉を押す。大きな雪玉も動かせる", symbol: "rectangle.fill",
                 kind: .pusher, force: 12_000, reach: 1.5, basePrice: 8_000, baseMaterials: 5, priceGrowth: 1.12, unlockDiameter: 1.5),
        ShopItem(id: "crawler", name: "でんどうクローラー", detail: "電気で動くクローラーが転がす", symbol: "bolt.fill",
                 kind: .pusher, force: 300_000, reach: 6, basePrice: 50_000, baseMaterials: 40, priceGrowth: 1.12, unlockDiameter: 2.8),
        ShopItem(id: "heavy", name: "おおがたクローラー", detail: "山も動かす大きなクローラー", symbol: "gearshape.2.fill",
                 kind: .pusher, force: 6_000_000, reach: 20, basePrice: 120_000, baseMaterials: 250, priceGrowth: 1.12, unlockDiameter: 8),
        ShopItem(id: "gravity", name: "じゅうりょくそうち", detail: "重力で雪玉を転がし、雪を引き寄せる", symbol: "atom",
                 kind: .gravity, force: 0, reach: 100, basePrice: 12_000, baseMaterials: 250, priceGrowth: 1.10, unlockDiameter: 14),
    ]

    static func item(_ id: String) -> ShopItem? { items.first { $0.id == id } }

    /// 次の 1 つの値段（歩数）
    static func price(_ item: ShopItem, owned: Int) -> Int {
        Int((item.basePrice * pow(item.priceGrowth, Double(owned))).rounded())
    }

    /// 次の 1 つに必要な資材
    static func materials(_ item: ShopItem, owned: Int) -> Int {
        Int((item.baseMaterials * pow(item.priceGrowth, Double(owned))).rounded())
    }

    /// 重力そうち 1 つごとの、重さに比例する力の割合
    static let liftPerGravity = 0.04
    static let maxLift = 0.6
    /// 重力そうち 1 つごとに、1歩で転がる距離が何倍になるか
    static let gravityReachGrowth = 1.8

    /// 持っているものから、チームの力を決める
    static func team(owned: [String: Int]) -> PushTeam {
        var force = SnowPhysics.bareHandForce
        var reach = 0.7
        for item in items where item.kind == .pusher {
            let n = owned[item.id] ?? 0
            guard n > 0 else { continue }
            force += Double(n) * item.force
            reach = max(reach, item.reach)
        }
        let gravityCount = owned["gravity"] ?? 0
        var lift = 0.0
        if gravityCount > 0 {
            lift = min(maxLift, liftPerGravity * Double(gravityCount))
            reach = max(reach, 100 * pow(gravityReachGrowth, Double(gravityCount)))
        }
        return PushTeam(force: force, reach: reach, lift: lift)
    }
}
