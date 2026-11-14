import SwiftUI
import Observation

/// 画面から使うゲームの窓口。歩数の同期・保存をまとめる。
@MainActor
@Observable
final class GameStore {
    var state: GameState
    /// 直近の同期で増えた歩数（画面の演出用）
    var lastGain = 0
    /// 選んでいるタブ（0:ホーム 1:ゆきだま 2:さくひん 3:きろく 4:せってい）
    var tab = 0
    /// 整える画面を開いているゆきだま（手元のもの）
    var sculptingPieceID: UUID?
    /// 設定画面のバージョンを5回タップすると有効になる検証用メニュー
    var developerMode = false

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
        #if DEBUG
        if demo {
            tab = DemoMode.tab
            if DemoMode.sculpts { sculptingPieceID = initial.stock.first?.id }
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
        persist()
        await refresh()
    }

    // MARK: ゆきだま・作品

    /// 転がした雪玉を「ゆきだま」にして、整える画面へ進む
    func makePiece() {
        guard let piece = state.makePiece() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        persist()
        tab = 1
        sculptingPieceID = piece.id
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

    func newArtwork() -> Artwork {
        let artwork = state.newArtwork()
        persist()
        return artwork
    }

    func saveArtwork(_ artwork: Artwork) {
        state.saveArtwork(artwork)
        persist()
    }

    func deleteArtwork(id: UUID) {
        state.deleteArtwork(id: id)
        persist()
    }

    // MARK: 検証用

    func addDebugSteps(_ n: Int) {
        state.addBonus(steps: n)
        persist()
    }

    func resetAll() {
        state = GameState()
        sculptingPieceID = nil
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
