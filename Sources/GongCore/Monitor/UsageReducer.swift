import Foundation

/// 事件日志 → 每日使用统计。**纯函数、幂等、可测。**
///
/// ## 为什么必须读三天的事件
///
/// 事件按本地日期分文件存放。若 23:50 激活 Xcode、次日 00:20 切走：
/// - 只读当日文件 → 不知道 00:20 的结束事件，最后一段无法闭合
/// - 只读次日文件 → 不知道 00:00 时前台已有应用，开头一段整个丢失
///
/// 因此 `reduce` 要求调用方传入 **D-1、D、D+1 三天**的事件，内部再按当日边界裁剪。
enum UsageReducer {

    /// 需要读取的事件日期（相对目标日）。
    static func requiredDayKeys(for key: DayKey) -> [String] {
        guard let d = GongTime.date(fromDayKey: key.date, timeZone: key.timeZone) else { return [key.date] }
        let cal = key.calendar
        return [-1, 0, 1].compactMap { off in
            cal.date(byAdding: .day, value: off, to: d).map {
                GongTime.dayKey($0, timeZone: key.timeZone)
            }
        }
    }

    /// - Parameters:
    ///   - events: D-1 / D / D+1 的全部事件（顺序无关，内部会稳定排序）
    ///   - liveNow: 若该日仍在进行中且监控存活，传入「现在」用于闭合最后一段；
    ///              否则传 nil，最后一段按最后可信心跳闭合并标记 truncated。
    static func reduce(events rawEvents: [UsageEvent],
                       for key: DayKey,
                       liveNow: Date? = nil) -> UsageDay {

        guard let dayInterval = key.dayInterval else { return UsageDay(date: key.date) }
        let dayStart = dayInterval.start
        let dayEnd = dayInterval.end

        let events = usageEventsSorted(rawEvents)

        var intervals: [UsageInterval] = []
        var truncated = false

        // 状态机
        var currentApp: (bundleId: String, name: String)?
        var openedAt: Date?
        var suspended = false            // idle / sleep / session inactive
        var lastAlive: Date?             // 最后一条可信的存活证据

        func closeCurrent(at t: Date) {
            guard let app = currentApp, let start = openedAt, t > start else {
                openedAt = nil
                return
            }
            intervals.append(UsageInterval(bundleId: app.bundleId, appName: app.name,
                                           start: start, end: t))
            openedAt = nil
        }

        for ev in events {
            switch ev.e {
            case .appStart:
                lastAlive = ev.t

            case .activate:
                lastAlive = ev.t
                closeCurrent(at: ev.t)
                guard let bid = ev.bundleId, !GongPaths.isIgnored(bid) else {
                    currentApp = nil          // 过滤自身与系统瞬时进程，不污染统计
                    continue
                }
                currentApp = (bid, ev.name ?? bid)
                suspended = false
                openedAt = ev.t

            case .idleStart, .sleep, .sessionInactive:
                // 注意：idleStart 的时间戳是回溯的，已由 usageEventsSorted 放回正确位置
                closeCurrent(at: ev.t)
                if !suspended { suspended = true }

            case .idleEnd, .wake, .sessionActive:
                lastAlive = ev.t
                if suspended {
                    suspended = false
                    // 唤醒后前台应用可能已变，监控会补发 activate；
                    // 这里只在已知应用时先开一段，随后的 activate 会正确闭合它。
                    if currentApp != nil && openedAt == nil { openedAt = ev.t }
                }

            case .heartbeat:
                lastAlive = ev.t

            case .appStop:
                closeCurrent(at: ev.t)
                lastAlive = ev.t
                currentApp = nil
                suspended = false
            }
        }

        // 收尾：仍有未闭合区间
        if openedAt != nil && !suspended {
            if let now = liveNow {
                closeCurrent(at: min(now, dayEnd))
            } else if let alive = lastAlive {
                // 崩溃/强杀：只认最后一条心跳，误差上界 = 心跳周期
                closeCurrent(at: alive)
                truncated = true
            } else {
                openedAt = nil
                truncated = true
            }
        }

        // 按当日边界裁剪
        let clipped: [UsageInterval] = intervals.compactMap { iv in
            let s = max(iv.start, dayStart)
            let e = min(iv.end, dayEnd)
            guard e > s else { return nil }
            return UsageInterval(bundleId: iv.bundleId, appName: iv.appName, start: s, end: e)
        }
        .sorted { $0.start < $1.start }

        var day = UsageDay(date: key.date)
        day.intervals = clipped
        day.truncated = truncated
        return day
    }

    /// 按类别汇总秒数。
    static func categoryTotals(_ day: UsageDay, settings: AppSettings) -> [AppCategory: TimeInterval] {
        var acc: [AppCategory: TimeInterval] = [:]
        for iv in day.intervals {
            let c = settings.category(for: iv.bundleId)
            acc[c, default: 0] += iv.seconds
        }
        return acc
    }
}
