import Foundation
import CloudKit
import CryptoKit
import CoreLocation

/// CloudKit（公開データベース）の置き場。レコードの種類と項目は docs/CLOUDKIT_SETUP.md のとおりに、管理画面で作っておく。
/// 注意: 署名のないシミュレーターのビルドでは動かない。TestFlight の実機で使う。
final class CloudKitTowerRepository: TowerRepository, @unchecked Sendable {
    private enum RecordKind {
        static let tower = "Tower"
        static let ball = "Ball"
        static let report = "Report"
        static let config = "Config"
        static let betaClock = "BetaClock"
    }

    private let containerID: String
    /// 使うときまで作らない（CloudKit の権限が無いビルドで、起動時に落ちないように）
    private lazy var container = CKContainer(identifier: containerID)
    private var database: CKDatabase { container.publicCloudDatabase }

    init(containerID: String = AppEnvironment.containerID) {
        self.containerID = containerID
    }

    // MARK: 共通

    private func map(_ error: Error) -> RepositoryError {
        if let known = error as? RepositoryError { return known }
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated: return .notSignedIn
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .internalError:
            return .network
        case .permissionFailure: return .permission
        case .unknownItem: return .notFound
        default: return .other(ck.localizedDescription)
        }
    }

    /// 複数のレコードを保存する。1 つでも失敗したら、エラーにする。
    private func saveAll(_ records: [CKRecord], policy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: policy, atomically: false)
        for (_, saved) in result.saveResults {
            _ = try saved.get()
        }
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data((AppEnvironment.ownerSalt + value).utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    // MARK: 自分・設定

    func ownerHash() async throws -> String {
        do {
            let id = try await container.userRecordID()
            return Self.hash(id.recordName)
        } catch {
            throw map(error)
        }
    }

    func fetchConfig() async -> TowerConfig {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: "main"))
            if let json = record["json"] as? String, let data = json.data(using: .utf8),
               let config = try? JSONDecoder().decode(TowerConfig.self, from: data) {
                return config
            }
        } catch {
            // 設定が無いときは、標準の値
        }
        return .standard
    }

    func betaSeq() async throws -> Int {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: "current"))
            return max(1, Int((record["seq"] as? Int64) ?? 1))
        } catch let error as CKError where error.code == .unknownItem {
            return 1
        } catch {
            throw map(error)
        }
    }

    func advanceBetaSeq() async throws -> Int {
        let id = CKRecord.ID(recordName: "current")
        do {
            let record: CKRecord
            do {
                record = try await database.record(for: id)
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: RecordKind.betaClock, recordID: id)
                record["seq"] = Int64(1)
            }
            let next = Int((record["seq"] as? Int64) ?? 1) + 1
            record["seq"] = Int64(next)
            try await saveAll([record], policy: .allKeys)
            return next
        } catch {
            throw map(error)
        }
    }

    // MARK: 変換

    private func ball(from record: CKRecord) -> Ball? {
        guard let towerID = record["towerID"] as? String,
              let index = record["index"] as? Int64,
              let diameter = record["diameter"] as? Double,
              let owner = record["ownerHash"] as? String else { return nil }
        return Ball(
            id: record.recordID.recordName,
            towerID: towerID,
            index: Int(index),
            diameter: diameter,
            cumHeight: (record["cumHeight"] as? Double) ?? diameter,
            ownerHash: owner,
            nick: (record["nick"] as? String) ?? "",
            look: Int((record["look"] as? Int64) ?? 0),
            createdAt: record.creationDate ?? Date(),
            periodId: (record["periodId"] as? String) ?? "",
            prefecture: Int((record["prefecture"] as? Int64) ?? 0)
        )
    }

    private func ballRecord(_ ball: Ball) -> CKRecord {
        let record = CKRecord(recordType: RecordKind.ball, recordID: CKRecord.ID(recordName: ball.id))
        record["towerID"] = ball.towerID
        record["index"] = Int64(ball.index)
        record["diameter"] = ball.diameter
        record["cumHeight"] = ball.cumHeight
        record["ownerHash"] = ball.ownerHash
        record["nick"] = ball.nick
        record["look"] = Int64(ball.look)
        record["periodId"] = ball.periodId
        record["prefecture"] = Int64(ball.prefecture)
        return record
    }

    private func ballsOfTower(_ id: String) async throws -> [Ball] {
        let query = CKQuery(recordType: RecordKind.ball, predicate: NSPredicate(format: "towerID == %@", id))
        query.sortDescriptors = [NSSortDescriptor(key: "index", ascending: true)]
        let result = try await database.records(matching: query, resultsLimit: 200)
        return result.matchResults.compactMap { try? $0.1.get() }.compactMap { ball(from: $0) }
    }

    private func tower(from record: CKRecord, config: TowerConfig) async throws -> Tower? {
        guard let location = record["location"] as? CLLocation else { return nil }
        let id = record.recordID.recordName
        let balls = try await ballsOfTower(id)
        return TowerRules.tower(
            id: id,
            location: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
            periodId: (record["periodId"] as? String) ?? "",
            prefecture: Int((record["prefecture"] as? Int64) ?? 0),
            createdAt: record.creationDate ?? Date(),
            balls: balls,
            config: config
        )
    }

    // MARK: 塔

    func towers(near: GeoPoint, radius: Double, periodId: String, config: TowerConfig) async throws -> [Tower] {
        do {
            let center = CLLocation(latitude: near.lat, longitude: near.lon)
            let predicate = NSPredicate(format: "distanceToLocation:fromLocation:(location, %@) < %f AND periodId == %@",
                                        center, radius, periodId)
            let query = CKQuery(recordType: RecordKind.tower, predicate: predicate)
            let result = try await database.records(matching: query, resultsLimit: 100)
            let records = result.matchResults.compactMap { try? $0.1.get() }
            return await withTaskGroup(of: Tower?.self) { group in
                for record in records {
                    group.addTask { try? await self.tower(from: record, config: config) }
                }
                var towers: [Tower] = []
                for await tower in group {
                    if let tower, !tower.balls.isEmpty { towers.append(tower) }
                }
                return towers
            }
        } catch {
            throw map(error)
        }
    }

    func tower(id: String, config: TowerConfig) async throws -> Tower? {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: id))
            return try await tower(from: record, config: config)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw map(error)
        }
    }

    func placeBase(location: GeoPoint, prefecture: Int, periodId: String, ball: Ball, config: TowerConfig) async throws -> Tower {
        do {
            let towerRecord = CKRecord(recordType: RecordKind.tower, recordID: CKRecord.ID(recordName: ball.towerID))
            towerRecord["location"] = CLLocation(latitude: location.lat, longitude: location.lon)
            towerRecord["periodId"] = periodId
            towerRecord["prefecture"] = Int64(prefecture)
            try await saveAll([towerRecord, ballRecord(ball)], policy: .ifServerRecordUnchanged)
            return TowerRules.tower(id: ball.towerID, location: location, periodId: periodId, prefecture: prefecture,
                                    createdAt: Date(), balls: [ball], config: config)
        } catch {
            throw map(error)
        }
    }

    func stack(ball: Ball, config: TowerConfig) async throws -> StackOutcome {
        do {
            try await saveAll([ballRecord(ball)], policy: .ifServerRecordUnchanged)
            // 同時に積んだ人がいないか、少し待ってから、もう一度読んで確かめる
            try await Task.sleep(for: .seconds(1.5))
            guard let tower = try await tower(id: ball.towerID, config: config) else { throw RepositoryError.notFound }
            return tower.balls.contains { $0.id == ball.id } ? .accepted(tower) : .rejected(tower)
        } catch {
            throw map(error)
        }
    }

    // MARK: 順位・記録・通報

    func topTowers(periodId: String, prefecture: Int?, limit: Int, config: TowerConfig) async throws -> [Tower] {
        do {
            let predicate: NSPredicate
            if let prefecture {
                predicate = NSPredicate(format: "periodId == %@ AND prefecture == %d", periodId, prefecture)
            } else {
                predicate = NSPredicate(format: "periodId == %@", periodId)
            }
            let query = CKQuery(recordType: RecordKind.ball, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "cumHeight", ascending: false)]
            let result = try await database.records(matching: query, resultsLimit: 100)
            let balls = result.matchResults.compactMap { try? $0.1.get() }.compactMap { ball(from: $0) }
            // 同じ塔は 1 回だけ。上から候補を取り、雪玉の記録から高さを計算し直して確かめる
            var ids: [String] = []
            for ball in balls where !ids.contains(ball.towerID) {
                ids.append(ball.towerID)
                if ids.count >= max(limit * 3, 20) { break }
            }
            let verified: [Tower] = await withTaskGroup(of: Tower?.self) { group in
                for id in ids {
                    group.addTask { try? await self.tower(id: id, config: config) }
                }
                var towers: [Tower] = []
                for await tower in group {
                    if let tower, !tower.balls.isEmpty, tower.periodId == periodId { towers.append(tower) }
                }
                return towers
            }
            return Ranking.top(verified, prefecture: prefecture, limit: limit)
        } catch {
            throw map(error)
        }
    }

    func myBalls(ownerHash: String, limit: Int) async throws -> [Ball] {
        do {
            let query = CKQuery(recordType: RecordKind.ball, predicate: NSPredicate(format: "ownerHash == %@", ownerHash))
            let result = try await database.records(matching: query, resultsLimit: max(limit, 50))
            let balls = result.matchResults.compactMap { try? $0.1.get() }.compactMap { ball(from: $0) }
            return Array(balls.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
        } catch {
            throw map(error)
        }
    }

    func report(towerID: String, periodId: String, reason: Int) async throws {
        do {
            let record = CKRecord(recordType: RecordKind.report)
            record["towerID"] = towerID
            record["periodId"] = periodId
            record["reason"] = Int64(reason)
            _ = try await database.save(record)
        } catch {
            throw map(error)
        }
    }

    func reportCounts(periodId: String) async throws -> [String: Int] {
        do {
            let query = CKQuery(recordType: RecordKind.report, predicate: NSPredicate(format: "periodId == %@", periodId))
            let result = try await database.records(matching: query, resultsLimit: 400)
            var counts: [String: Int] = [:]
            let records = result.matchResults.compactMap { try? $0.1.get() }
            for record in records {
                if let id = record["towerID"] as? String { counts[id, default: 0] += 1 }
            }
            return counts
        } catch {
            throw map(error)
        }
    }
}
