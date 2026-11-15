import Foundation

/// 自分の状態を JSON ファイルで保存する（アプリの Application Support に置く）。
enum PlayerStorage {
    static func fileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("yukikoro-player.json")
    }

    static func load(from url: URL = PlayerStorage.fileURL()) -> PlayerState {
        guard let data = try? Data(contentsOf: url) else { return newPlayer() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PlayerState.self, from: data)) ?? newPlayer()
    }

    @discardableResult
    static func save(_ state: PlayerState, to url: URL = PlayerStorage.fileURL()) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// はじめての状態（名前は、決まった言葉からランダムに）
    static func newPlayer() -> PlayerState {
        var state = PlayerState()
        var generator = SystemRandomNumberGenerator()
        let nick = Nickname.random(using: &generator)
        state.nickAdjective = nick.adjective
        state.nickAnimal = nick.animal
        return state
    }
}
