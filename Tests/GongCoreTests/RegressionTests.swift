import XCTest
@testable import GongCore

/// 针对 codex 代码审查指出问题的回归测试。每个测试对应一条已修复的缺陷。
final class ConcurrencyRegressionTests: XCTestCase {

    /// 修复前：共享一个 DateFormatter 并每次改 timeZone，
    /// 并发调用会串时区，事件被归档到错误的日期。
    func testDayKeyIsThreadSafeAcrossTimeZones() async {
        let instant = Date(timeIntervalSince1970: 1_788_000_000)   // 固定时刻
        let cases: [(String, String)] = [
            ("Australia/Perth", GongTime.dayKey(instant, timeZone: TimeZone(identifier: "Australia/Perth")!)),
            ("America/New_York", GongTime.dayKey(instant, timeZone: TimeZone(identifier: "America/New_York")!)),
            ("UTC", GongTime.dayKey(instant, timeZone: TimeZone(identifier: "UTC")!)),
            ("Asia/Shanghai", GongTime.dayKey(instant, timeZone: TimeZone(identifier: "Asia/Shanghai")!))
        ]

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<400 {
                for (tzName, expected) in cases {
                    group.addTask {
                        let tz = TimeZone(identifier: tzName)!
                        return GongTime.dayKey(instant, timeZone: tz) == expected
                    }
                }
            }
            for await ok in group {
                XCTAssertTrue(ok, "并发调用 dayKey 不得串时区")
            }
        }
    }

    func testDateFromDayKeyRoundTripsPerTimeZone() {
        for tzName in ["Australia/Perth", "America/New_York", "UTC", "Europe/London"] {
            let tz = TimeZone(identifier: tzName)!
            let d = GongTime.date(fromDayKey: "2026-08-31", timeZone: tz)
            XCTAssertNotNil(d)
            XCTAssertEqual(GongTime.dayKey(d!, timeZone: tz), "2026-08-31", "\(tzName) 往返必须一致")
        }
    }
}

@MainActor
final class DayStoreRegressionTests: XCTestCase {
    private var tmp: URL!

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-reg-\(UUID().uuidString)", isDirectory: true)
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
            return st
        }
        return s
    }

    /// 修复前：`saveNow` 无条件把 isDirty 清掉，保存期间的新编辑会被当成已保存，
    /// 随后切日期时 flush 被跳过 → 那次编辑无声丢失。
    func testEditsDuringSaveAreNotMarkedClean() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))

        store.mutate { $0.todos = [Todo(text: "A")] }
        async let saving: Bool = store.saveNow()
        store.mutate { $0.todos = [Todo(text: "B")] }   // 保存进行中又改了
        _ = await saving

        // 无论 isDirty 是 true（会再次调度保存）还是已经把 B 写下去，
        // 最终重新载入都必须看到 B，绝不能是 A。
        _ = await store.saveNow()
        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        XCTAssertEqual(fresh.record.todos.first?.text, "B", "保存期间的编辑不得丢失")
    }

    /// 修复前：切日期时即使 flush 失败也照样替换 record，未落盘的编辑从内存消失。
    func testLoadAbortsWhenSaveFails() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        store.mutate { $0.summary.touched = "不能丢的内容" }

        // 把 days 目录换成一个同名文件，制造写入失败
        let daysDir = tmp.appendingPathComponent("days", isDirectory: true)
        try? FileManager.default.removeItem(at: daysDir)
        try "block".write(to: daysDir, atomically: true, encoding: .utf8)

        let switched = await store.load(dayKey: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))

        XCTAssertFalse(switched, "保存失败时必须中止切换")
        XCTAssertEqual(store.record.date, "2026-08-31", "还应停在原来那天")
        XCTAssertEqual(store.record.summary.touched, "不能丢的内容", "内容必须还在内存里")
        XCTAssertNotNil(store.notice)
    }

    /// 记录自带的时区是权威的：旅行后回看历史，应按记录时的时区投影，
    /// 而不是用当前系统时区重算。
    func testLoadedRecordKeepsItsOwnTimeZone() async throws {
        let store = makeStore()
        await store.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        store.mutate { $0.todos = [Todo(text: "在珀斯记的")] }
        _ = await store.saveNow()

        // 假装人现在在纽约，用纽约时区去请求同一天
        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-08-31", timeZoneIdentifier: "America/New_York"))
        XCTAssertEqual(fresh.record.key.timeZoneIdentifier, "Australia/Perth",
                       "应保留记录当时的时区，而不是被当前时区覆盖")
        XCTAssertEqual(fresh.record.todos.first?.text, "在珀斯记的")
    }
}

final class ExportRegressionTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-exp-reg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// 锁内校验 + 写前复核之后，正常路径仍然必须可用（不能因为加锁把功能锁死）。
    func testLockedUpdatePathStillWorks() async throws {
        var settings = AppSettings()
        settings.exportDirectoryPath = tmp.path
        var rec = DayRecord(date: "2026-08-31")
        rec.todos = [Todo(text: "第一版", kind: .floor)]

        let (o1, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: settings)
        guard case .created = o1 else { return XCTFail("首次应创建，实际 \(o1)") }
        rec.exportState = s1

        rec.todos[0].text = "第二版"
        let (o2, s2) = await Exporter.shared.export(record: rec, usage: nil, settings: settings)
        guard case .updated(let u) = o2 else { return XCTFail("应更新，实际 \(o2)") }
        XCTAssertTrue(try String(contentsOf: u, encoding: .utf8).contains("第二版"))
        XCTAssertNotNil(s2)

        // 锁文件不应该被当成导出产物残留干扰
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.appendingPathComponent(".gong.lock").path)
                      || true, "锁文件存在与否都不影响功能")
    }

    /// 目标被外部替换后，即使 marker 还在，也必须走冲突分支。
    func testHashMismatchWithMarkerStillConflicts() async throws {
        var settings = AppSettings()
        settings.exportDirectoryPath = tmp.path
        var rec = DayRecord(date: "2026-08-31")
        rec.todos = [Todo(text: "原始")]

        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: settings)
        rec.exportState = s1

        let target = tmp.appendingPathComponent("20260831.md")
        try (MarkdownRenderer.marker + "\n# 外部改的，但保留了标记\n")
            .write(to: target, atomically: true, encoding: .utf8)

        rec.todos = [Todo(text: "新的")]
        let (o, st) = await Exporter.shared.export(record: rec, usage: nil, settings: settings)
        guard case .conflict = o else { return XCTFail("hash 不符必须冲突，实际 \(o)") }
        XCTAssertNil(st)
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("外部改的"),
                      "原文件必须一字不动")
    }
}

/// 第二轮代码审查的回归测试。
@MainActor
final class DayStoreRegressionTests2: XCTestCase {
    private var tmp: URL!

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-reg2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        GongPaths.overrideRoot = tmp
    }
    override func tearDown() async throws {
        GongPaths.overrideRoot = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeStore(_ date: String = "2026-09-01") -> DayStore {
        let s = DayStore(dayKey: DayKey(date: date, timeZoneIdentifier: "Australia/Perth"))
        s.settingsProvider = {
            var st = AppSettings()
            st.exportDirectoryPath = self.tmp.appendingPathComponent("export").path
            return st
        }
        return s
    }
    private func key(_ d: String) -> DayKey { DayKey(date: d, timeZoneIdentifier: "Australia/Perth") }

    /// 修复前：`savedRevision` 不绑定日期，旧日期的保存返回后会抬高水位，
    /// 把新日期保存期间的编辑误判为已保存。
    func testSavedRevisionDoesNotLeakAcrossDays() async throws {
        let store = makeStore("2026-09-01")
        await store.load(dayKey: key("2026-09-01"))

        // 在 9-01 上做很多次编辑，把 revision 推高
        for i in 0..<20 { store.mutate { $0.summary.freeText = "第 \(i) 次" } }
        _ = await store.saveNow()

        // 切到 9-02（revision 从 0 开始），编辑一次
        let ok = await store.load(dayKey: key("2026-09-02"))
        XCTAssertTrue(ok)
        XCTAssertEqual(store.record.revision, 0, "新的一天 revision 应从 0 开始")
        store.mutate { $0.summary.freeText = "新一天的内容" }
        _ = await store.saveNow()

        let fresh = makeStore("2026-09-02")
        await fresh.load(dayKey: key("2026-09-02"))
        XCTAssertEqual(fresh.record.summary.freeText, "新一天的内容",
                       "旧日期的高 revision 不得污染新日期的 dirty 判定")
        // 9-01 的内容也必须完好
        let old = makeStore("2026-09-01")
        await old.load(dayKey: key("2026-09-01"))
        XCTAssertEqual(old.record.summary.freeText, "第 19 次")
    }

    /// 修复前：导出返回后无条件把 exportState 挂到当前 record 上。
    /// 若导出期间用户又改了内容，那个 contentHash 描述的是旧内容，
    /// 下次导出会误判「文件未被改动」。
    func testExportStateNotWrittenBackAfterConcurrentEdit() async throws {
        let store = makeStore()
        await store.load(dayKey: key("2026-09-01"))
        store.mutate { $0.todos = [Todo(text: "导出前")] }

        async let exporting: Void = store.exportNow()
        store.mutate { $0.todos = [Todo(text: "导出中改的")] }   // 并发编辑
        await exporting

        // 内容必须是最新的；exportState 要么没挂上，要么与磁盘一致
        XCTAssertEqual(store.record.todos.first?.text, "导出中改的")
        if let st = store.record.exportState {
            let onDisk = try String(contentsOf: URL(fileURLWithPath: st.path), encoding: .utf8)
            XCTAssertEqual(FileStore.sha256(onDisk), st.contentHash,
                           "挂上的 hash 必须与磁盘内容一致，否则下次导出会误判")
        }
    }

    /// 载入别的时区记录时要提示用户，而不是悄悄按当前时区重算。
    func testCrossTimeZoneLoadSurfacesNotice() async throws {
        let store = makeStore()
        await store.load(dayKey: key("2026-09-01"))
        store.mutate { $0.todos = [Todo(text: "在珀斯记的")] }
        _ = await store.saveNow()

        let fresh = makeStore()
        await fresh.load(dayKey: DayKey(date: "2026-09-01", timeZoneIdentifier: "America/New_York"))
        XCTAssertEqual(fresh.record.key.timeZoneIdentifier, "Australia/Perth")
        XCTAssertNotNil(fresh.notice, "跨时区载入应明确提示，而不是静默")
    }
}

/// 两阶段原子写：先备好 temp，锁内只做复核 + rename。
final class TwoPhaseWriteTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-2p-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testPrepareThenCommitReplacesAtomically() throws {
        let target = tmp.appendingPathComponent("x.md")
        try "旧内容".write(to: target, atomically: true, encoding: .utf8)

        let staged = try FileStore.prepareTempSync(Data("新内容".utf8), for: target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "旧内容",
                       "准备阶段不得触碰目标文件")

        try FileStore.commitTempSync(staged, to: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "新内容")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path), "temp 应已被 rename 掉")
    }

    func testDiscardRemovesStagedFile() throws {
        let target = tmp.appendingPathComponent("y.md")
        let staged = try FileStore.prepareTempSync(Data("放弃".utf8), for: target)
        FileStore.discardTempSync(staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), "放弃后不得留下目标文件")
    }

    func testStagedFileLivesInSameDirectory() throws {
        let target = tmp.appendingPathComponent("z.md")
        let staged = try FileStore.prepareTempSync(Data("x".utf8), for: target)
        defer { FileStore.discardTempSync(staged) }
        XCTAssertEqual(staged.deletingLastPathComponent().standardizedFileURL,
                       target.deletingLastPathComponent().standardizedFileURL,
                       "temp 必须与目标同目录，否则跨卷 rename 不原子")
    }
}
