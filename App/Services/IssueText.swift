import Foundation

/// 「おけない・積めない」理由を、やさしい文にする。
extension LocationIssue {
    var message: String {
        switch self {
        case .unavailable: return "いまの位置が、まだ取れていません"
        case .inaccurate: return "位置の精度が低いようです。少し待ってください"
        case .tooFast: return "動いている間は、操作できません。立ち止まってください"
        case .spoofed: return "位置が正しくないようです"
        }
    }
}

extension StackIssue {
    func message(config: TowerConfig) -> String {
        switch self {
        case .frozen: return "この週は、もう終わりました"
        case .closed: return "この雪だるまは、完成しました"
        case .ownTop: return "一番上が自分の雪玉です。ほかの人が積むのを待ちましょう"
        case .tooBig(let max): return "雪玉が大きすぎます。\(formatLength(meters: max))以下にけずると、のせられます"
        case .tooSmall(let min): return "雪玉が小さすぎます。\(formatLength(meters: min))から、のせられます"
        case .tooFar(let distance):
            return "あと\(formatDistance(meters: max(1, distance - config.stackRadius)))ほど近づくと、のせられます"
        case .dailyLimit: return "今日は、もう上限までおきました"
        case .location(let issue): return issue.message
        }
    }
}

extension PlaceIssue {
    func message(config: TowerConfig, carriedSteps: Int) -> String {
        switch self {
        case .tooSmall(let min):
            let need = max(0, BallSize.steps(forDiameter: min, config: config) - carriedSteps)
            return "土台にするには、\(formatLength(meters: min))に育てましょう（あと約\(formatSteps(need))歩）"
        case .nearTower: return "近くに雪だるまがあります。そこに積んでみましょう"
        case .dailyLimit: return "今日は、もう上限までおきました"
        case .outsideJapan: return "日本の外では、おけません"
        case .unknownPrefecture: return "場所の県が分かりませんでした。あとで、もう一度ためしてください"
        case .location(let issue): return issue.message
        }
    }
}
