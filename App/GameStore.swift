import SwiftUI
import Observation

/// 画面から使うゲームの窓口。歩数の同期・保存をまとめる。
@MainActor
@Observable
final class GameStore {
    var state: GameState
    /// 直近の同期で増えた歩数（画面の演出用）
    var lastGain = 0
    /// 「データをリセット」「舞台を片付ける」のたびに増える（画面を作り直すための印）
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
        // 飾る舞台（作品はひとつ）は、いつも1つ用意しておく
        _ = initial.ensureStage()
        state = initial
        lastSaved = initial
        isDemo = demo
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
        persist()
        await refresh()
    }

    // MARK: ゆきだま・作品

    /// 転がしている雪玉を「ゆきだま」として取り出す（飾れるようになる）
    @discardableResult
    func makePiece() -> SnowPiece? {
        guard let piece = state.makePiece() else { return nil }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        persist()
        return piece
    }

    /// 転がしている雪玉の形を更新する（成形したとき）
    func updateRolling(shape: SnowShape) {
        state.updateRolling(shape: shape)
        persist()
    }

    func updateStock(id: UUID, shape: SnowShape) {
        state.updateStock(id: id, shape: shape)
        persist()
    }

    func takeFromStock(id: UUID) -> SnowPiece? {
        let piece = state.takeFromStock(id: id)
        persist()
        return piece
    }

    func returnToStock(_ piece: SnowPiece) {
        state.returnToStock(piece)
        persist()
    }

    /// 飾る舞台（作品はひとつ）
    func ensureStage() -> Artwork {
        let stage = state.ensureStage()
        persist()
        return stage
    }

    func saveArtwork(_ artwork: Artwork) {
        state.saveArtwork(artwork)
        persist()
    }

    /// 舞台を片付ける。置いていたゆきだまは手元に戻る。
    func clearStage() {
        state.clearStage()
        persist()
        resetCount += 1
    }

    // MARK: 検証用

    func addDebugSteps(_ n: Int) {
        state.addBonus(steps: n)
        persist()
    }

    func resetAll() {
        var fresh = GameState()
        _ = fresh.ensureStage()
        state = fresh
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
