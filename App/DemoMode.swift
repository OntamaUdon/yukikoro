#if DEBUG
import SwiftUI
import simd

/// 起動引数で画面の見た目を確認するためのデバッグ専用機能（Release には含まれない）。
/// 例: -yukikoro-demo -yukikoro-tab 2 -yukikoro-hour 22.5
enum DemoMode {
    static var args: [String] { CommandLine.arguments }
    static var isOn: Bool { args.contains("-yukikoro-demo") }

    static func value(_ key: String) -> String? {
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var hour: Double? { value("-yukikoro-hour").flatMap(Double.init) }
    static var steps: Int { value("-yukikoro-steps").flatMap(Int.init) ?? 4_200 }

    static var mass: Double? { value("-yukikoro-mass").flatMap(Double.init) }

    /// 動作確認用の状態（歩数、または重さを直接指定）
    static func state() -> GameState {
        var s = GameState()
        s.onboarded = true
        s.initialized = true
        if let m = mass {
            s.mass = m
            s.peakDiameter = max(s.peakDiameter, s.diameter)
            s.totalSteps = steps
        } else {
            s.addBonus(steps: steps)
        }
        s.markSeen()
        s.credited[DayKey.key(for: Date())] = 5_200
        return s
    }
}
#endif
