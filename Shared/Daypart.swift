import Foundation

/// 時間帯。背景の写真を切り替える。
enum Daypart: String {
    case day, dusk, night

    static func current(hour: Int) -> Daypart {
        switch hour {
        case 8..<16: return .day
        case 5..<8, 16..<19: return .dusk
        default: return .night
        }
    }

    /// 背景画像のファイル名（Resources/Backgrounds）
    var imageName: String {
        switch self {
        case .day: return "bg_day"
        case .dusk: return "bg_dusk"
        case .night: return "bg_night"
        }
    }

    var isDark: Bool { self == .night }
}
