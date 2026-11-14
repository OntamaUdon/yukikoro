import Foundation

/// 雪玉の大きさに関する定数
enum Snow {
    /// ゆきだまにできる最小の歩数
    static let minimumSteps = 300
    /// 達成上限: 雪玉はこの歩数で最大サイズに到達し、これ以上は大きくならない（超えた歩数は次の雪玉へ持ち越す）
    static let maxSteps = 30_000
}

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
