import XCTest
@testable import GongCore

/// 日期导航（`<` / `>` / `今天`）。
///
/// 用户报：主窗口里日期动不了。需求很明确——
/// 昨天的计划要今早补总结，看到未来的会议要跳过去先记一笔。
/// 所以「往回翻、往前翻、跳回今天」三条路必须都通，而且**有未保存内容时也要通**。
@MainActor
final class DayNavigationTests: XCTestCase {

    private var tmp: URL!
    private let tz = "Australia/Perth"

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-nav-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        GongPaths.overrideRoot = tmp
    }
    override func tearDown() async throws {
        GongPaths.overrideRoot = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore(_ date: String) -> DayStore {
        let s = DayStore(dayKey: DayKey(date: date, timeZoneIdentifier: tz))
        s.settingsProvider = { AppSettings() }
        return s
    }

    /// `GongTableView.shiftDay` 的日期算术，抽出来单独锁住。
    private func shifted(_ key: DayKey, _ delta: Int) -> DayKey? {
        guard let d = GongTime.date(fromDayKey: key.date, timeZone: key.timeZone),
              let next = key.calendar.date(byAdding: .day, value: delta, to: d) else { return nil }
        return DayKey(next, timeZone: key.timeZone)
    }

    func testDateArithmeticMovesOneDay() {
        let key = DayKey(date: "2026-09-02", timeZoneIdentifier: tz)
        XCTAssertEqual(shifted(key, -1)?.date, "2026-09-01")
        XCTAssertEqual(shifted(key, 1)?.date, "2026-09-03")
    }

    /// 跨月、跨年也要对。
    func testDateArithmeticCrossesBoundaries() {
        XCTAssertEqual(shifted(DayKey(date: "2026-09-01", timeZoneIdentifier: tz), -1)?.date, "2026-08-31")
        XCTAssertEqual(shifted(DayKey(date: "2026-12-31", timeZoneIdentifier: tz), 1)?.date, "2027-01-01")
        XCTAssertEqual(shifted(DayKey(date: "2027-01-01", timeZoneIdentifier: tz), -1)?.date, "2026-12-31")
    }

    /// 干净状态下往回翻。
    func testLoadPreviousDayFromCleanState() async {
        let store = makeStore("2026-09-02")
        let ok = await store.load(dayKey: shifted(store.record.key, -1)!)
        XCTAssertTrue(ok, "干净状态下切日期不该失败")
        XCTAssertEqual(store.record.date, "2026-09-01")
    }

    /// 往前翻到未来那一天（看到会议安排先记一笔）。
    func testLoadFutureDay() async {
        let store = makeStore("2026-09-02")
        let ok = await store.load(dayKey: shifted(store.record.key, 5)!)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.record.date, "2026-09-07")
    }

    /// **关键路径**：当天有未保存的编辑时切日期。
    /// `load()` 会先 saveNow()，只有仍然 dirty 才中止。正常情况下必须切成功。
    func testSwitchingDayWithUnsavedEditsStillWorks() async {
        let store = makeStore("2026-09-02")
        store.mutate { $0.todos.append(Todo(text: "今天写的东西", order: 0)) }
        XCTAssertTrue(store.isDirty, "刚编辑完应该是 dirty")

        let ok = await store.load(dayKey: shifted(store.record.key, -1)!)
        XCTAssertTrue(ok, "有未保存内容时切日期被拒绝了：\(store.notice?.text ?? "无提示")")
        XCTAssertEqual(store.record.date, "2026-09-01")
        XCTAssertTrue(store.record.todos.isEmpty, "昨天应该是空的")
    }

    /// 昨天写的东西，今天翻回去还在（补总结的场景）。
    func testYesterdayEditsSurviveRoundTrip() async {
        let store = makeStore("2026-09-02")
        _ = await store.load(dayKey: DayKey(date: "2026-09-01", timeZoneIdentifier: tz))
        store.mutate { $0.summary.touched = "昨天卡在时区那段" }
        _ = await store.saveNow()

        _ = await store.load(dayKey: DayKey(date: "2026-09-02", timeZoneIdentifier: tz))
        XCTAssertEqual(store.record.summary.touched, "")

        _ = await store.load(dayKey: DayKey(date: "2026-09-01", timeZoneIdentifier: tz))
        XCTAssertEqual(store.record.summary.touched, "昨天卡在时区那段", "翻回昨天内容丢了")
    }

    /// 连续翻多天不出错，且每天各自独立。
    func testRepeatedNavigationKeepsDaysSeparate() async {
        let store = makeStore("2026-09-02")
        for (offset, text) in [(-2, "前天"), (-1, "昨天"), (0, "今天")] {
            let key = DayKey(date: ["-2": "2026-08-31", "-1": "2026-09-01", "0": "2026-09-02"]["\(offset)"]!,
                             timeZoneIdentifier: tz)
            _ = await store.load(dayKey: key)
            store.mutate { $0.summary.touched = text }
            _ = await store.saveNow()
        }
        for (date, text) in [("2026-08-31", "前天"), ("2026-09-01", "昨天"), ("2026-09-02", "今天")] {
            _ = await store.load(dayKey: DayKey(date: date, timeZoneIdentifier: tz))
            XCTAssertEqual(store.record.summary.touched, text, "\(date) 的内容串了")
        }
    }
}
