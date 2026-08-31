import XCTest
@testable import GongCore

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!
}

final class UsageReducerTests: XCTestCase {

    /// Perth = UTC+8，无 DST，便于手算。
    private let perth = "Australia/Perth"
    private var key: DayKey { DayKey(date: "2026-09-01", timeZoneIdentifier: perth) }

    private var seq = 0
    private func ev(_ e: UsageEvent.Kind, _ t: Date, _ bid: String? = nil, _ name: String? = nil,
                    run: String = "run-1") -> UsageEvent {
        seq += 1
        return UsageEvent(t: t, e: e, runId: run, seq: seq, tz: perth, bundleId: bid, name: name)
    }

    override func setUp() { seq = 0 }

    /// 2026-09-01 00:00 Perth(UTC+8) == 2026-08-31 16:00 UTC
    private var dayStartUTC: Date { utc(2026, 8, 31, 16, 0) }
    /// 目标日的本地时刻。用「当日起点 + 偏移」构造，避免手算时区跨日出错。
    private func local(_ h: Int, _ mi: Int) -> Date {
        dayStartUTC.addingTimeInterval(TimeInterval(h * 3600 + mi * 60))
    }

    func testBasicSwitching() {
        let events = [
            ev(.appStart, local(9, 0)),
            ev(.activate, local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, local(10, 0), "com.google.Chrome", "Google Chrome"),
            ev(.appStop,  local(10, 30))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertEqual(day.intervals.count, 2)
        XCTAssertEqual(day.intervals[0].appName, "Xcode")
        XCTAssertEqual(day.intervals[0].seconds, 3600, accuracy: 1)
        XCTAssertEqual(day.intervals[1].appName, "Google Chrome")
        XCTAssertEqual(day.intervals[1].seconds, 1800, accuracy: 1)
        XCTAssertFalse(day.truncated)
    }

    func testIsIdempotent() {
        let events = [
            ev(.activate, local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, local(11, 0), "com.google.Chrome", "Chrome"),
            ev(.appStop,  local(12, 0))
        ]
        let a = UsageReducer.reduce(events: events, for: key)
        let b = UsageReducer.reduce(events: events.reversed(), for: key)   // 输入顺序不同
        XCTAssertEqual(a, b, "同样的事件必须产生完全相同的结果，与输入顺序无关")
        XCTAssertEqual(a.intervals.map(\.id), b.intervals.map(\.id))
    }

    func testIdleClosesIntervalAtBacktrackedTimestamp() {
        let events = [
            ev(.activate,  local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.heartbeat, local(9, 1)),
            ev(.heartbeat, local(9, 2)),
            // 09:03 才发现空闲，时间戳回溯到 09:00（空闲已 180s）
            ev(.idleStart, local(9, 0), nil, nil),
            ev(.idleEnd,   local(9, 30)),
            ev(.activate,  local(9, 30), "com.apple.dt.Xcode", "Xcode"),
            ev(.appStop,   local(10, 0))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        let total = day.intervals.reduce(0.0) { $0 + $1.seconds }
        XCTAssertEqual(total, 1800, accuracy: 60, "空闲的 30 分钟不得计入")
    }

    func testCrashTruncatesAtLastHeartbeat() {
        let events = [
            ev(.activate,  local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.heartbeat, local(9, 30)),
            ev(.heartbeat, local(10, 0))
            // 没有 appStop —— 进程被强杀
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertTrue(day.truncated, "崩溃场景必须标记数据不完整")
        XCTAssertEqual(day.intervals.count, 1)
        XCTAssertEqual(day.intervals[0].seconds, 3600, accuracy: 1, "只认到最后一条心跳，不凭空外推")
    }

    func testLiveNowClosesOpenInterval() {
        let events = [ev(.activate, local(9, 0), "com.apple.dt.Xcode", "Xcode")]
        let day = UsageReducer.reduce(events: events, for: key, liveNow: local(9, 45))
        XCTAssertFalse(day.truncated)
        XCTAssertEqual(day.intervals.first?.seconds ?? 0, 2700, accuracy: 1)
    }

    func testCrossMidnightSplitsCorrectly() {
        // 8-31 23:50 本地激活 Xcode，9-01 00:20 本地切走
        let start = utc(2026, 8, 31, 15, 50)   // 8-31 23:50 Perth
        let end   = utc(2026, 8, 31, 16, 20)   // 9-01 00:20 Perth
        let events = [
            ev(.activate, start, "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, end,   "com.google.Chrome", "Chrome"),
            ev(.appStop,  end.addingTimeInterval(600))
        ]
        let d0 = UsageReducer.reduce(events: events, for: DayKey(date: "2026-08-31", timeZoneIdentifier: perth))
        let d1 = UsageReducer.reduce(events: events, for: DayKey(date: "2026-09-01", timeZoneIdentifier: perth))

        XCTAssertEqual(d0.intervals.first { $0.appName == "Xcode" }?.seconds ?? 0, 600, accuracy: 1,
                       "8-31 只应记到 23:50–24:00 的 10 分钟")
        XCTAssertEqual(d1.intervals.first { $0.appName == "Xcode" }?.seconds ?? 0, 1200, accuracy: 1,
                       "9-01 应记到 00:00–00:20 的 20 分钟")
        // 总量守恒
        XCTAssertEqual(600 + 1200, 1800)
    }

    func testRequiredDayKeysCoversNeighbours() {
        let keys = UsageReducer.requiredDayKeys(for: key)
        XCTAssertEqual(keys, ["2026-08-31", "2026-09-01", "2026-09-02"],
                       "必须读前后各一天，否则跨零点区间会丢")
    }

    func testFiltersGongItself() {
        let events = [
            ev(.activate, local(9, 0), GongPaths.bundleIdentifier, "Gong"),
            ev(.activate, local(9, 30), "com.apple.dt.Xcode", "Xcode"),
            ev(.appStop,  local(10, 0))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertFalse(day.intervals.contains { $0.bundleId == GongPaths.bundleIdentifier },
                       "Gong 自己不得计入统计")
        XCTAssertEqual(day.intervals.count, 1)
    }

    func testCategoryTotals() {
        var s = AppSettings()
        s.categories["com.google.Chrome"] = .other      // 用户自定义覆盖
        var day = UsageDay(date: "2026-09-01")
        day.intervals = [
            UsageInterval(bundleId: "com.apple.dt.Xcode", appName: "Xcode",
                          start: local(9, 0), end: local(11, 0)),
            UsageInterval(bundleId: "com.google.Chrome", appName: "Chrome",
                          start: local(11, 0), end: local(12, 0))
        ]
        let totals = UsageReducer.categoryTotals(day, settings: s)
        XCTAssertEqual(totals[.focus] ?? 0, 7200, accuracy: 1)
        XCTAssertEqual(totals[.other] ?? 0, 3600, accuracy: 1, "用户覆盖的分类要生效")
    }
}

/// 状态机边界：这些是最容易出现「重复计时」或「漏计」的路径。
final class UsageReducerStateMachineTests: XCTestCase {
    private let perth = "Australia/Perth"
    private var key: DayKey { DayKey(date: "2026-09-01", timeZoneIdentifier: perth) }
    private var seq = 0
    override func setUp() { seq = 0 }

    private func ev(_ e: UsageEvent.Kind, _ t: Date, _ bid: String? = nil, _ name: String? = nil) -> UsageEvent {
        seq += 1
        return UsageEvent(t: t, e: e, runId: "run-1", seq: seq, tz: perth, bundleId: bid, name: name)
    }
    private var dayStartUTC: Date { utc(2026, 8, 31, 16, 0) }
    private func local(_ h: Int, _ mi: Int) -> Date {
        dayStartUTC.addingTimeInterval(TimeInterval(h * 3600 + mi * 60))
    }
    private func total(_ d: UsageDay) -> TimeInterval { d.intervals.reduce(0) { $0 + $1.seconds } }

    func testWakeThenActivateDoesNotDoubleCount() {
        let events = [
            ev(.activate, local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.sleep,    local(9, 30)),
            ev(.wake,     local(10, 0)),
            ev(.activate, local(10, 0), "com.apple.dt.Xcode", "Xcode"),   // 唤醒后补发采样
            ev(.appStop,  local(10, 30))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertEqual(total(day), 3600, accuracy: 2,
                       "9:00–9:30 与 10:00–10:30 共 60 分钟；睡眠期间不得计入，唤醒也不得重复开段")
    }

    func testActivateWhileSuspendedResumesCorrectly() {
        // 空闲中直接切换应用，没有显式 idleEnd
        let events = [
            ev(.activate,  local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.idleStart, local(9, 10)),
            ev(.activate,  local(9, 40), "com.google.Chrome", "Chrome"),
            ev(.appStop,   local(10, 0))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertEqual(total(day), 600 + 1200, accuracy: 2,
                       "Xcode 10 分钟 + Chrome 20 分钟，空闲的 30 分钟不计")
        XCTAssertEqual(day.intervals.count, 2)
    }

    func testSleepWithoutWakeIsNotCounted() {
        let events = [
            ev(.activate, local(9, 0), "com.apple.dt.Xcode", "Xcode"),
            ev(.sleep,    local(9, 20))
            // 之后一直没醒
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertEqual(total(day), 1200, accuracy: 2, "睡眠之后不得继续累计")
        XCTAssertFalse(day.truncated, "已被 sleep 正常闭合，不算截断")
    }

    func testRepeatedSameAppActivatePreservesTotal() {
        let events = [
            ev(.activate, local(9, 0),  "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, local(9, 20), "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, local(9, 40), "com.apple.dt.Xcode", "Xcode"),
            ev(.appStop,  local(10, 0))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertEqual(total(day), 3600, accuracy: 2, "重复 activate 不得丢失或重复总时长")
    }

    func testSystemTransientAppsAreFiltered() {
        let events = [
            ev(.activate, local(9, 0),  "com.apple.loginwindow", "loginwindow"),
            ev(.activate, local(9, 5),  "com.apple.dt.Xcode", "Xcode"),
            ev(.activate, local(9, 6),  "com.apple.controlcenter", "Control Center"),
            ev(.activate, local(9, 7),  "com.apple.dt.Xcode", "Xcode"),
            ev(.appStop,  local(9, 30))
        ]
        let day = UsageReducer.reduce(events: events, for: key)
        XCTAssertTrue(day.intervals.allSatisfy { !GongPaths.isIgnored($0.bundleId) },
                      "系统瞬时进程不得进入统计")
        XCTAssertEqual(total(day), 60 + 1380, accuracy: 2, "只应统计 Xcode 的两段")
    }

    func testEmptyEventsProduceEmptyDay() {
        let day = UsageReducer.reduce(events: [], for: key)
        XCTAssertTrue(day.intervals.isEmpty)
        XCTAssertFalse(day.truncated)
    }
}
