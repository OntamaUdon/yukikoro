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
        #if DEBUG
        if demo, DemoMode.showsCompletion, let last = initial.snowmen.last {
            pendingResult = CompletionResult(snowman: last, isNewKind: true)
        }
        #endif
    }

    var todayKey: String { DayKey.key(for: Date()) }
    var todaySteps: Int { state.creditedSteps(on: todayKey) }

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
        persist(forceWidget: true)
        await refresh()
    }

    // MARK: 雪だるま

    func completeSnowman() {
        guard let result = state.complete() else { return }
        pendingResult = result
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        persist(forceWidget: true)
        exportWidgetImages()
    }

    // MARK: ウィジェット用の画像

    /// ウィジェットは 3D を描けないので、雪玉と最新の雪だるまを画像にして共有フォルダへ置く。
    func exportWidgetImages() {
        guard !isDemo else { return }
        let rgb = SharedFiles.backgroundRGB
        let background = UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        if let ball = BallSnapshot.image(size: CGSize(width: 160, height: 160), background: background),
           let data = ball.pngData() {
            try? data.write(to: SharedFiles.url(SharedFiles.ballImageName), options: .atomic)
        }
        if let latest = state.snowmen.last,
           let image = SnowmanSnapshot.image(for: latest, size: CGSize(width: 200, height: 200), background: background),
           let data = image.pngData() {
            try? data.write(to: SharedFiles.url(SharedFiles.snowmanImageName), options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
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
        guard !isDemo, state != lastSaved else { return }
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
