import XCTest
@testable import GongCore

/// 补录场景：开会 / 外出调研回来后往回补条目，补完必须自动按时间排好，
/// 而不是留在列表末尾等着人工整理。
@MainActor
final class BlockSortingTests: XCTestCase {

    private var tmp: URL!
    private let tz = "Australia/Perth"

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-sort-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        GongPaths.overrideRoot = tmp
    }
    override func tearDown() async throws {
        GongPaths.overrideRoot = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore() -> DayStore {
        let s = DayStore(dayKey: DayKey(date: "2026-09-02", timeZoneIdentifier: tz))
        s.settingsProvider = { AppSettings() }
        return s
    }

    private func perth(_ h: Int, _ m: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 2; c.hour = h; c.minute = m
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: tz)!
        return cal.date(from: c)!
    }

    /// 补一条早上的计划，它必须排到已有的下午那条前面。
    func testBackfilledPlanSortsIntoPlace() {
        let store = makeStore()
        store.mutate { $0.planned = [PlannedBlock(start: 14 * 60, end: 15 * 60, title: "下午的会")] }
        store.mutate { $0.planned.append(PlannedBlock(start: 9 * 60, end: 10 * 60, title: "早上补的")) }

        XCTAssertEqual(store.record.planned.map(\.title), ["早上补的", "下午的会"],
                       "补录的条目应自动排到正确位置")
    }

    /// 实际列同理。
    func testBackfilledActualSortsIntoPlace() {
        let store = makeStore()
        store.mutate {
            $0.actual = [ActualBlock(start: perth(16, 0), end: perth(17, 0),
                                     timeZoneIdentifier: tz, title: "回来后先记的", source: .manual)]
        }
        store.mutate {
            $0.actual.append(ActualBlock(start: perth(10, 0), end: perth(12, 0),
                                         timeZoneIdentifier: tz, title: "上午外出调研", source: .manual))
        }
        XCTAssertEqual(store.record.actual.map(\.title), ["上午外出调研", "回来后先记的"])
    }

    /// **改时间之后**也要立刻重排——这是补录最常见的动作：
    /// 先「＋新增」拿到一条默认的当前时刻，再把时间改成实际发生的时间。
    func testEditingTimeResortsImmediately() {
        let store = makeStore()
        store.mutate {
            $0.planned = [
                PlannedBlock(start: 9 * 60, end: 10 * 60, title: "A"),
                PlannedBlock(start: 11 * 60, end: 12 * 60, title: "B")
            ]
        }
        // 把 B 改到 A 前面
        let bID = store.record.planned.first { $0.title == "B" }!.id
        store.mutate { rec in
            if let i = rec.planned.firstIndex(where: { $0.id == bID }) {
                rec.planned[i].setRange(start: 7 * 60, end: 8 * 60)
            }
        }
        XCTAssertEqual(store.record.planned.map(\.title), ["B", "A"], "改完时间应立刻重排")
    }

    func testEditingActualTimeResortsImmediately() {
        let store = makeStore()
        store.mutate {
            $0.actual = [
                ActualBlock(start: perth(9, 0), end: perth(10, 0),
                            timeZoneIdentifier: tz, title: "A", source: .manual),
                ActualBlock(start: perth(11, 0), end: perth(12, 0),
                            timeZoneIdentifier: tz, title: "B", source: .manual)
            ]
        }
        let bID = store.record.actual.first { $0.title == "B" }!.id
        store.mutate { rec in
            if let i = rec.actual.firstIndex(where: { $0.id == bID }) {
                rec.actual[i].setStartWallClock(7 * 60)
                rec.actual[i].setEndWallClock(8 * 60)
            }
        }
        XCTAssertEqual(store.record.actual.map(\.title), ["B", "A"])
    }

    /// 「从监控填充」一次灌进来多条，也要排好。
    func testMonitorFillIsSorted() {
        let store = makeStore()
        store.mutate { rec in
            for (h, name) in [(16, "Chrome"), (9, "Xcode"), (13, "Terminal")] {
                rec.actual.append(ActualBlock(start: perth(h, 0), end: perth(h + 1, 0),
                                              timeZoneIdentifier: tz, title: name, source: .monitor))
            }
        }
        XCTAssertEqual(store.record.actual.map(\.title), ["Xcode", "Terminal", "Chrome"])
    }

    /// 排序在存盘往返之后依然成立。
    func testSortSurvivesRoundTrip() async {
        let store = makeStore()
        store.mutate {
            $0.planned = [PlannedBlock(start: 15 * 60, end: 16 * 60, title: "晚"),
                          PlannedBlock(start: 8 * 60, end: 9 * 60, title: "早")]
        }
        _ = await store.saveNow()
        _ = await store.load(dayKey: DayKey(date: "2026-09-01", timeZoneIdentifier: tz))
        _ = await store.load(dayKey: DayKey(date: "2026-09-02", timeZoneIdentifier: tz))
        XCTAssertEqual(store.record.planned.map(\.title), ["早", "晚"])
    }
}
