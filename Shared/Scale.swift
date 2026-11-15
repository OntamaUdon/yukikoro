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

    /// 直径にいちばん近い（見た目の比で）目印と、その何倍か
    static func nearest(to diameter: Double) -> (reference: ScaleReference, times: Double)? {
        guard diameter > 0 else { return nil }
        guard let best = all.min(by: { abs(log(diameter / $0.height)) < abs(log(diameter / $1.height)) }) else { return nil }
        return (best, diameter / best.height)
    }
}

/// 重さを比べるための目印
struct MassReference: Equatable {
    let name: String
    /// 重さ（kg）
    let mass: Double
    let symbol: String

    static let all: [MassReference] = [
        MassReference(name: "どんぐり", mass: 0.004, symbol: "leaf.fill"),
        MassReference(name: "りんご", mass: 0.3, symbol: "carrot.fill"),
        MassReference(name: "ねこ", mass: 4, symbol: "cat.fill"),
        MassReference(name: "ひと", mass: 60, symbol: "figure.stand"),
        MassReference(name: "ピアノ", mass: 300, symbol: "pianokeys"),
        MassReference(name: "くるま", mass: 1_500, symbol: "car.fill"),
        MassReference(name: "バス", mass: 12_000, symbol: "bus.fill"),
        MassReference(name: "ひこうき", mass: 280_000, symbol: "airplane"),
        MassReference(name: "ビル", mass: 1e8, symbol: "building.2.fill"),
        MassReference(name: "やま", mass: 1e13, symbol: "mountain.2.fill"),
        MassReference(name: "つき", mass: 7.3e22, symbol: "moon.fill"),
        MassReference(name: "ちきゅう", mass: 6e24, symbol: "globe.asia.australia.fill"),
        MassReference(name: "たいよう", mass: 2e30, symbol: "sun.max.fill"),
    ]

    static func nearest(to mass: Double) -> (reference: MassReference, times: Double)? {
        guard mass > 0 else { return nil }
        guard let best = all.min(by: { abs(log(mass / $0.mass)) < abs(log(mass / $1.mass)) }) else { return nil }
        return (best, mass / best.mass)
    }
}

/// 「×2.1」「×340」のような倍率の文字
func formatTimes(_ value: Double) -> String {
    if value < 10 { return String(format: "×%.1f", value) }
    if value < 1_000 { return "×\(Int(value.rounded()))" }
    return "×" + formatMass(kg: value).replacingOccurrences(of: "kg", with: "")
}
