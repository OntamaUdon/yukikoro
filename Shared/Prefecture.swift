import Foundation

/// 都道府県（コード 1〜47。JIS の順番）
enum Prefecture {
    static let names = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県", "茨城県", "栃木県", "群馬県",
        "埼玉県", "千葉県", "東京都", "神奈川県", "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県",
        "岐阜県", "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
        "鳥取県", "島根県", "岡山県", "広島県", "山口県", "徳島県", "香川県", "愛媛県", "高知県", "福岡県",
        "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
    ]

    private static let romanNames = [
        "hokkaido", "aomori", "iwate", "miyagi", "akita", "yamagata", "fukushima", "ibaraki", "tochigi", "gunma",
        "saitama", "chiba", "tokyo", "kanagawa", "niigata", "toyama", "ishikawa", "fukui", "yamanashi", "nagano",
        "gifu", "shizuoka", "aichi", "mie", "shiga", "kyoto", "osaka", "hyogo", "nara", "wakayama",
        "tottori", "shimane", "okayama", "hiroshima", "yamaguchi", "tokushima", "kagawa", "ehime", "kochi", "fukuoka",
        "saga", "nagasaki", "kumamoto", "oita", "miyazaki", "kagoshima", "okinawa",
    ]

    static func name(code: Int) -> String {
        guard code >= 1, code <= names.count else { return "—" }
        return names[code - 1]
    }

    /// 逆ジオコーディングの `administrativeArea`（「東京都」「Tokyo」など）から、コードを決める。
    static func code(fromAdministrativeArea area: String?) -> Int? {
        guard let area, !area.isEmpty else { return nil }
        let trimmed = area.trimmingCharacters(in: .whitespaces)
        if let index = names.firstIndex(of: trimmed) { return index + 1 }
        // 「東京」のように、末尾の 都・道・府・県 がないとき
        if let index = names.firstIndex(where: { stripSuffix($0) == stripSuffix(trimmed) && !stripSuffix(trimmed).isEmpty }) {
            return index + 1
        }
        let roman = trimmed.lowercased()
            .replacingOccurrences(of: " prefecture", with: "")
            .replacingOccurrences(of: "-ken", with: "")
            .replacingOccurrences(of: "-fu", with: "")
            .replacingOccurrences(of: "-to", with: "")
        if let index = romanNames.firstIndex(of: roman) { return index + 1 }
        return nil
    }

    private static func stripSuffix(_ name: String) -> String {
        if name == "北海道" { return name }
        guard let last = name.last, "都道府県".contains(last) else { return name }
        return String(name.dropLast())
    }
}
