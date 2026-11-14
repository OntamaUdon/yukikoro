import Foundation

enum SharedConfig {
    /// ウィジェットと状態を共有する App Group。Bundle ID を変えたらここと entitlements も合わせる。
    static let appGroup = "group.com.example.yukikoro"
}

/// 状態を JSON ファイルで保存する。App Group が使えない環境では通常の保存先に退避する。
enum GameStorage {
    static func fileURL() -> URL {
        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup) {
            return container.appendingPathComponent("yukikoro-state.json")
        }
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
