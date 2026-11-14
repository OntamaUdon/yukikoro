import SwiftUI
import Observation
import WidgetKit

/// 画面から使うゲームの窓口。歩数の同期・保存・ウィジェット更新をまとめる。
@MainActor
@Observable
final class GameStore {
    var state: GameState
    /// 直近の同期で増えた歩数（画面の演出用）
    var lastGain = 0
    /// 雪だるま完成直後に出すシート用
    var pendingResult: CompletionResult?
    /// 設定画面のバージョンを5回タップすると有効になる検証用メニュー
    var developerMode = false

    @ObservationIgnored private var lastSaved: GameState
    @ObservationIgnored private var lastHaptic = Date.distantPast
    @ObservationIgnored private var lastWidgetReload = Date.distantPast

    init() {
        let loaded = GameStorage.load()
        state = loaded
        lastSaved = loaded
    }

    var todayKey: String { DayKey.key(for: Date()) }
    var todaySteps: Int { state.creditedSteps(on: todayKey) }

    // MARK: 同期

    func refresh() async {
        guard state.onboarded else { return }
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
        persist(forceWidget: true)
        await refresh()
    }

    // MARK: 雪だるま

    func completeSnowman() {
        guard let result = state.complete() else { return }
        pendingResult = result
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        persist(forceWidget: true)
    }

    // MARK: 検証用

    func addDebugSteps(_ n: Int) {
        state.addBonus(steps: n)
        persist(forceWidget: true)
    }

    func resetAll() {
        state = GameState()
        pendingResult = nil
        persist(forceWidget: true)
    }

    // MARK: 内部

    private func persist(forceWidget: Bool = false) {
        guard state != lastSaved else { return }
        GameStorage.save(state)
        lastSaved = state
        let now = Date()
        if forceWidget || now.timeIntervalSince(lastWidgetReload) > 300 {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = now
        }
    }

    private func tapHaptic(strong: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastHaptic) > 4 else { return }
        lastHaptic = now
        UIImpactFeedbackGenerator(style: strong ? .soft : .light).impactOccurred()
    }
}
