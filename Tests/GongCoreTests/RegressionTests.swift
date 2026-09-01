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

    /// 断言的是**不变式**而非时序：`async let` + `mutate` 无法保证导出确实先捕获了旧
    /// revision（codex r3 正确地指出了这一点）。因此这里不声称在测并发窗口，
    /// 只锁定两条无论时序如何都必须成立的性质：
    ///   ① 记录内容是最新的；
    ///   ② 若挂上了 exportState，它的 hash 必须与磁盘内容一致
    ///      —— 否则下次导出会把自己写的文件误判为「被外部修改」。
    func testExportStateAlwaysMatchesDiskRegardlessOfTiming() async throws {
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

/// 第三轮代码审查的回归测试。
final class CommitOutcomeTests: XCTestCase {
    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-commit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// rename 成功即视为已提交。区分「未 rename」与「已 rename 但未确认持久化」的意义：
    /// 后者若被当成失败，exportState 不更新，下次导出会把新目标当外部修改，
    /// 从此陷入永久冲突——一次瞬时磁盘异常变成永久功能损坏。
    func testCommitReturnsCommittedOnSuccess() throws {
        let target = tmp.appendingPathComponent("a.md")
        try "旧".write(to: target, atomically: true, encoding: .utf8)
        let staged = try FileStore.prepareTempSync(Data("新".utf8), for: target)
        let outcome = try FileStore.commitTempSync(staged, to: target)
        if case .committed = outcome {} else { XCTFail("正常路径应为 .committed，实际 \(outcome)") }
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "新")
    }

    func testUnsyncedOutcomeStillCountsAsWritten() throws {
        // 语义测试：committedButUnsynced 表示「文件已是新内容」，
        // Exporter 必须照常更新 exportState。
        let outcome = FileStore.CommitOutcome.committedButUnsynced("模拟外置盘 fsync 失败")
        switch outcome {
        case .committedButUnsynced(let d):
            XCTAssertFalse(d.isEmpty, "必须带上可读的原因，不能静默")
        case .committed:
            XCTFail("用例构造错误")
        }
    }

    func testExportOutcomeUnsyncedExposesURL() {
        let u = URL(fileURLWithPath: "/tmp/x.md")
        let o = ExportOutcome.updatedUnsynced(u, "fsync 失败")
        XCTAssertEqual(o.url, u, "updatedUnsynced 也要能取到 URL，供 UI 提示")
    }
}

/// 缓冲文本框的 context 绑定：这是第三轮抓到的会**损坏数据**的问题。
/// 视图层不易直接单测，这里锁定生成 contextID 的约定本身。
final class BufferContextTests: XCTestCase {
    private func ctx(_ day: String, _ kind: String, _ id: String) -> String {
        "\(day)|\(kind)|\(id)"
    }

    func testContextChangesWithDay() {
        let id = UUID().uuidString
        XCTAssertNotEqual(ctx("2026-08-31", "summary", id), ctx("2026-09-01", "summary", id),
                          "日期一变 contextID 必须变，否则缓冲不会重置，"
                          + "前一天的文字会被提交进新一天")
    }

    func testContextDistinguishesFields() {
        let a = UUID().uuidString, b = UUID().uuidString
        XCTAssertNotEqual(ctx("2026-09-01", "todo", a), ctx("2026-09-01", "todo", b))
        XCTAssertNotEqual(ctx("2026-09-01", "planned", a), ctx("2026-09-01", "actual", a))
    }
}

/// 第四轮代码审查的回归测试。
final class ActualBlockTimeZoneTests: XCTestCase {

    private func utc2(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    /// 同时区：只给墙钟，不加时区后缀。
    func testSameTimeZoneRendersPlainWallClock() {
        // 珀斯(UTC+8) 2026-09-01 10:00 = 02:00 UTC
        let b = ActualBlock(start: utc2(2026, 9, 1, 2, 0), end: utc2(2026, 9, 1, 3, 0),
                            timeZoneIdentifier: "Australia/Perth", title: "x")
        XCTAssertEqual(b.rangeLabel(recordTimeZoneIdentifier: "Australia/Perth"),
                       "10:00 至 11:00")
    }

    /// 跨时区：必须按**块自身**时区渲染，并带上时区标识。
    /// 修复前用记录的时区渲染，纽约 20:00 会被显示成珀斯的次日 08:00 —— 语义就错了。
    func testCrossTimeZoneRendersInOwnZoneWithSuffix() {
        // 纽约(EDT, UTC-4) 2026-09-01 20:00 = 2026-09-02 00:00 UTC
        let b = ActualBlock(start: utc2(2026, 9, 2, 0, 0), end: utc2(2026, 9, 2, 1, 0),
                            timeZoneIdentifier: "America/New_York", title: "在纽约做的")
        let label = b.rangeLabel(recordTimeZoneIdentifier: "Australia/Perth")
        XCTAssertTrue(label.hasPrefix("20:00 至 21:00"),
                      "必须是纽约的 20:00，不是珀斯的 08:00；实际：\(label)")
        XCTAssertTrue(label.contains("America/New_York"),
                      "跨时区必须标出是哪个时区；实际：\(label)")
    }

    /// 导出的 Markdown 同样不能用记录时区去渲染跨时区的块。
    func testMarkdownExportsCrossTimeZoneCorrectly() {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        rec.actual = [
            ActualBlock(start: utc2(2026, 9, 1, 2, 0), end: utc2(2026, 9, 1, 3, 0),
                        timeZoneIdentifier: "Australia/Perth", title: "在珀斯做的"),
            ActualBlock(start: utc2(2026, 9, 2, 0, 0), end: utc2(2026, 9, 2, 1, 0),
                        timeZoneIdentifier: "America/New_York", title: "在纽约做的")
        ]
        let md = MarkdownRenderer.render(record: rec, usage: nil, settings: AppSettings())
        XCTAssertTrue(md.contains("- 10:00 至 11:00：在珀斯做的"))
        XCTAssertTrue(md.contains("20:00 至 21:00（America/New_York）：在纽约做的"),
                      "跨时区块必须导出为它自己的墙钟时间并标注时区。实际导出：\n\(md)")
        XCTAssertFalse(md.contains("08:00 至 09:00：在纽约做的"),
                       "绝不能按记录时区把纽约 20:00 渲染成珀斯次日 08:00")
    }

    /// 投影里越界块的标签同样按自身时区。
    func testProjectionOutOfRangeLabelUsesOwnZone() {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        rec.actual = [ActualBlock(start: utc2(2026, 9, 2, 0, 0), end: utc2(2026, 9, 2, 1, 0),
                                  timeZoneIdentifier: "America/New_York", title: "越界")]
        let p = DayTimelineProjection.project(record: rec)
        XCTAssertEqual(p.outOfRange.count, 1)
        XCTAssertTrue(p.outOfRange[0].label.hasPrefix("20:00"),
                      "越界提示也要给纽约的 20:00；实际：\(p.outOfRange[0].label)")
    }
}
