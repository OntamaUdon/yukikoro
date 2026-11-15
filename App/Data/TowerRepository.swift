import Foundation

/// 試験版か本番か。TestFlight の試験版は true。本番に出すときに false にする。
enum AppEnvironment {
    static let isBeta = true
    static let containerID = "iCloud.com.ontamaudon.yukikoro"
    /// 持ち主のハッシュに混ぜる、アプリ固有の塩
    static let ownerSalt = "yukikoro-v2-owner"
}

enum RepositoryError: Error, Equatable {
    case notSignedIn
    case network
    case permission
    case notFound
    case other(String)

    var message: String {
        switch self {
        case .notSignedIn: return "iCloud にサインインすると、みんなの雪だるまが見えます"
        case .network: return "つながりませんでした。あとで、もう一度ためしてください"
        case .permission: return "この操作は、まだ許可されていません"
        case .notFound: return "見つかりませんでした"
        case .other(let text): return text
        }
    }
}

enum StackOutcome {
    case accepted(Tower)
    /// 同時に積まれて、先に積んだ人がいた（自分の雪玉は無効）
    case rejected(Tower)
}

/// 塔のデータの置き場。本番は CloudKit、試験・画面確認用はメモリ。
protocol TowerRepository: Sendable {
    /// 自分を表すハッシュ（iCloud のユーザー ID から作る）
    func ownerHash() async throws -> String
    /// 設定データ（読めないときは標準の値）
    func fetchConfig() async -> TowerConfig
    /// 試験版の、期間の番号
    func betaSeq() async throws -> Int
    func advanceBetaSeq() async throws -> Int
    /// 近くの塔（有効な雪玉だけをのせたもの）
    func towers(near: GeoPoint, radius: Double, periodId: String, config: TowerConfig) async throws -> [Tower]
    func tower(id: String, config: TowerConfig) async throws -> Tower?
    /// 土台をおく。`ball.towerID` が、新しい塔の id。
    func placeBase(location: GeoPoint, prefecture: Int, periodId: String, ball: Ball, config: TowerConfig) async throws -> Tower
    /// 塔に積む。同時に積まれたときは、`rejected`。
    func stack(ball: Ball, config: TowerConfig) async throws -> StackOutcome
    /// 高さの順位（上位だけ、雪玉の記録から高さを計算し直して確かめたもの）
    func topTowers(periodId: String, prefecture: Int?, limit: Int, config: TowerConfig) async throws -> [Tower]
    /// 自分が積んだ雪玉
    func myBalls(ownerHash: String, limit: Int) async throws -> [Ball]
    func report(towerID: String, periodId: String, reason: Int) async throws
    func reportCounts(periodId: String) async throws -> [String: Int]
}
