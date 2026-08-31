import XCTest
@testable import GongCore

/// DayStore 的端到端路径：编辑 → 防抖保存 → 重新载入 → 导出。
/// 重点验证「快速连续编辑不会用过期快照覆盖新数据」。
@MainActor
final class DayStoreIntegrationTests: XCTestCase {

    private var tmp: URL!

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        GongPaths.overrideRoot = tmp
    }

    override func tearDown() async throws {
        GongPaths.overrideRoot = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore() -> DayStore {
        let s = DayStore(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        s.settingsProvider = {
            var st = AppSettings()
            st.exportDirectoryPath = self.tmp.appendingPathComponent("export").path
            st.autoExport = false
            return st
        }
        return s
    }

    func testEditThenSaveThenReload() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))

        store.mutate { $0.todos = [Todo(text: "跑通图表", kind: .floor)] }
        await store.saveNow()

        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertEqual(fresh.record.todos.first?.text, "跑通图表")
        XCTAssertEqual(fresh.record.todos.first?.kind, .floor)
    }

    /// 连续快速编辑 —— 最后一次的内容必须完整落盘，不能被中途的旧快照盖回去。
    func testRapidEditsPersistLatestValue() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))

        store.mutate { $0.todos = [Todo(text: "a")] }
        for ch in ["ab", "abc", "abcd", "abcde"] {
            store.mutate { rec in rec.todos[0].text = ch }
        }
        await store.saveNow()

        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertEqual(fresh.record.todos.first?.text, "abcde", "必须落到最后一次的值")
        XCTAssertGreaterThanOrEqual(fresh.record.revision, 5, "每次 mutate 都应递增 revision")
    }

    /// exportNow 会写回 exportState 并再次落盘；它不得丢掉此前的编辑。
    func testExportDoesNotClobberConcurrentEdits() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        store.mutate { $0.todos = [Todo(text: "第一条")] }
        await store.saveNow()

        store.mutate { $0.summary.touched = "今天最触动我的事" }
        await store.exportNow()

        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertEqual(fresh.record.todos.first?.text, "第一条")
        XCTAssertEqual(fresh.record.summary.touched, "今天最触动我的事",
                       "导出写回 exportState 时不得丢掉刚才的编辑")
        XCTAssertNotNil(fresh.record.exportState, "exportState 必须一起持久化")
    }

    /// 退出路径的同步落盘（不能 await，否则主线程死锁）。
    func testSynchronousTerminationSave() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        store.mutate { $0.summary.freeText = "退出前写的" }

        store.saveSynchronouslyForTermination()      // 完全同步，无 await

        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertEqual(fresh.record.summary.freeText, "退出前写的",
                       "退出时的同步落盘必须真的写进去")
    }

    func testLoadingMissingDayGivesEmptyRecordNotCrash() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2019-01-01", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertTrue(store.record.todos.isEmpty)
        XCTAssertEqual(store.record.date, "2019-01-01")
    }

    func testCorruptedDayFileDoesNotCrash() async throws {
        let dir = tmp.appendingPathComponent("days", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ this is not json".write(to: dir.appendingPathComponent("2026-08-31.json"),
                                      atomically: true, encoding: .utf8)
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertTrue(store.record.todos.isEmpty, "损坏文件应降级为空记录并给出提示，而不是崩溃")
        XCTAssertNotNil(store.notice)
    }
}
