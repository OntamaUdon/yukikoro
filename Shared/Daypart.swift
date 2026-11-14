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

    /// 背景イラストのファイル名（Resources/Backgrounds）
    var imageName: String { "ill_" + rawValue }

    var isDark: Bool { self == .night }
}
