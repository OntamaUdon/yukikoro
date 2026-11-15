#if DEBUG
import Foundation

/// 起動引数で画面の見た目を確認するためのデバッグ専用機能（Release には含まれない）。
/// 例: -yukikoro-demo -yukikoro-steps 3000 -yukikoro-tab 1 -yukikoro-sheet tower
enum DemoMode {
    static var args: [String] { CommandLine.arguments }
    static var isOn: Bool { args.contains("-yukikoro-demo") }

    static func value(_ key: String) -> String? {
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// 見本の塔を置く、基準の位置（東京駅のあたり）
    static let center = GeoPoint(lat: 35.6812, lon: 139.7671)

    static var steps: Int { value("-yukikoro-steps").flatMap(Int.init) ?? 3_000 }
    /// 開いておくタブ: 0 ちず 1 ランキング 2 きろく 3 せってい
    static var tab: Int { value("-yukikoro-tab").flatMap(Int.init) ?? 0 }
    /// 開いておく画面: "tower"（いちばん近い塔） / "carry"（持っている雪玉）
    static var sheet: String? { value("-yukikoro-sheet") }

    static func player() -> PlayerState {
        var player = PlayerStorage.newPlayer()
        player.nickAdjective = 0
        player.nickAnimal = 0
        player.onboarded = true
        player.initialized = true
        player.totalSteps = steps
        // 「今日の歩数」にも、同じ歩数が出るように
        player.credited[DayKey.key(for: Date())] = steps
        return player
    }
}
#endif
