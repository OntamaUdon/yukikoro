import Foundation

/// 状態を JSON ファイルで保存する（アプリの Application Support に置く）。
enum GameStorage {
    static func fileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("yukikoro-state.json")
    }

    static func load(from url: URL = GameStorage.fileURL()) -> GameState {
        guard let data = try? Data(contentsOf: url) else { return GameState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(GameState.self, from: data)) ?? GameState()
    }

    @discardableResult
    static func save(_ state: GameState, to url: URL = GameStorage.fileURL()) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
