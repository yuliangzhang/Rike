import Foundation

/// 时间轴上的一段。
struct TimelineSegment: Identifiable, Hashable, Sendable {
    enum Track: String, Sendable { case planned, actual }

    var id: UUID
    var track: Track
    /// 相对当日起点的**已流逝分钟**（elapsed），不是墙钟读数。见下方轴语义说明。
    var startOffset: Double
    var endOffset: Double
    var title: String
    /// 起/止被当日边界裁剪（跨零点的延续段）。
    var clippedStart: Bool = false
    var clippedEnd: Bool = false
    /// 该计划块的墙钟时间在当日**不存在**（春令时被跳过的那一小时）。
    var wallClockNonexistent: Bool = false
    /// 墙钟标签，用于 tooltip。
    var label: String = ""

    var lengthOffset: Double { max(0, endOffset - startOffset) }
}

struct TimelineTick: Hashable, Sendable {
    var offset: Double     // elapsed 分钟
    var label: String      // 墙钟标签，秋令时会出现两个 "01"
}

/// 落在当日投影范围之外的实际记录。
///
/// 这类记录**不能被静默丢弃**。典型场景：在珀斯建立了 09-01 的记录，
/// 飞到纽约，当地仍是 09-01 晚上继续记录——但那个时刻已经越过了珀斯的 09-01。
/// Ribbon 画不出来，可它确实存在（Markdown 导出里也有），
/// 所以必须在 UI 上明确告诉用户「有 N 条落在范围外」，而不是让它们消失。
struct OutOfRangeBlock: Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    /// 按该块**自己发生地**的时区渲染的墙钟标签。
    var label: String
    var timeZoneIdentifier: String
}

struct DayProjection: Hashable, Sendable {
    /// 轴总长 = 当日真实时长。春令时 1380，秋令时 1500，平日 1440。
    var axisLength: Double
    var ticks: [TimelineTick]
    var planned: [TimelineSegment]
    var actual: [TimelineSegment]
    /// 「现在」的位置；不在当日则为 nil。
    var nowOffset: Double?
    /// 有记录但画不到轴上的实际块。为空是常态。
    var outOfRange: [OutOfRangeBlock] = []
}

/// 把 DayRecord 投影成可绘制的线段。**纯函数，可测。**
///
/// ## 轴语义（审查要求明确定义）
///
/// 轴是 **elapsed-time 轴**：`offset = instant - dayStart`（分钟）。
/// 轴长等于当日真实时长，因此 DST 当天不是 1440。
///
/// 为什么不用「墙钟读数轴」：
/// - **秋令时**当天 01:30 出现两次。墙钟轴会把两个不同的真实区间画到同一位置，
///   一个 01:30→03:30 的真实 120 分钟区间会被画成 120 分钟宽——但另一个
///   重复小时里的区间会与它重叠，无法区分。elapsed 轴天然把两者分开。
/// - **春令时**当天 02:00–03:00 不存在。elapsed 轴上这段直接不占宽度，
///   长度自然是 1380，与真实经过时间一致。
///
/// 代价：轴上的**刻度标签**不再等距递增（秋令时会出现两个 "01"）。
/// 这是诚实的表示——那天确实有两个 01 点。
///
/// 计划块是**墙钟意图**，因此先把墙钟分钟换算成真实 instant 再求 elapsed；
/// 春令时被跳过的墙钟时间标记 `wallClockNonexistent`，仍然绘制（意图是真实存在的）。
enum DayTimelineProjection {

    static func project(record: DayRecord, now: Date? = nil, lang: Lang) -> DayProjection {
        let key = record.key
        guard let dayInterval = key.dayInterval else {
            return DayProjection(axisLength: 1440, ticks: [], planned: [], actual: [], nowOffset: nil)
        }
        let cal = key.calendar
        let dayStart = dayInterval.start
        let dayEnd = dayInterval.end
        let axisLength = dayInterval.duration / 60.0

        // MARK: 刻度：沿真实时间每小时走一步，标签取该时刻的墙钟小时
        var ticks: [TimelineTick] = []
        var cursor = dayStart
        var guardCount = 0
        while cursor < dayEnd && guardCount < 30 {
            guardCount += 1
            let offset = cursor.timeIntervalSince(dayStart) / 60.0
            let hour = cal.component(.hour, from: cursor)
            ticks.append(TimelineTick(offset: offset, label: String(format: "%02d", hour)))
            guard let next = cal.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        // MARK: 计划块：墙钟意图 → instant → elapsed
        let plannedSegs: [TimelineSegment] = record.planned.map { blk in
            let (s, sExists) = elapsed(forWallClockMinute: blk.startMinute, dayStart: dayStart,
                                       dayEnd: dayEnd, calendar: cal, axisLength: axisLength)
            let (e, eExists) = elapsed(forWallClockMinute: blk.endMinute, dayStart: dayStart,
                                       dayEnd: dayEnd, calendar: cal, axisLength: axisLength)
            return TimelineSegment(
                id: blk.id,
                track: .planned,
                startOffset: min(s, e),
                endOffset: max(s, e),
                title: blk.title,
                wallClockNonexistent: !(sExists && eExists),
                label: blk.rangeLabel(lang)
            )
        }

        // MARK: 实际块：instant → elapsed，按当日边界裁剪
        var outOfRange: [OutOfRangeBlock] = []
        let actualSegs: [TimelineSegment] = record.actual.compactMap { blk in
            // 时间还没填满的块不上时间带。它在「实际」列里看得见，
            // 只是还没有位置可画 —— 这不是丢数据，是它本来就还没有时刻。
            guard let rawStart = blk.start, let blkEnd = blk.end else { return nil }
            let rawEnd = max(rawStart, blkEnd)
            guard rawEnd > dayStart, rawStart < dayEnd else {
                // 完全在当日投影之外 —— 记下来，不静默丢弃
                var ownCal = Calendar(identifier: .gregorian)
                ownCal.timeZone = blk.timeZone
                _ = ownCal
                outOfRange.append(OutOfRangeBlock(
                    id: blk.id,
                    title: blk.title.isEmpty ? S.untitled.text(lang) : blk.title,
                    label: blk.rangeLabel(recordTimeZoneIdentifier: key.timeZoneIdentifier,
                                          lang: lang),
                    timeZoneIdentifier: blk.timeZoneIdentifier))
                return nil
            }

            let cs = rawStart < dayStart
            let ce = rawEnd > dayEnd
            let s = max(rawStart, dayStart).timeIntervalSince(dayStart) / 60.0
            let e = min(rawEnd, dayEnd).timeIntervalSince(dayStart) / 60.0
            guard e > s else { return nil }

            return TimelineSegment(
                id: blk.id,
                track: .actual,
                startOffset: s,
                endOffset: e,
                title: blk.title,
                clippedStart: cs,
                clippedEnd: ce,
                label: blk.rangeLabel(recordTimeZoneIdentifier: key.timeZoneIdentifier,
                                      lang: lang)
            )
        }

        var nowOffset: Double?
        if let n = now, n >= dayStart, n < dayEnd {
            nowOffset = n.timeIntervalSince(dayStart) / 60.0
        }

        return DayProjection(axisLength: axisLength,
                             ticks: ticks,
                             planned: plannedSegs,
                             actual: actualSegs,
                             nowOffset: nowOffset,
                             outOfRange: outOfRange)
    }

    /// 墙钟分钟 → elapsed 偏移。返回 (offset, 该墙钟时间是否真实存在)。
    static func elapsed(forWallClockMinute minute: Int,
                        dayStart: Date,
                        dayEnd: Date,
                        calendar: Calendar,
                        axisLength: Double) -> (Double, Bool) {
        // 1440 表示当日结束
        if minute >= PlannedBlock.dayMinutes { return (axisLength, true) }

        var comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
        comps.hour = minute / 60
        comps.minute = minute % 60
        comps.second = 0

        guard let instant = calendar.date(from: comps) else {
            // 极端情况：按比例落位
            return (Double(minute) / Double(PlannedBlock.dayMinutes) * axisLength, false)
        }

        // 春令时：Foundation 会把不存在的墙钟时间前移。回读比对即可判定。
        let backHour = calendar.component(.hour, from: instant)
        let backMinute = calendar.component(.minute, from: instant)
        let exists = (backHour == comps.hour && backMinute == comps.minute)

        let offset = instant.timeIntervalSince(dayStart) / 60.0
        return (min(max(0, offset), axisLength), exists)
    }

}
