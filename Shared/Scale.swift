import Foundation

/// 大きさを比べるための目印（人・木・山など）
struct ScaleReference: Equatable {
    let name: String
    /// 高さ（メートル）
    let height: Double
    /// 絵（SF Symbols）
    let symbol: String

    static let all: [ScaleReference] = [
        ScaleReference(name: "はっぱ", height: 0.06, symbol: "leaf.fill"),
        ScaleReference(name: "ボール", height: 0.22, symbol: "soccerball"),
        ScaleReference(name: "ねこ", height: 0.30, symbol: "cat.fill"),
        ScaleReference(name: "ひと", height: 1.7, symbol: "figure.stand"),
        ScaleReference(name: "き", height: 8, symbol: "tree.fill"),
        ScaleReference(name: "ビル", height: 40, symbol: "building.2.fill"),
        ScaleReference(name: "たかいビル", height: 100, symbol: "building.fill"),
        ScaleReference(name: "タワー", height: 333, symbol: "antenna.radiowaves.left.and.right"),
        ScaleReference(name: "くも", height: 1_000, symbol: "cloud.fill"),
        ScaleReference(name: "やま", height: 3_776, symbol: "mountain.2.fill"),
        ScaleReference(name: "ひこうき", height: 10_000, symbol: "airplane"),
        ScaleReference(name: "つき", height: 3_474_000, symbol: "moon.fill"),
        ScaleReference(name: "ちきゅう", height: 12_742_000, symbol: "globe.asia.australia.fill"),
        ScaleReference(name: "もくせい", height: 139_820_000, symbol: "circle.hexagongrid.fill"),
        ScaleReference(name: "たいよう", height: 1_392_700_000, symbol: "sun.max.fill"),
    ]

    /// 直径がこれより大きくなる、次の目印
    static func next(after diameter: Double) -> ScaleReference? {
        all.first { $0.height > diameter }
    }
}
