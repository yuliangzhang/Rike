import XCTest
@testable import GongCore

/// 「实际」列的时间**可以是空的**。
///
/// 来源是自用期的一条反馈：手工新增一条实际时，应用替人填了「现在起一小时」。
/// 但用这个应用的时候人往往**不在**做那件事——开完会回来补录、晚上回顾一整天，
/// 当前时刻和那件事发生的时刻毫无关系，猜出来的值几乎每次都得先删掉再重填。
///
/// 于是「还没填时间」成了模型里一个正经状态，而不是用一个假时间冒充。
/// 这个文件锁住它的全部后果：不参与计算、不上时间带、排序沉底、
/// 导出不吞内容、旧文件照常读得进来、而且必须有路**回到**空。
final class BlankActualTimeTests: XCTestCase {
    private let perth = "Australia/Perth"

    private func day(_ date: String = "2026-09-05") -> DayKey {
        DayKey(date: date, timeZoneIdentifier: perth)
    }
    private func anchor(_ date: String = "2026-09-05") -> Date {
        day(date).dayInterval!.start
    }
    private func blank(_ title: String) -> ActualBlock {
        ActualBlock(timeZoneIdentifier: perth, title: title, source: .manual)
    }
    private func timed(_ hour: Int, _ title: String, on date: String = "2026-09-05") -> ActualBlock {
        var b = blank(title)
        b.setStartWallClock(hour * 60, anchoredOn: anchor(date))
        b.setEndWallClock(hour * 60 + 30, anchoredOn: anchor(date))
        return b
    }
    private var perthCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: perth)!
        return c
    }

    // MARK: ① 空块本身

    func testNewManualBlockCarriesNoTimeAtAll() {
        let b = blank("写周报")
        XCTAssertNil(b.start)
        XCTAssertNil(b.end)
        XCTAssertFalse(b.isTimed)
        XCTAssertNil(b.interval)
        XCTAssertNil(b.startWallClockMinutes, "编辑框应显示空白，而不是某个猜出来的时刻")
        XCTAssertNil(b.endWallClockMinutes)
        XCTAssertEqual(b.durationSeconds, 0, "未填时间不能贡献时长——列头那个合计是拿来看的")
    }

    /// 只填了开始，是正常的输入中途状态。不要替他把另一头补上——
    /// 那等于又回到了「先删掉系统猜的值」那套。
    func testFillingOnlyTheStartLeavesTheEndBlank() {
        var b = blank("调研")
        b.setStartWallClock(14 * 60, anchoredOn: anchor())
        XCTAssertEqual(b.startWallClockMinutes, 14 * 60)
        XCTAssertNil(b.end)
        XCTAssertEqual(b.durationSeconds, 0, "只有一头的块还不构成区间")
    }

    func testFillingOnlyTheEndLeavesTheStartBlank() {
        var b = blank("调研")
        b.setEndWallClock(15 * 60, anchoredOn: anchor())
        XCTAssertEqual(b.endWallClockMinutes, 15 * 60)
        XCTAssertNil(b.start)
        XCTAssertEqual(b.durationSeconds, 0)
    }

    func testFillingBothEndsMakesItARealInterval() {
        var b = blank("写周报")
        b.setStartWallClock(14 * 60, anchoredOn: anchor())
        b.setEndWallClock(15 * 60 + 30, anchoredOn: anchor())
        XCTAssertTrue(b.isTimed)
        XCTAssertEqual(b.durationSeconds, 90 * 60, accuracy: 1)
    }

    // MARK: ② 补录必须落在这条记录的那一天

    /// 补录的场景就是「人不在那个时刻」。块自己一个时刻都没有时，
    /// 得有人告诉它这是哪一天——不能拿 `Date()` 顶上。
    func testBlankBlockAnchorsOnTheRecordsDayNotToday() {
        var b = blank("昨天的会")
        b.setStartWallClock(9 * 60 + 30, anchoredOn: anchor("2026-09-05"))
        let c = perthCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: b.start!)
        XCTAssertEqual([c.year!, c.month!, c.day!, c.hour!, c.minute!], [2026, 9, 5, 9, 30])
    }

    /// 拿不到锚就什么都不做。宁可这次输入不生效，也不要凭 `Date()` 猜一天——
    /// 那会让在 09-05 的界面上补录的时间悄悄落到今天，而且当场看不出来。
    func testWithoutAnAnchorNothingIsGuessed() {
        var b = blank("")
        b.setStartWallClock(9 * 60)
        b.setEndWallClock(10 * 60)
        XCTAssertNil(b.start)
        XCTAssertNil(b.end)
    }

    // MARK: ③ 必须有路回到空

    /// 有了「空」这个状态，就必须能改回去。
    /// 否则手滑填错一次，这一格就永远回不到空白了。
    func testTimesCanBeClearedBackToBlank() {
        var b = timed(10, "会议")
        XCTAssertTrue(b.isTimed)

        b.clearEndWallClock()
        XCTAssertNil(b.end)
        XCTAssertNotNil(b.start, "清结束不该连带清掉开始")
        XCTAssertEqual(b.durationSeconds, 0)

        b.clearStartWallClock()
        XCTAssertNil(b.start)
        XCTAssertFalse(b.isTimed)
    }

    // MARK: ④ 排序：沉底，且彼此不乱

    /// 直接比较 Optional 会把 nil 排到**最前**：刚新增的空行会跳到列首，
    /// 人正在那一行打字，行却动了。必须沉底。
    /// 而且几条空行之间要保持输入顺序——否则连续加两条，它们会互相换位。
    func testUntimedBlocksSinkToTheBottomKeepingTheirOwnOrder() {
        var rec = DayRecord(key: day())
        rec.actual = [blank("空一"), timed(14, "十四点"), blank("空二"), timed(9, "九点")]
        rec.normalize()
        XCTAssertEqual(rec.actual.map(\.title), ["九点", "十四点", "空一", "空二"])
    }

    /// 界面排序和导出排序必须是同一个函数，否则导出的顺序和屏幕上看到的不一样,
    /// 而这种不一致要到打开文件时才发现。
    func testExportOrderMatchesScreenOrder() {
        var rec = DayRecord(key: day())
        rec.actual = [blank("空一"), timed(14, "十四点"), blank("空二"), timed(9, "九点")]
        rec.normalize()
        XCTAssertEqual(ActualBlock.timeOrdered(rec.actual).map(\.title), rec.actual.map(\.title))
    }

    // MARK: ⑤ 导出不吞内容

    /// 时间没填，不等于这条不存在。人已经写了标题，导出必须带上它。
    func testExportKeepsUntimedBlocksWithABlankTimeSlot() {
        var rec = DayRecord(key: day())
        rec.actual = [blank("写周报")]
        let md = MarkdownRenderer.render(record: rec, usage: nil,
                                         settings: AppSettings(), lang: .zh)
        XCTAssertTrue(md.contains("写周报"), "未填时间的条目被导出吞掉了")
        XCTAssertTrue(md.contains(S.timeBlank.text(.zh)), "应留出空格子，而不是编一个时间")
    }

    // MARK: ⑥ 时间带

    /// 没有时刻的块画不到轴上——这不是丢数据（它在「实际」列里看得见），
    /// 所以也**不该**混进「越界记录」提示里，那个提示说的是另一件事：
    /// 有时间、但不落在这一天。
    func testUntimedBlocksAreNeitherProjectedNorReportedOutOfRange() {
        var rec = DayRecord(key: day())
        rec.actual = [blank("写周报"), timed(9, "九点")]
        rec.normalize()
        let proj = DayTimelineProjection.project(record: rec, lang: .zh)
        XCTAssertEqual(proj.actual.count, 1)
        XCTAssertTrue(proj.outOfRange.isEmpty, "未填时间不是「越界」，别把两件事混在一个提示里")
    }

    // MARK: ⑦ 旧文件必须照常读得进来

    /// `start`/`end` 从 `Date` 变成 `Date?` 是一次磁盘结构变更。
    /// 这个项目吃过一次亏：合成的 Codable 遇到缺键会**抛错**，
    /// 于是「读不出来→当空记录→存回去」把一天的内容抹掉。
    /// 所以任何动到落盘结构的改动，都要在这里证明旧文件还读得进来。
    func testRecordsWrittenBeforeTimesBecameOptionalStillDecode() throws {
        struct LegacyActualBlock: Codable {      // 改动前的形状：两端都是非可选
            var id: UUID
            var start: Date
            var end: Date
            var timeZoneIdentifier: String
            var title: String
            var source: BlockSource
        }
        let legacy = LegacyActualBlock(id: UUID(),
                                       start: anchor().addingTimeInterval(9 * 3600),
                                       end: anchor().addingTimeInterval(10 * 3600),
                                       timeZoneIdentifier: perth,
                                       title: "旧记录",
                                       source: .manual)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(ActualBlock.self, from: data)

        XCTAssertEqual(decoded.id, legacy.id)
        XCTAssertEqual(decoded.title, "旧记录")
        XCTAssertEqual(decoded.start, legacy.start)
        XCTAssertEqual(decoded.end, legacy.end)
        XCTAssertEqual(decoded.durationSeconds, 3600, accuracy: 1)
    }

    func testBlankBlockSurvivesARoundTrip() throws {
        let data = try JSONEncoder().encode(blank("写周报"))
        let back = try JSONDecoder().decode(ActualBlock.self, from: data)
        XCTAssertNil(back.start)
        XCTAssertNil(back.end)
        XCTAssertEqual(back.title, "写周报")
    }
}

// MARK: - 输入时的冒号回位

/// 「数字自动填到对应位置」——只开给「实际」列。
/// 计划列的时间是排计划时一次带出来的默认值，不需要这个，也**明确不要动**。
final class TimeMaskTests: XCTestCase {

    func testFourDigitsGetTheColonPlacedForYou() {
        XCTAssertEqual(TimeEntryField.sanitize("1430", autoColon: true), "14:30")
        XCTAssertEqual(TimeEntryField.sanitize("0930", autoColon: true), "09:30")
        XCTAssertEqual(TimeEntryField.sanitize("2400", autoColon: true), "24:00")
    }

    /// 3 个数字是歧义的：`143` 既可能是 `1:43`，也可能是 `14:3` 打了一半。
    /// 这时插冒号，下一个数字就落错格子。留着不动，交给提交时的 parseMinutes。
    func testThreeDigitsAreLeftAloneBecauseTheyAreAmbiguous() {
        XCTAssertEqual(TimeEntryField.sanitize("143", autoColon: true), "143")
        XCTAssertEqual(GongTime.parseMinutes("930"), 9 * 60 + 30)
        XCTAssertEqual(GongTime.parseMinutes("143"), 1 * 60 + 43)
    }

    /// 已经有冒号就不再插——否则退格删掉冒号会被立刻补回来，人永远退不回去。
    func testBackspaceCanActuallyDeleteTheColon() {
        XCTAssertEqual(TimeEntryField.sanitize("14:3", autoColon: true), "14:3")
        XCTAssertEqual(TimeEntryField.sanitize("14:", autoColon: true), "14:")
        XCTAssertEqual(TimeEntryField.sanitize("14", autoColon: true), "14")
    }

    /// `controlTextDidChange` 里回写会再触发一次通知。不幂等就是无限循环。
    func testAutoColonIsIdempotent() {
        for raw in ["1430", "143", "14:30", "9：30", "abc", "140000", "", "24:00"] {
            let once = TimeEntryField.sanitize(raw, autoColon: true)
            XCTAssertEqual(TimeEntryField.sanitize(once, autoColon: true), once,
                           "sanitize(\(raw)) 不幂等")
        }
    }

    /// 用户明确说了计划那一列不要改。锁住它的逐字行为。
    func testPlannedColumnTypingIsByteForByteUnchanged() {
        XCTAssertEqual(TimeEntryField.sanitize("1430"), "1430")
        XCTAssertEqual(TimeEntryField.sanitize("143"), "143")
        XCTAssertEqual(TimeEntryField.sanitize("14ab00"), "1400")
        XCTAssertEqual(TimeEntryField.sanitize("9：30"), "9:30")
        XCTAssertEqual(TimeEntryField.sanitize("140000"), "14000")
    }
}
