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

    /// 開いておく画面の確認用: "-yukikoro-sheet shop" / "-yukikoro-sheet menu"
    static var sheet: String? { value("-yukikoro-sheet") }
    static var materials: Int? { value("-yukikoro-materials").flatMap(Int.init) }

    static var mass: Double? { value("-yukikoro-mass").flatMap(Double.init) }

    /// 仲間の見た目の確認用: "-yukikoro-crew 段,数"（0=ゆきんこ 1=でかゆきんこ 2=そりいた 3=クローラー 4=おおがた）
    static var crew: (tier: Int, count: Int)? {
        guard let text = value("-yukikoro-crew") else { return nil }
        let parts = text.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    /// 動作確認用の状態（歩数、または重さを直接指定）
    static func state() -> GameState {
        var s = GameState()
        s.onboarded = true
        s.initialized = true
        if let m = mass {
            s.mass = m
            var k = 0
            while Lane.capMass(stage: k, pack: s.pack) < m { k += 1 }
            s.stage = k
            s.peakDiameter = max(s.peakDiameter, s.diameter)
            s.totalSteps = steps
        } else {
            s.addBonus(steps: steps)
        }
        if let crew = crew {
            let ids = ["kid", "big", "plank", "crawler", "heavy"]
            s.owned[ids[min(max(crew.tier, 0), ids.count - 1)]] = crew.count
        }
        if let materials = materials { s.materials = materials }
        s.markSeen()
        s.credited[DayKey.key(for: Date())] = 5_200
        return s
    }
}
#endif
