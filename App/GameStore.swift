import SwiftUI
import Observation

/// 画面から使うゲームの窓口。歩数の同期・保存をまとめる。
@MainActor
@Observable
final class GameStore {
    var state: GameState
    /// 直近の同期で増えた歩数（画面の演出用）
    var lastGain = 0
    /// 「データをリセット」のたびに増える（画面を作り直すための印）
    var resetCount = 0

    @ObservationIgnored private var lastSaved: GameState
    @ObservationIgnored private var lastHaptic = Date.distantPast
    /// デバッグ用のデモ表示中は、歩数の取得も保存もしない
    @ObservationIgnored private var isDemo = false

    init() {
        var initial = GameStorage.load()
        var demo = false
        #if DEBUG
        if DemoMode.isOn {
            initial = DemoMode.state()
            demo = true
        }
        #endif
        state = initial
        lastSaved = initial
        isDemo = demo
    }

    var todayKey: String { DayKey.key(for: Date()) }
    var todaySteps: Int { state.walkedSteps(on: todayKey) }

    // MARK: 同期

    func refresh() async {
        guard state.onboarded, !isDemo else { return }
        var daily = await HealthSteps.dailySteps(days: 7)
        if daily.values.reduce(0, +) == 0, let fallback = await MotionSteps.dailySteps(days: 7) {
            daily = fallback
        }
        // まだ何も取れていない初回は、ベースラインを記録せずに待つ（後で過去分が一気に入るのを防ぐ）
        if !state.initialized && daily.values.reduce(0, +) == 0 { return }

        let gained = state.apply(daily: daily, todayKey: todayKey)
        if gained > 0 {
            lastGain = gained
            tapHaptic(strong: gained >= 100)
        }
        persist()
    }

    func completeOnboarding() async {
        await HealthSteps.requestAuthorization()
        state.onboarded = true
        persist()
        await refresh()
    }

    // MARK: 検証用

    func addDebugSteps(_ n: Int) {
        state.addBonus(steps: n)
        persist()
    }

    /// 雪玉をタップして、ぎゅっと固める
    func packSnow() {
        guard !state.blackHole else { return }
        state.tapPack()
        persist()
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
    }

    @discardableResult
    func buy(_ item: ShopItem) -> Bool {
        guard state.buy(item) else { return false }
        persist()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }

    /// いま見せている雪玉の状態を、「最後に見せた状態」として覚える
    func markSeen() {
        state.markSeen()
        persist()
    }

    /// ブラックホールになったあと、新しい雪玉ではじめる
    func startOver() {
        state = state.restarted()
        resetCount += 1
        persist()
    }

    func resetAll() {
        state = GameState()
        resetCount += 1
        persist()
    }

    // MARK: 内部

    private func persist() {
        guard !isDemo, state != lastSaved else { return }
        GameStorage.save(state)
        lastSaved = state
    }

    private func tapHaptic(strong: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastHaptic) > 4 else { return }
        lastHaptic = now
        UIImpactFeedbackGenerator(style: strong ? .soft : .light).impactOccurred()
    }
}
