import SwiftUI
import Observation
import UIKit

/// 画面に出す、ひとこと（成功・失敗）
struct Banner: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var isGood: Bool
}

/// 「きろく」の 1 件: 自分が参加した塔
struct RecordEntry: Identifiable, Equatable {
    var tower: Tower
    var myBallIDs: [String]
    var id: String { tower.id }
}

/// 画面から使う窓口。歩数・位置・塔のデータ・おく/積むを、まとめる。
@MainActor
@Observable
final class AppModel {
    var player: PlayerState
    var config: TowerConfig = .standard
    var towers: [Tower] = []
    var betaSeq: Int?
    var ownerHash: String?
    var banner: Banner?
    var isBusy = false
    /// 読みこみのエラー（iCloud にサインインしていない、など）
    var loadError: String?

    var ranking: [Tower] = []
    var rankingLoading = false
    var rankingError: String?
    var hall: [Tower] = []
    var hallLoading = false
    var rankingPrefecture: Int?

    var record: [RecordEntry] = []
    var recordLoading = false

    /// 直近の同期で増えた歩数（画面の演出用）
    var lastGain = 0

    let location: LocationService
    @ObservationIgnored let repository: TowerRepository
    @ObservationIgnored private var lastSavedPlayer: PlayerState
    @ObservationIgnored private var lastRefreshPoint: GeoPoint?
    @ObservationIgnored private var lastRefreshAt = Date.distantPast
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    /// 画面確認用のデモ表示中は、歩数の取得も保存もしない
    @ObservationIgnored private(set) var isDemo = false

    init() {
        var initial = PlayerStorage.load()
        let location = LocationService()
        var demo = false
        #if DEBUG
        if DemoMode.isOn {
            initial = DemoMode.player()
            location.testPoint = DemoMode.center
            demo = true
            isDemo = true
        }
        #endif
        // 署名のないシミュレーターのビルドでは、CloudKit の部品を作ると落ちるので、デモのときは作らない
        let repo: TowerRepository = demo ? InMemoryTowerRepository() : CloudKitTowerRepository()
        player = initial
        lastSavedPlayer = initial
        repository = repo
        self.location = location
    }

    // MARK: 状態

    var todayKey: String { DayKey.key(for: Date()) }
    var todaySteps: Int { player.walkedSteps(on: todayKey) }
    var usedToday: Int { player.usedDay == todayKey ? player.usedToday : 0 }
    var carriedDiameter: Double { player.carriedDiameter(config: config) }

    /// 期間の名前が決まっているか（試験版は、番号を読みこんだあと）
    var isReady: Bool { !AppEnvironment.isBeta || betaSeq != nil }

    var periodId: String {
        PeriodClock.periodId(now: Date(), betaSeq: AppEnvironment.isBeta ? betaSeq : nil)
    }

    var previousPeriodId: String? {
        PeriodClock.previousPeriodId(now: Date(), betaSeq: AppEnvironment.isBeta ? betaSeq : nil)
    }

    var currentPoint: GeoPoint? { location.snapshot?.point }

    /// 自分の位置から、積める距離の中にある、いちばん近い塔
    var nearbyTower: Tower? {
        guard let point = currentPoint else { return nil }
        return towers
            .filter { $0.periodId == periodId && $0.location.distance(to: point) <= config.stackRadius }
            .min { $0.location.distance(to: point) < $1.location.distance(to: point) }
    }

    func distance(to tower: Tower) -> Double? {
        currentPoint.map { $0.distance(to: tower.location) }
    }

    func stackIssue(for tower: Tower) -> StackIssue? {
        guard let snapshot = location.snapshot else { return .location(.unavailable) }
        if let issue = snapshot.issue(config: config) { return .location(issue) }
        return TowerRules.stackIssue(
            tower: tower, carried: carriedDiameter, owner: ownerHash ?? "",
            distance: snapshot.point.distance(to: tower.location), usedToday: usedToday,
            currentPeriod: periodId, config: config
        )
    }

    var placeIssue: PlaceIssue? {
        guard let snapshot = location.snapshot else { return .location(.unavailable) }
        if let issue = snapshot.issue(config: config) { return .location(issue) }
        return TowerRules.placeIssue(
            carried: carriedDiameter, me: snapshot.point, towers: towers, currentPeriod: periodId,
            usedToday: usedToday, config: config
        )
    }

    // MARK: 起動・同期

    func bootstrap() async {
        #if DEBUG
        if isDemo, let repo = repository as? InMemoryTowerRepository {
            betaSeq = 1
            ownerHash = "me-local"
            await repo.seedDemo(around: DemoMode.center, periodId: periodId)
            await refreshTowers(force: true)
            return
        }
        #endif
        config = await repository.fetchConfig()
        do {
            ownerHash = try await repository.ownerHash()
            if AppEnvironment.isBeta { betaSeq = try await repository.betaSeq() }
            loadError = nil
        } catch let error as RepositoryError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
        await refreshTowers(force: true)
    }

    func refreshSteps() async {
        guard player.onboarded, !isDemo else { return }
        var daily = await HealthSteps.dailySteps(days: 7)
        if daily.values.reduce(0, +) == 0, let fallback = await MotionSteps.dailySteps(days: 7) {
            daily = fallback
        }
        // まだ何も取れていない初回は、ベースラインを記録せずに待つ（あとで過去分が一気に入るのを防ぐ）
        if !player.initialized && daily.values.reduce(0, +) == 0 { return }
        let gained = player.apply(daily: daily)
        if gained > 0 { lastGain = gained }
        persist()
    }

    /// 近くの塔を読みなおす。位置が 25 m 動いたか、20 秒たったとき（force なら、いつでも）。
    func refreshTowers(force: Bool = false) async {
        guard isReady, let point = currentPoint else { return }
        let moved = lastRefreshPoint.map { $0.distance(to: point) > 25 } ?? true
        let stale = Date().timeIntervalSince(lastRefreshAt) > 20
        guard force || moved || stale else { return }
        lastRefreshPoint = point
        lastRefreshAt = Date()
        do {
            let list = try await repository.towers(near: point, radius: 1_000, periodId: periodId, config: config)
            let counts = (try? await repository.reportCounts(periodId: periodId)) ?? [:]
            towers = list.map { tower -> Tower in
                var copy = tower
                copy.reportCount = counts[tower.id] ?? 0
                return copy
            }.filter { $0.reportCount < config.reportHideCount }
            loadError = nil
        } catch let error as RepositoryError {
            loadError = error.message
        } catch {
            loadError = error.localizedDescription
        }
    }

    func completeOnboarding() async {
        await HealthSteps.requestAuthorization()
        location.start()
        player.onboarded = true
        persist()
        await refreshSteps()
    }

    // MARK: おく・積む

    private func prefecture(for point: GeoPoint, isTest: Bool) async -> (code: Int, ok: Bool, issue: PlaceIssue?) {
        if let result = await PrefectureResolver.resolve(point) {
            if !result.isJapan && !isTest { return (0, false, .outsideJapan) }
            if let code = result.code { return (code, true, nil) }
        }
        if isTest { return (13, true, nil) }
        return (0, false, .unknownPrefecture)
    }

    func place() async {
        guard !isBusy else { return }
        guard isReady, let owner = ownerHash, let snapshot = location.snapshot else {
            show("まだ準備ができていません", good: false)
            return
        }
        if let issue = placeIssue {
            show(issue.message(config: config, carriedSteps: player.carriedSteps), good: false)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let result = await prefecture(for: snapshot.point, isTest: snapshot.isTest)
        guard result.ok else {
            show((result.issue ?? .unknownPrefecture).message(config: config, carriedSteps: player.carriedSteps), good: false)
            return
        }
        let stored = GeoGrid.randomPoint(inCellOf: snapshot.point, size: config.cellSize)
        let towerID = UUID().uuidString
        let ball = TowerRules.makeBall(
            towerID: towerID, index: 0, diameter: carriedDiameter, previousHeight: 0, ownerHash: owner,
            nick: player.nickname, now: Date(), periodId: periodId, prefecture: result.code
        )
        do {
            let tower = try await repository.placeBase(location: stored, prefecture: result.code, periodId: periodId,
                                                       ball: ball, config: config)
            player.markUsed(dayKey: todayKey)
            player.placedCount += 1
            persist()
            towers.removeAll { $0.id == tower.id }
            towers.append(tower)
            success()
            show("おきました！ だれかが、上に積んでくれるかも", good: true)
        } catch let error as RepositoryError {
            show(error.message, good: false)
        } catch {
            show(error.localizedDescription, good: false)
        }
    }

    @discardableResult
    func stack(on tower: Tower) async -> Bool {
        guard !isBusy else { return false }
        guard isReady, let owner = ownerHash else {
            show("まだ準備ができていません", good: false)
            return false
        }
        if let issue = stackIssue(for: tower) {
            show(issue.message(config: config), good: false)
            return false
        }
        isBusy = true
        defer { isBusy = false }
        let ball = TowerRules.makeBall(
            towerID: tower.id, index: tower.balls.count, diameter: carriedDiameter, previousHeight: tower.height,
            ownerHash: owner, nick: player.nickname, now: Date(), periodId: tower.periodId, prefecture: tower.prefecture
        )
        do {
            let outcome = try await repository.stack(ball: ball, config: config)
            switch outcome {
            case .accepted(let updated):
                player.markUsed(dayKey: todayKey)
                player.stackedCount += 1
                persist()
                replace(updated)
                success()
                let closed = updated.isClosed(config: config)
                show(closed ? "のせました！ これで、雪だるまが完成です" : "のせました！ 高さは \(formatLength(meters: updated.height)) になりました", good: true)
                return true
            case .rejected(let updated):
                replace(updated)
                show("先に、ほかの人が積みました。雪玉は、そのまま持っています", good: false)
                return false
            }
        } catch let error as RepositoryError {
            show(error.message, good: false)
        } catch {
            show(error.localizedDescription, good: false)
        }
        return false
    }

    private func replace(_ tower: Tower) {
        if let index = towers.firstIndex(where: { $0.id == tower.id }) {
            var copy = tower
            copy.reportCount = towers[index].reportCount
            towers[index] = copy
        } else {
            towers.append(tower)
        }
    }

    func shave(to diameter: Double) {
        player.shave(to: diameter, config: config)
        persist()
    }

    func report(_ tower: Tower, reason: Int) async {
        do {
            try await repository.report(towerID: tower.id, periodId: tower.periodId, reason: reason)
            show("通報しました。ありがとうございます", good: true)
        } catch let error as RepositoryError {
            show(error.message, good: false)
        } catch {
            show(error.localizedDescription, good: false)
        }
    }

    // MARK: 順位・殿堂・きろく

    func loadRanking() async {
        guard isReady else { return }
        rankingLoading = true
        defer { rankingLoading = false }
        do {
            ranking = try await repository.topTowers(periodId: periodId, prefecture: rankingPrefecture, limit: 20, config: config)
            if let previous = previousPeriodId {
                hallLoading = true
                hall = try await repository.topTowers(periodId: previous, prefecture: rankingPrefecture, limit: 10, config: config)
                hallLoading = false
            } else {
                hall = []
            }
            rankingError = nil
        } catch let error as RepositoryError {
            rankingError = error.message
        } catch {
            rankingError = error.localizedDescription
        }
        hallLoading = false
    }

    func loadRecord() async {
        guard let owner = ownerHash else { return }
        recordLoading = true
        defer { recordLoading = false }
        do {
            let balls = try await repository.myBalls(ownerHash: owner, limit: 100)
            var order: [String] = []
            for ball in balls where !order.contains(ball.towerID) { order.append(ball.towerID) }
            var entries: [RecordEntry] = []
            for id in order.prefix(30) {
                guard let tower = try await repository.tower(id: id, config: config) else { continue }
                let mine = balls.filter { $0.towerID == id }.map(\.id)
                entries.append(RecordEntry(tower: tower, myBallIDs: mine))
            }
            record = entries
            collectRewards(entries)
        } catch {
            // きろくが読めなくても、ほかの画面は使える
        }
    }

    /// 上に積まれた雪玉・完成した塔のポイントを、まだもらっていないぶんだけ受け取る
    private func collectRewards(_ entries: [RecordEntry]) {
        var changed = false
        for entry in entries {
            let tower = entry.tower
            for ball in tower.balls where entry.myBallIDs.contains(ball.id) {
                let covered = tower.balls.contains { $0.index == ball.index + 1 }
                if covered && !player.rewardedBalls.contains(ball.id) {
                    player.rewardedBalls.append(ball.id)
                    player.addPoints(PointRules.coveredReward(diameter: ball.diameter, config: config), dayKey: todayKey, dailyCap: config.dailyPointCap)
                    changed = true
                }
            }
            if tower.isClosed(config: config) && !player.rewardedTowers.contains(tower.id) {
                player.rewardedTowers.append(tower.id)
                let mine = tower.balls.filter { entry.myBallIDs.contains($0.id) }
                for ball in mine {
                    player.addPoints(PointRules.completionReward(diameter: ball.diameter, config: config), dayKey: todayKey, dailyCap: config.dailyPointCap)
                }
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: 試験用（試験版だけ）

    func betaAdvanceWeek() async {
        do {
            betaSeq = try await repository.advanceBetaSeq()
            towers = []
            ranking = []
            hall = []
            await refreshTowers(force: true)
            await loadRanking()
            show("週を終えました。新しい週のはじまりです（\(periodId)）", good: true)
        } catch let error as RepositoryError {
            show(error.message, good: false)
        } catch {
            show(error.localizedDescription, good: false)
        }
    }

    func betaAddSteps(_ n: Int) {
        player.addDebugSteps(n)
        persist()
    }

    func betaSetBallSteps(_ steps: Int) {
        player.totalSteps = max(player.totalSteps, steps)
        player.stepsAtLastUse = player.totalSteps - steps
        persist()
    }

    func betaResetUsage() {
        player.usedToday = 0
        player.usedDay = todayKey
        persist()
    }

    func betaMove(to tower: Tower) {
        location.testPoint = tower.location
        Task { await refreshTowers(force: true) }
    }

    func betaMove(to point: GeoPoint) {
        location.testPoint = point
        Task { await refreshTowers(force: true) }
    }

    func betaClearTestPoint() {
        location.testPoint = nil
        Task { await refreshTowers(force: true) }
    }

    // MARK: 設定

    func setNickname(adjective: Int, animal: Int) {
        player.nickAdjective = adjective
        player.nickAnimal = animal
        persist()
    }

    func resetAll() {
        player = PlayerStorage.newPlayer()
        record = []
        persist()
    }

    // MARK: 内部

    private func persist() {
        guard !isDemo, player != lastSavedPlayer else { return }
        PlayerStorage.save(player)
        lastSavedPlayer = player
    }

    func show(_ text: String, good: Bool) {
        banner = Banner(text: text, isGood: good)
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    private func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
