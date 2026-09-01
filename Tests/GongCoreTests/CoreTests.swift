import XCTest
@testable import GongCore

/// 用 UTC 绝对时刻构造，避免测试依赖运行机器的时区。
private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

final class TimeTests: XCTestCase {

    func testWeekdayIsComputedNotHardcoded() {
        // codex r1 抓到的错误：设计稿把 2026-08-31 写成了周五。
        XCTAssertEqual(GongTime.weekdayLabel(dayKey: "2026-08-31"), "周一")
        XCTAssertEqual(GongTime.weekdayLabel(dayKey: "2026-09-06"), "周日")
        XCTAssertEqual(GongTime.displayDate(dayKey: "2026-08-31"), "2026-08-31 周一")
    }

    func testParseMinutesLenient() {
        XCTAssertEqual(GongTime.parseMinutes("9"), 540)
        XCTAssertEqual(GongTime.parseMinutes("09"), 540)
        XCTAssertEqual(GongTime.parseMinutes("930"), 570)
        XCTAssertEqual(GongTime.parseMinutes("0930"), 570)
        XCTAssertEqual(GongTime.parseMinutes("9:30"), 570)
        XCTAssertEqual(GongTime.parseMinutes("09:30"), 570)
        XCTAssertEqual(GongTime.parseMinutes("9：30"), 570)   // 全角冒号
        XCTAssertEqual(GongTime.parseMinutes("24:00"), 1440)
        XCTAssertEqual(GongTime.parseMinutes(" 8 "), 480)
        XCTAssertNil(GongTime.parseMinutes(""))
        XCTAssertNil(GongTime.parseMinutes("abc"))
        XCTAssertNil(GongTime.parseMinutes("25:00"))
        XCTAssertNil(GongTime.parseMinutes("9:70"))
    }

    func testFormatting() {
        XCTAssertEqual(GongTime.formatMinutes(540), "09:00")
        XCTAssertEqual(GongTime.formatMinutes(1440), "24:00")
        XCTAssertEqual(GongTime.formatRange(480, 570), "08:00 至 09:30")
        XCTAssertEqual(GongTime.formatDuration(9240), "2h 34m")
        XCTAssertEqual(GongTime.formatDuration(1800), "30m")
        XCTAssertEqual(GongTime.formatDuration(45), "45s")
    }

    func testSplitByDayCrossMidnight() {
        let tz = TimeZone(identifier: "Australia/Perth")!   // 无 DST
        // Perth = UTC+8。2026-08-31 23:50 本地 = 15:50 UTC
        let start = utc(2026, 8, 31, 15, 50)
        let end   = utc(2026, 8, 31, 16, 20)                // 次日 00:20 本地
        let parts = GongTime.splitByDay(start: start, end: end, timeZone: tz)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].dayKey, "2026-08-31")
        XCTAssertEqual(parts[1].dayKey, "2026-09-01")
        let total = parts.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 1800, accuracy: 1)            // 总时长守恒
    }
}

final class DayKeyTests: XCTestCase {
    private let ny = "America/New_York"

    func testNormalDayIs1440() {
        XCTAssertEqual(DayKey(date: "2026-08-31", timeZoneIdentifier: ny).lengthMinutes, 1440)
    }

    func testSpringForwardDayIs1380() {
        // 2026-03-08 美东：02:00 → 03:00，当天只有 23 小时
        XCTAssertEqual(DayKey(date: "2026-03-08", timeZoneIdentifier: ny).lengthMinutes, 1380)
    }

    func testFallBackDayIs1500() {
        // 2026-11-01 美东：02:00 → 01:00，当天有 25 小时
        XCTAssertEqual(DayKey(date: "2026-11-01", timeZoneIdentifier: ny).lengthMinutes, 1500)
    }
}

final class ProjectionTests: XCTestCase {
    private let ny = "America/New_York"

    func testAxisLengthMatchesRealDayLength() {
        var rec = DayRecord(key: DayKey(date: "2026-03-08", timeZoneIdentifier: ny))
        rec.planned = [PlannedBlock(start: 9 * 60, end: 10 * 60, title: "晨会")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertEqual(p.axisLength, 1380, accuracy: 0.5)
        XCTAssertEqual(p.ticks.count, 23)                  // 春令时只有 23 个整点
    }

    func testSpringForwardNonexistentWallClockIsFlagged() {
        var rec = DayRecord(key: DayKey(date: "2026-03-08", timeZoneIdentifier: ny))
        rec.planned = [
            PlannedBlock(start: 2 * 60 + 30, end: 2 * 60 + 45, title: "不存在的时刻"),
            PlannedBlock(start: 9 * 60, end: 10 * 60, title: "正常")
        ]
        let p = DayTimelineProjection.project(record: rec)
        let gap = p.planned.first { $0.title == "不存在的时刻" }
        let ok  = p.planned.first { $0.title == "正常" }
        XCTAssertEqual(gap?.wallClockNonexistent, true, "春令时被跳过的墙钟时间必须被标记")
        XCTAssertEqual(ok?.wallClockNonexistent, false)
        // 09:00 在春令时当天的 elapsed 是 480，不是 540
        XCTAssertEqual(ok?.startOffset ?? -1, 480, accuracy: 0.5)
    }

    func testFallBackRepeatedHourGetsDistinctPositions() {
        // 这是墙钟轴会画错、elapsed 轴才能画对的关键用例。
        var rec = DayRecord(key: DayKey(date: "2026-11-01", timeZoneIdentifier: ny))
        // 当日 00:00 EDT = 04:00 UTC
        let first  = utc(2026, 11, 1, 5, 30)   // 第一个 01:30（EDT）→ elapsed 90
        let second = utc(2026, 11, 1, 6, 30)   // 第二个 01:30（EST）→ elapsed 150
        rec.actual = [
            ActualBlock(start: first,  end: first.addingTimeInterval(600),  title: "第一次"),
            ActualBlock(start: second, end: second.addingTimeInterval(600), title: "第二次")
        ]
        let p = DayTimelineProjection.project(record: rec)
        let a = p.actual.first { $0.title == "第一次" }
        let b = p.actual.first { $0.title == "第二次" }
        XCTAssertEqual(a?.startOffset ?? -1, 90,  accuracy: 0.5)
        XCTAssertEqual(b?.startOffset ?? -1, 150, accuracy: 0.5)
        XCTAssertNotEqual(a?.startOffset, b?.startOffset, "重复的墙钟小时必须落在不同位置")
        XCTAssertEqual(p.axisLength, 1500, accuracy: 0.5)
    }

    func testActualBlockClippedAtDayBoundaries() {
        let tz = "Australia/Perth"
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: tz))
        // Perth UTC+8：2026-08-31 23:50 本地 = 15:50 UTC，跨到次日 00:20
        rec.actual = [ActualBlock(start: utc(2026, 8, 31, 15, 50),
                                  end:   utc(2026, 8, 31, 16, 20),
                                  title: "跨零点")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertEqual(p.actual.count, 1)
        let seg = p.actual[0]
        XCTAssertTrue(seg.clippedStart, "延续自前一天的段必须标记裁剪")
        XCTAssertFalse(seg.clippedEnd)
        XCTAssertEqual(seg.startOffset, 0, accuracy: 0.5)
        XCTAssertEqual(seg.endOffset, 20, accuracy: 0.5)
    }

    /// 越界的实际记录不画到轴上，但**必须被报告**，不能静默消失。
    func testBlockEntirelyOutsideDayIsReportedNotSwallowed() {
        var rec = DayRecord(key: DayKey(date: "2026-09-05", timeZoneIdentifier: "Australia/Perth"))
        rec.actual = [ActualBlock(start: utc(2026, 8, 1, 0, 0),
                                  end:   utc(2026, 8, 1, 1, 0),
                                  timeZoneIdentifier: "America/New_York", title: "别的日子")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertTrue(p.actual.isEmpty, "画不到轴上")
        XCTAssertEqual(p.outOfRange.count, 1, "但必须出现在 outOfRange 里")
        XCTAssertEqual(p.outOfRange.first?.title, "别的日子")
        XCTAssertEqual(p.outOfRange.first?.timeZoneIdentifier, "America/New_York",
                       "标签应按该块自己发生地的时区渲染")
    }

    /// 跨时区同日：在珀斯建的 09-01，飞到纽约当地仍是 09-01 晚上继续记录。
    /// 那个时刻已越过珀斯的 09-01，必须被报告而不是消失。
    func testCrossTimeZoneSameDateEveningIsReported() {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        // 纽约 2026-09-01 20:00 EDT = 2026-09-02 00:00 UTC（珀斯已是 09-02 08:00）
        let nyEvening = utc(2026, 9, 2, 0, 0)
        rec.actual = [ActualBlock(start: nyEvening, end: nyEvening.addingTimeInterval(3600),
                                  timeZoneIdentifier: "America/New_York", title: "在纽约记的")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertTrue(p.actual.isEmpty)
        XCTAssertEqual(p.outOfRange.count, 1, "跨时区越界的记录必须被明确告知，不能静默隐藏")
    }

    func testNormalDayHasNoOutOfRange() {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        let t = utc(2026, 9, 1, 2, 0)     // 珀斯 10:00
        rec.actual = [ActualBlock(start: t, end: t.addingTimeInterval(3600), title: "正常")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertEqual(p.actual.count, 1)
        XCTAssertTrue(p.outOfRange.isEmpty, "常态下不应有越界提示")
    }

    func testNowOffsetOnlyWithinDay() {
        let rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        // 2026-09-01 10:00 Perth = 02:00 UTC
        let inside = DayTimelineProjection.project(record: rec, now: utc(2026, 9, 1, 2, 0))
        XCTAssertEqual(inside.nowOffset ?? -1, 600, accuracy: 0.5)
        let outside = DayTimelineProjection.project(record: rec, now: utc(2026, 9, 9, 2, 0))
        XCTAssertNil(outside.nowOffset)
    }
}

final class ModelInvariantTests: XCTestCase {

    func testPlannedBlockClampsToValidRange() {
        var b = PlannedBlock(start: -100, end: 5000, title: "x")
        XCTAssertEqual(b.startMinute, 0)
        XCTAssertEqual(b.endMinute, 1440)          // 允许到午夜

        b.setRange(start: 600, end: 500)           // end < start
        XCTAssertLessThan(b.startMinute, b.endMinute, "不变式：start < end")

        b.setRange(start: 1439, end: 1439)
        XCTAssertEqual(b.startMinute, 1439)
        XCTAssertEqual(b.endMinute, 1440)

        let full = PlannedBlock(start: 22 * 60, end: 24 * 60, title: "到午夜")
        XCTAssertEqual(full.endMinute, 1440)
        XCTAssertEqual(full.rangeLabel, "22:00 至 24:00")
    }

    func testFloorAndMitAreUnique() {
        var rec = DayRecord(date: "2026-08-31")
        let a = Todo(text: "A"), b = Todo(text: "B"), c = Todo(text: "C")
        rec.todos = [a, b, c]

        rec.setKind(.floor, for: a.id)
        rec.setKind(.floor, for: b.id)              // 第二次设下限
        XCTAssertEqual(rec.todos.filter { $0.kind == .floor }.count, 1, "下限只能有一条")
        XCTAssertEqual(rec.floorTodo?.id, b.id, "后设的生效，前一条降级")

        rec.setKind(.mit, for: c.id)
        XCTAssertEqual(rec.todos.filter { $0.kind == .mit }.count, 1, "最重要只能有一条")
    }

    func testNormalizeRepairsDuplicateKinds() {
        var rec = DayRecord(date: "2026-08-31")
        // 模拟外部损坏的数据：两条下限
        rec.todos = [Todo(text: "A", kind: .floor), Todo(text: "B", kind: .floor)]
        rec.normalize()
        XCTAssertEqual(rec.todos.filter { $0.kind == .floor }.count, 1)
        XCTAssertEqual(rec.todos.map(\.order), [0, 1])
    }

    func testStatusIsDerivedNotDuplicated() {
        // 双重事实源的回归测试：DaySummary 不得再持有 floorStatus。
        var rec = DayRecord(date: "2026-08-31")
        var t = Todo(text: "下限", kind: .floor)
        t.status = .done
        rec.todos = [t]
        XCTAssertEqual(rec.floorStatus, .done)
        XCTAssertEqual(rec.mitStatus, .notRecorded, "没有 MIT 时应为未记录，而不是失败")
    }

    func testWidgetTodoOrdering() {
        var rec = DayRecord(date: "2026-08-31")
        rec.todos = [
            Todo(text: "普通1", kind: .normal, order: 0),
            Todo(text: "最重要", kind: .mit, order: 1),
            Todo(text: "下限", kind: .floor, order: 2),
            Todo(text: "普通2", kind: .normal, order: 3)
        ]
        XCTAssertEqual(rec.widgetTodos.prefix(3).map(\.text), ["下限", "最重要", "普通1"])
    }

    func testClarityEntryIncompleteWithoutFirstStep() {
        var e = ClarityEntry(stuckOn: "token 刷新策略不确定")
        XCTAssertFalse(e.isComplete, "没拆出第一步就不算写完")
        e.firstStep = "   "
        XCTAssertFalse(e.isComplete, "空白不算")
        e.firstStep = "把两个方案各写三行发给 Xiaojia"
        XCTAssertTrue(e.isComplete)
    }
}

final class UsageEventOrderingTests: XCTestCase {

    func testStableOrderingWithBacktrackedIdleStart() {
        // idleStart 时间戳回溯，会落在更晚的 heartbeat 之后 —— 必须按 (t, runId, seq) 定序。
        let run = "run-1"
        let hb1 = UsageEvent(t: utc(2026, 8, 31, 1, 0), e: .heartbeat, runId: run, seq: 1, tz: "UTC")
        let hb2 = UsageEvent(t: utc(2026, 8, 31, 1, 1), e: .heartbeat, runId: run, seq: 2, tz: "UTC")
        // 第 3 条写入，但时间戳回溯到 00:58
        let idle = UsageEvent(t: utc(2026, 8, 31, 0, 58), e: .idleStart, runId: run, seq: 3, tz: "UTC")

        let sorted = usageEventsSorted([hb2, idle, hb1])
        XCTAssertEqual(sorted.map(\.seq), [3, 1, 2], "应按时间戳排序，idleStart 回到它真正发生的位置")
    }

    func testTieBreakBySeqWithinSameTimestamp() {
        let t = utc(2026, 8, 31, 1, 0)
        let a = UsageEvent(t: t, e: .activate, runId: "r", seq: 5, tz: "UTC", bundleId: "A", name: "A")
        let b = UsageEvent(t: t, e: .activate, runId: "r", seq: 6, tz: "UTC", bundleId: "B", name: "B")
        XCTAssertEqual(usageEventsSorted([b, a]).map(\.seq), [5, 6], "同时间戳按 seq 定序")
    }

    func testDifferentRunsAreDeterministic() {
        let t = utc(2026, 8, 31, 1, 0)
        let a = UsageEvent(t: t, e: .heartbeat, runId: "run-a", seq: 9, tz: "UTC")
        let b = UsageEvent(t: t, e: .heartbeat, runId: "run-b", seq: 1, tz: "UTC")
        let once = usageEventsSorted([a, b]).map(\.runId)
        let twice = usageEventsSorted([b, a]).map(\.runId)
        XCTAssertEqual(once, twice, "跨 run 的定序必须确定，不依赖输入顺序")
    }
}
