import Foundation

/// 时间与日期的统一入口。**weekday 一律由 Calendar 计算，不硬编码。**
enum GongTime {

    /// 应用统一使用的日历（公历 + 当前时区 + 周一为一周之始）。
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2   // Monday
        return c
    }

    // MARK: 日键

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-08-31"，按传入时区（默认当前）的本地日历日。
    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = dayKeyFormatter
        f.timeZone = timeZone
        return f.string(from: date)
    }

    static func date(fromDayKey key: String, timeZone: TimeZone = .current) -> Date? {
        let f = dayKeyFormatter
        f.timeZone = timeZone
        return f.date(from: key)
    }

    /// 导出文件名用的紧凑日期："20260831"
    static func compactKey(_ dayKey: String) -> String {
        dayKey.replacingOccurrences(of: "-", with: "")
    }

    // MARK: 星期

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 由 Calendar 计算，绝不硬编码。2026-08-31 → 周一
    static func weekdayLabel(_ date: Date) -> String {
        let w = calendar.component(.weekday, from: date)   // 1 = Sunday
        return weekdayNames[(w - 1 + 7) % 7]
    }

    static func weekdayLabel(dayKey: String) -> String {
        guard let d = date(fromDayKey: dayKey) else { return "" }
        return weekdayLabel(d)
    }

    /// "2026-08-31 周一"
    static func displayDate(dayKey: String) -> String {
        "\(dayKey) \(weekdayLabel(dayKey: dayKey))"
    }

    // MARK: 当日分钟 ⇄ 文本

    /// 宽松解析：`9` → 540，`930` → 570，`9:30` → 570，`09:30` → 570，`0930` → 570。
    /// 返回 nil 表示无法解析。
    static func parseMinutes(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
        guard !s.isEmpty else { return nil }

        func make(_ h: Int, _ m: Int) -> Int? {
            guard (0...24).contains(h), (0..<60).contains(m) else { return nil }
            let total = h * 60 + m
            return total <= 24 * 60 ? total : nil
        }

        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = Int(parts[0]),
                  let m = Int(parts[1].isEmpty ? "0" : String(parts[1])) else { return nil }
            return make(h, m)
        }

        guard let n = Int(s), s.allSatisfy({ $0.isNumber }) else { return nil }
        switch s.count {
        case 1, 2: return make(n, 0)            // 9 / 09 → 09:00
        case 3:    return make(n / 100, n % 100) // 930 → 09:30
        case 4:    return make(n / 100, n % 100) // 0930 → 09:30
        default:   return nil
        }
    }

    /// 540 → "09:00"；1440 → "24:00"
    static func formatMinutes(_ m: Int) -> String {
        let clamped = max(0, min(24 * 60, m))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// "09:00 至 10:30"
    static func formatRange(_ start: Int, _ end: Int) -> String {
        "\(formatMinutes(start)) 至 \(formatMinutes(end))"
    }

    // MARK: 时长

    /// 9240 秒 → "2h 34m"；1800 → "30m"；45 → "45s"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }

    /// 150 分钟 → "2h 30m"
    static func formatMinutesDuration(_ minutes: Int) -> String {
        formatDuration(TimeInterval(max(0, minutes) * 60))
    }

    // MARK: 跨日切分

    /// 把一个区间按本地自然日切分。用 Calendar，不手写午夜算术。
    static func splitByDay(start: Date, end: Date, timeZone: TimeZone = .current)
        -> [(dayKey: String, start: Date, end: Date)] {
        guard end > start else { return [] }
        var cal = calendar
        cal.timeZone = timeZone

        var result: [(String, Date, Date)] = []
        var cursor = start
        var guardCount = 0

        while cursor < end && guardCount < 400 {
            guardCount += 1
            guard let dayInterval = cal.dateInterval(of: .day, for: cursor) else { break }
            let segEnd = min(end, dayInterval.end)
            if segEnd > cursor {
                result.append((dayKey(cursor, timeZone: timeZone), cursor, segEnd))
            }
            // 用日历推进，避免 DST 当天 86400 秒的假设
            cursor = dayInterval.end > cursor ? dayInterval.end : cursor.addingTimeInterval(3600)
        }
        return result.map { (dayKey: $0.0, start: $0.1, end: $0.2) }
    }
}
