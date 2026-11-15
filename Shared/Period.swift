import Foundation

enum DayKey {
    /// "2026-11-14" 形式の日付キー（端末のカレンダー基準）
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 順位を競う期間。本番は 1 週間（日本時間の月曜 0:00〜日曜 24:00）。試験版は、ボタンで進める番号。
enum PeriodClock {
    static let timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = timeZone
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    /// "2026-W47"（ISO 週番号。日本時間）
    static func weekId(for date: Date) -> String {
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    /// いまの期間の名前。試験版（`betaSeq` がある）は "beta-3" のような名前。
    static func periodId(now: Date, betaSeq: Int?) -> String {
        if let betaSeq { return "beta-\(betaSeq)" }
        return weekId(for: now)
    }

    /// ひとつ前の期間の名前（殿堂に使う）。ないときは nil。
    static func previousPeriodId(now: Date, betaSeq: Int?) -> String? {
        if let betaSeq { return betaSeq > 1 ? "beta-\(betaSeq - 1)" : nil }
        guard let before = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
        return weekId(for: before)
    }

    /// この期間が終わる時刻（本番の週のみ）
    static func weekEnd(for date: Date) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.end
    }
}
