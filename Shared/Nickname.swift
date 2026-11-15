import Foundation

/// 名前は、決まった言葉の組み合わせだけ（自由入力は無い）。例: 「ふわふわのペンギン」
enum Nickname {
    static let adjectives = [
        "ふわふわ", "ぽかぽか", "きらきら", "のんびり", "ころころ", "ひんやり", "もこもこ", "ゆらゆら", "しんしん", "ほかほか",
        "つるつる", "まんまる", "ぴかぴか", "すいすい", "わくわく", "こっそり", "ゆっくり", "どっしり", "にこにこ", "ぱたぱた",
    ]

    static let animals = [
        "ペンギン", "うさぎ", "きつね", "くま", "ふくろう", "あざらし", "りす", "しろくま", "ねこ", "いぬ",
        "たぬき", "かもしか", "ことり", "らっこ", "ひつじ", "やぎ", "うま", "かめ", "いるか", "くじら",
    ]

    static func make(adjective: Int, animal: Int) -> String {
        let a = adjectives[((adjective % adjectives.count) + adjectives.count) % adjectives.count]
        let b = animals[((animal % animals.count) + animals.count) % animals.count]
        return "\(a)の\(b)"
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> (adjective: Int, animal: Int) {
        (Int.random(in: 0..<adjectives.count, using: &generator), Int.random(in: 0..<animals.count, using: &generator))
    }
}
