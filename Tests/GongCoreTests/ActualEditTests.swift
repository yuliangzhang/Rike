import XCTest
@testable import GongCore

/// 「实际」列的时间可编辑（用户反馈：监控填进来的区间和 ＋新增 的默认一小时都改不了，
/// 而我们并不是一直坐在电脑前，时间必须能改成事实）。
///
/// 这里锁住三条语义：
/// ① 墙钟一律按**块自己的时区**解释，不按记录时区；
/// ② 改开始 → 结束不动；越过结束才整块平移，保住时长（绝不凭空造出跨日巨块）；
/// ③ 改结束 → 不晚于开始时视为跨夜，顺延到次日。
final class ActualBlockWallClockEditTests: XCTestCase {

    private let perth = "Australia/Perth"          // UTC+8，全年无夏令时
    private let newYork = "America/New_York"

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// 珀斯 2026-09-01 的某个墙钟时刻
    private func perthTime(_ h: Int, _ mi: Int, day: Int = 1) -> Date {
        utc(2026, 9, day, h - 8, mi)               // UTC+8
    }

    private func block(_ startH: Int, _ startM: Int, _ endH: Int, _ endM: Int,
                       tz: String? = nil) -> ActualBlock {
        ActualBlock(start: perthTime(startH, startM), end: perthTime(endH, endM),
                    timeZoneIdentifier: tz ?? perth, title: "t", source: .monitor)
    }

    // MARK: ① 基本编辑

    /// 监控填进来 09:12–10:45，人记得其实 09:30 才真正开始 —— 结束不该跟着动。
    func testEditingStartKeepsEndWhenStillEarlier() {
        var b = block(9, 12, 10, 45)
        b.setStartWallClock(9 * 60 + 30)
        XCTAssertEqual(b.startWallClockMinutes, 9 * 60 + 30)
        XCTAssertEqual(b.endWallClockMinutes, 10 * 60 + 45, "改开始不应连带改结束")
        XCTAssertEqual(b.durationSeconds, 75 * 60, accuracy: 1)
    }

    func testEditingEndShortensBlock() {
        var b = block(9, 0, 12, 0)
        b.setEndWallClock(10 * 60)
        XCTAssertEqual(b.endWallClockMinutes, 10 * 60)
        XCTAssertEqual(b.durationSeconds, 3600, accuracy: 1)
    }

    // MARK: ② 开始越过结束 → 平移，不是膨胀

    /// 10:00–11:00 把开始改成 14:00：人的意思是「这件事其实是下午干的」。
    /// 若按「结束顺延到次日」处理会得到 14:00–次日 11:00 的 21 小时巨块，把时间轴填满。
    func testEditingStartPastEndSlidesBlockPreservingDuration() {
        var b = block(10, 0, 11, 0)
        b.setStartWallClock(14 * 60)
        XCTAssertEqual(b.startWallClockMinutes, 14 * 60)
        XCTAssertEqual(b.endWallClockMinutes, 15 * 60, "应平移保时长，而不是顺延到次日")
        XCTAssertEqual(b.durationSeconds, 3600, accuracy: 1)
    }

    /// 任何编辑之后，结束都必须严格晚于开始——否则时长为 0 的块会在轴上消失。
    func testEndAlwaysStrictlyAfterStart() {
        for m in stride(from: 0, through: 24 * 60, by: 37) {
            var b = block(10, 0, 11, 0)
            b.setStartWallClock(m)
            XCTAssertGreaterThan(b.end, b.start, "开始改成 \(m) 分后结束不晚于开始")
            var c = block(10, 0, 11, 0)
            c.setEndWallClock(m)
            XCTAssertGreaterThan(c.end, c.start, "结束改成 \(m) 分后不晚于开始")
        }
    }

    // MARK: ③ 跨夜

    /// 23:00 至 01:00 是真实存在的（干到后半夜），不该被压成 23:00 至 23:01。
    func testEditingEndBeforeStartMeansNextDay() {
        var b = block(23, 0, 23, 30)
        b.setEndWallClock(1 * 60)
        XCTAssertEqual(b.endWallClockMinutes, 60)
        XCTAssertEqual(b.durationSeconds, 2 * 3600, accuracy: 1, "23:00→次日 01:00 应为 2 小时")
        XCTAssertEqual(b.end.timeIntervalSince(b.start), 7200, accuracy: 1)
    }

    /// 已经跨夜的块，把结束改回当天：23:00–次日01:00 → 23:00–23:30。
    func testEditingEndOfCrossMidnightBlockBackToSameDay() {
        var b = ActualBlock(start: perthTime(23, 0), end: perthTime(1, 0, day: 2),
                            timeZoneIdentifier: perth, title: "t", source: .manual)
        XCTAssertEqual(b.durationSeconds, 2 * 3600, accuracy: 1)
        b.setEndWallClock(23 * 60 + 30)
        XCTAssertEqual(b.durationSeconds, 30 * 60, accuracy: 1)
    }

    // MARK: ④ 跨时区：按块自己的时区解释，不按记录的

    /// 珀斯的记录里有一条发生在纽约的块。改成 09:00 必须是**纽约的** 09:00。
    /// 若按记录时区解释，会把它写成珀斯 09:00（= 纽约前一天 21:00），事实就错了。
    func testWallClockIsInterpretedInBlocksOwnTimeZone() {
        // 纽约 2026-09-01 20:00 = UTC 2026-09-02 00:00（EDT, UTC-4）
        var b = ActualBlock(start: utc(2026, 9, 2, 0, 0), end: utc(2026, 9, 2, 1, 0),
                            timeZoneIdentifier: newYork, title: "在纽约做的", source: .manual)
        XCTAssertEqual(b.startWallClockMinutes, 20 * 60, "编辑框应显示纽约的 20:00")

        b.setStartWallClock(9 * 60)
        XCTAssertEqual(b.startWallClockMinutes, 9 * 60)
        // 结束仍是纽约 21:00：改开始不连带改结束，两个框显示的都是真实存储值。
        XCTAssertEqual(b.rangeLabel(recordTimeZoneIdentifier: perth, lang: .zh),
                       "09:00 至 21:00（America/New_York）")

        // 同一瞬间在珀斯是 21:00 —— 证明我们没有用记录时区去解释
        var perthCal = Calendar(identifier: .gregorian)
        perthCal.timeZone = TimeZone(identifier: perth)!
        XCTAssertEqual(perthCal.component(.hour, from: b.start), 21)
    }

    func testForeignTimeZoneLabel() {
        let foreign = block(10, 0, 11, 0, tz: newYork)
        XCTAssertEqual(foreign.foreignTimeZoneLabel(recordTimeZoneIdentifier: perth), newYork)
        let local = block(10, 0, 11, 0)
        XCTAssertNil(local.foreignTimeZoneLabel(recordTimeZoneIdentifier: perth))
    }

    // MARK: ⑤ 夏令时

    /// 春令时当天纽约没有 02:30 这个墙钟。编辑必须仍然产出一个有效瞬间，
    /// 不能崩、不能悄悄回到纪元 0，也不能让结束早于开始。
    func testSpringForwardNonexistentWallClockStillYieldsValidInstant() {
        // 2026-03-08 是美国春令时切换日：02:00 直接跳到 03:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: newYork)!
        let noon = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        var b = ActualBlock(start: noon, end: noon.addingTimeInterval(3600),
                            timeZoneIdentifier: newYork, title: "t", source: .manual)

        b.setStartWallClock(2 * 60 + 30)
        XCTAssertGreaterThan(b.end, b.start)
        XCTAssertEqual(cal.component(.day, from: b.start), 8, "必须仍落在同一天")
        let m = b.startWallClockMinutes
        XCTAssertTrue((0..<1440).contains(m))
        XCTAssertGreaterThanOrEqual(m, 3 * 60, "不存在的 02:30 应被推到间隔之后，实际 \(m)")
    }

    /// 秋令时当天 01:30 出现两次，Calendar 取第一次。只要求：有效、结束晚于开始、当天。
    func testFallBackAmbiguousWallClockResolvesDeterministically() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: newYork)!
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        var b = ActualBlock(start: noon, end: noon.addingTimeInterval(3600),
                            timeZoneIdentifier: newYork, title: "t", source: .manual)

        b.setStartWallClock(90)
        XCTAssertEqual(b.startWallClockMinutes, 90)
        XCTAssertEqual(cal.component(.day, from: b.start), 1)
        XCTAssertGreaterThan(b.end, b.start)
    }

    /// 编辑后的块经过一次 normalize（DayStore.mutate 的必经之路）不应丢失或错序。
    func testEditedBlocksSurviveNormalize() {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: perth))
        rec.actual = [block(14, 0, 15, 0), block(9, 0, 10, 0)]
        rec.normalize()
        XCTAssertEqual(rec.actual.map(\.startWallClockMinutes), [9 * 60, 14 * 60])

        rec.actual[0].setStartWallClock(16 * 60)
        rec.normalize()
        XCTAssertEqual(rec.actual.count, 2, "编辑不应丢块")
        XCTAssertEqual(rec.actual.map(\.startWallClockMinutes), [14 * 60, 16 * 60], "应重新按开始排序")
    }
}

// MARK: - codex r6 的发现：24:00 作为「开始」

extension ActualBlockWallClockEditTests {

    /// `GongTime.parseMinutes` 接受 24:00（=1440）。作为**结束**它有意义（当天末尾），
    /// 作为**开始**没有意义——那一天已经结束了。
    ///
    /// 修复前：1440 → `comps.hour = 24` → Calendar 滚到次日 00:00，
    /// 整块静默跳到另一天，然后只在「越界记录」提示里出现。
    /// 与计划列的行为也不一致（`PlannedBlock.clamp` 把开始夹在 `0..<1440`）。
    func testStartAt2400IsClampedAndBlockStaysOnSameDay() {
        var b = block(10, 0, 11, 0)
        let originalDay = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: perth)!, from: b.start).day

        b.setStartWallClock(24 * 60)

        XCTAssertEqual(b.startWallClockMinutes, 23 * 60 + 59, "24:00 应被夹到 23:59")
        let newDay = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: perth)!, from: b.start).day
        XCTAssertEqual(newDay, originalDay, "块不该跳到次日")
        XCTAssertGreaterThan(b.end, b.start)
    }

    /// 结束仍然允许 24:00 —— 那是「干到当天末尾」，是真实意图。
    func testEndAt2400IsAllowedAndMeansEndOfDay() {
        var b = block(22, 0, 23, 0)
        b.setEndWallClock(24 * 60)
        XCTAssertEqual(b.durationSeconds, 2 * 3600, accuracy: 1, "22:00 到 24:00 应为 2 小时")
    }

    /// 与计划列同一套约定：开始 0..<1440，结束 (start, 1440]。
    func testStartClampMatchesPlannedBlockConvention() {
        let (ps, _) = PlannedBlock.clamp(start: 24 * 60, end: 24 * 60)
        XCTAssertEqual(ps, 24 * 60 - 1)

        var b = block(10, 0, 11, 0)
        b.setStartWallClock(24 * 60)
        XCTAssertEqual(b.startWallClockMinutes, ps, "实际列的开始夹取必须和计划列一致")
    }
}
