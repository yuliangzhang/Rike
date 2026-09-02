import XCTest
@testable import GongCore

final class ExportSafetyTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-export-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeSettings() -> AppSettings {
        var s = AppSettings()
        s.exportDirectoryPath = tmpDir.path
        return s
    }

    private func makeRecord(text: String = "把蜂箱数据分析报告的图表跑通") -> DayRecord {
        var r = DayRecord(date: "2026-08-31")
        r.todos = [Todo(text: text, order: 0)]
        return r
    }

    /// 从 GongPaths 取，不要在测试里复述文件名格式——
    /// 格式一改，硬编码的测试就会在**错误的路径**上摆好道具，然后测了个寂寞。
    private var targetURL: URL { GongPaths.exportFile(in: tmpDir, dayKey: "2026-08-31") }

    // MARK: 1. 首次导出：独占创建

    func testFirstExportCreatesFile() async throws {
        let (outcome, state) = await Exporter.shared.export(
            record: makeRecord(), usage: nil, settings: makeSettings())

        guard case .created(let url) = outcome else {
            return XCTFail("应为 .created，实际 \(outcome)")
        }
        XCTAssertEqual(url, targetURL)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(MarkdownRenderer.hasMarker(text), "首行必须有生成标记")
        XCTAssertTrue(text.contains("把蜂箱数据分析报告的图表跑通"))
        XCTAssertEqual(state?.contentHash, FileStore.sha256(text))
    }

    // MARK: 2. 内容未变：不写盘

    func testUnchangedContentSkipsWrite() async throws {
        var rec = makeRecord()
        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())
        rec.exportState = s1
        let mtime1 = try FileManager.default.attributesOfItem(atPath: targetURL.path)[.modificationDate] as? Date

        let (outcome, _) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())
        guard case .unchanged = outcome else { return XCTFail("应为 .unchanged，实际 \(outcome)") }

        let mtime2 = try FileManager.default.attributesOfItem(atPath: targetURL.path)[.modificationDate] as? Date
        XCTAssertEqual(mtime1, mtime2, "内容没变就不应该写盘")
    }

    // MARK: 3. 我们自己的文件、未被改动 → 允许更新

    func testUpdatesOwnUnmodifiedFile() async throws {
        var rec = makeRecord()
        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())
        rec.exportState = s1

        rec.todos.append(Todo(text: "回 Liz 的邮件"))
        let (outcome, s2) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())

        guard case .updated(let url) = outcome else {
            return XCTFail("应为 .updated，实际 \(outcome)")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("回 Liz 的邮件"))
        XCTAssertNotEqual(s1?.contentHash, s2?.contentHash)
    }

    // MARK: 4. 被外部修改 → 绝不覆盖

    func testExternallyModifiedFileIsNeverOverwritten() async throws {
        var rec = makeRecord()
        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())
        rec.exportState = s1

        // 模拟用户/云同步在我们背后改了这个文件
        let userEdit = MarkdownRenderer.marker + "\n# 我手工改过的内容，绝不能丢\n"
        try userEdit.write(to: targetURL, atomically: true, encoding: .utf8)

        rec.todos.append(Todo(text: "新任务"))
        let (outcome, state) = await Exporter.shared.export(record: rec, usage: nil, settings: makeSettings())

        guard case .conflict(let conflictURL) = outcome else {
            return XCTFail("应为 .conflict，实际 \(outcome)")
        }
        XCTAssertNil(state, "冲突时不得更新 exportState")

        let stillThere = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertEqual(stillThere, userEdit, "原文件必须一字不动")
        XCTAssertTrue(try String(contentsOf: conflictURL, encoding: .utf8).contains("新任务"))
        XCTAssertTrue(conflictURL.lastPathComponent.contains("conflict"))
    }

    // MARK: 5. 用户手写的同名文件（无标记）→ 绝不覆盖

    func testHandwrittenFileIsNeverOverwritten() async throws {
        let handwritten = "# 我自己写的工作记录\n- 这是手写内容，不是 Gong 生成的\n"
        try handwritten.write(to: targetURL, atomically: true, encoding: .utf8)

        let (outcome, _) = await Exporter.shared.export(
            record: makeRecord(), usage: nil, settings: makeSettings())

        guard case .conflict = outcome else { return XCTFail("应为 .conflict，实际 \(outcome)") }
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), handwritten,
                       "无生成标记的文件必须原样保留")
    }

    // MARK: 6. 旧冲突文件也不许被覆盖

    func testOldConflictFilesAreNotOverwritten() async throws {
        try "手写".write(to: targetURL, atomically: true, encoding: .utf8)

        let (o1, _) = await Exporter.shared.export(record: makeRecord(text: "第一次"),
                                                   usage: nil, settings: makeSettings())
        let (o2, _) = await Exporter.shared.export(record: makeRecord(text: "第二次"),
                                                   usage: nil, settings: makeSettings())
        guard case .conflict(let u1) = o1, case .conflict(let u2) = o2 else {
            return XCTFail("两次都应为 .conflict")
        }
        XCTAssertNotEqual(u1, u2, "第二个冲突必须换新文件名")
        XCTAssertTrue(try String(contentsOf: u1, encoding: .utf8).contains("第一次"),
                      "旧冲突文件内容必须保留")
        XCTAssertTrue(try String(contentsOf: u2, encoding: .utf8).contains("第二次"))
    }

    // MARK: 7. 隐私：默认不导出使用明细

    func testUsageDetailNotExportedByDefault() async throws {
        var usage = UsageDay(date: "2026-08-31")
        usage.intervals = [UsageInterval(bundleId: "com.tencent.xinWeChat", appName: "微信",
                                         start: Date(), end: Date().addingTimeInterval(3600))]
        let settings = makeSettings()
        XCTAssertFalse(settings.exportUsageDetail, "默认必须关闭")

        let text = MarkdownRenderer.render(record: makeRecord(), usage: usage, settings: settings)
        XCTAssertFalse(text.contains("微信"), "默认不得把应用使用明细写进 Work_Records")

        var opened = settings
        opened.exportUsageDetail = true
        XCTAssertTrue(MarkdownRenderer.render(record: makeRecord(), usage: usage, settings: opened)
                        .contains("微信"), "显式开启后才导出")
    }

    // MARK: 8. 渲染：中性措辞

    func testRenderUsesNeutralWording() {
        var rec = makeRecord()
        rec.floor.text = "23:00 前睡觉"
        rec.floor.status = .done
        rec.todos[0].status = .notRecorded
        let text = MarkdownRenderer.render(record: rec, usage: nil, settings: makeSettings())
        XCTAssertTrue(text.contains("- 下限：已完成"), text)
        XCTAssertTrue(text.contains("- 最重要：未记录"), "未做的第一条应为「未记录」而非「未达成」\n\(text)")
        XCTAssertFalse(text.contains("✓"))
        XCTAssertFalse(text.contains("⚠"))
        XCTAssertFalse(text.contains("！"))
    }

    /// 导出文件名的格式（用户指定）。
    /// 带横杠的日期在 Finder 里按名字排序就是按时间排序，也一眼看得出是哪天的。
    func testExportFileNameFormat() {
        let dir = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        XCTAssertEqual(GongPaths.exportFile(in: dir, dayKey: "2026-08-31").lastPathComponent,
                       "2026-08-31-daily-record.md")
        XCTAssertEqual(GongPaths.conflictFile(in: dir, dayKey: "2026-08-31").lastPathComponent,
                       "2026-08-31-daily-record.gong-conflict.md")
        XCTAssertEqual(GongPaths.conflictFile(in: dir, dayKey: "2026-08-31", index: 2).lastPathComponent,
                       "2026-08-31-daily-record.gong-conflict-2.md")
    }

    /// 导出的永远是**当前这一天**，文件名跟着界面日期走。
    func testExportUsesTheRecordsOwnDate() async throws {
        var rec = DayRecord(date: "2026-09-15")
        rec.summary.touched = "九月十五号写的"
        let (outcome, _) = await Exporter.shared.export(
            record: rec, usage: nil, settings: makeSettings())
        guard case .created(let url) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(url.lastPathComponent, "2026-09-15-daily-record.md")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("九月十五号写的"))
    }

    /// 下限单独成节，且不占用 TODO 的位置。
    func testFloorExportsAsItsOwnSection() {
        var rec = makeRecord()
        rec.floor.text = "今天必须在 23:00 前睡觉"
        let text = MarkdownRenderer.render(record: rec, usage: nil, settings: makeSettings())
        XCTAssertTrue(text.contains("## 今日下限"), text)
        XCTAssertTrue(text.contains("今天必须在 23:00 前睡觉"), text)
        // TODO 一节里不该重复出现下限
        let todoSection = text.components(separatedBy: "## 今日 TODO")[1]
        XCTAssertFalse(todoSection.contains("23:00 前睡觉"))
    }

    /// TODO 按优先级编号导出，第一条带最重要标记。
    func testTodosExportNumberedByPriority() {
        var rec = makeRecord()
        rec.todos = [Todo(text: "最要紧的", order: 0), Todo(text: "其次", order: 1)]
        let text = MarkdownRenderer.render(record: rec, usage: nil, settings: makeSettings())
        XCTAssertTrue(text.contains("1. [ ] ★ 最重要：最要紧的"), text)
        XCTAssertTrue(text.contains("2. [ ] 其次"), text)
    }

    /// 成功日记与明天会更好也要进导出。
    func testWinsAndTomorrowExport() {
        var rec = makeRecord()
        rec.summary.wins = [WinEntry(text: "把拖了很久的邮件发出去了"),
                            WinEntry(text: "删干净了一段乱码")]
        rec.summary.tomorrow = "上午不开会，留给深度工作"
        let text = MarkdownRenderer.render(record: rec, usage: nil, settings: makeSettings())
        XCTAssertTrue(text.contains("### 成功日记"), text)
        XCTAssertTrue(text.contains("1. 把拖了很久的邮件发出去了"), text)
        XCTAssertTrue(text.contains("2. 删干净了一段乱码"), text)
        XCTAssertTrue(text.contains("### 明天会更好"), text)
        XCTAssertTrue(text.contains("上午不开会，留给深度工作"), text)
    }

    // MARK: 9. 导出文件名与星期由 Calendar 计算

    func testExportHeaderWeekday() {
        let text = MarkdownRenderer.render(record: makeRecord(), usage: nil, settings: makeSettings())
        XCTAssertTrue(text.contains("# 20260831 周一"), "2026-08-31 是周一")
    }
}

// MARK: - 切换界面语言后重新导出（用户明确选择「导出跟界面语言走」）

/// 这是这个选择最容易出错的地方：切语言会让同一天的渲染结果完全不同。
/// 如果「是否可替换」的判断拿的是**新渲染的哈希**去比对盘上文件，
/// 那第一次切语言就会把自己上次导出的文件判成「外部修改」，
/// 从此每天都写冲突文件，用户会收到一堆莫名其妙的 *.gong-conflict.md。
///
/// 正确的判断是「盘上内容 vs 我上次写下去的内容」，与新渲染结果无关。
final class ExportLanguageSwitchTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gong-lang-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpDir) }

    private func settings(_ lang: LangPreference) -> AppSettings {
        var s = AppSettings()
        s.exportDirectoryPath = tmpDir.path
        s.language = lang
        return s
    }

    private func record() -> DayRecord {
        var r = DayRecord(date: "2026-08-31")
        r.todos = [Todo(text: "把蜂箱数据管线跑通", kind: .floor)]
        r.planned = [PlannedBlock(start: 9 * 60, end: 10 * 60, title: "深度工作")]
        return r
    }

    private var target: URL { GongPaths.exportFile(in: tmpDir, dayKey: "2026-08-31") }

    func testSwitchingLanguageUpdatesInPlaceWithoutConflict() async throws {
        var rec = record()

        // 1) 中文导出
        let (o1, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.zh))
        guard case .created = o1 else { return XCTFail("首次应为 .created，实际 \(o1)") }
        rec.exportState = s1
        let zh = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(zh.contains("## 今日 TODO"), zh)

        // 2) 切英文再导出同一天 —— 必须**原地更新**，不能判成冲突
        let (o2, s2) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.en))
        guard case .updated(let u) = o2 else {
            return XCTFail("切语言后应原地更新，实际 \(o2)。若为 .conflict 说明可替换判断用错了哈希")
        }
        XCTAssertEqual(u, target)
        rec.exportState = s2
        let en = try String(contentsOf: target, encoding: .utf8)
        XCTAssertTrue(en.contains("## Today's TODO"), en)
        XCTAssertFalse(en.contains("## 今日 TODO"), "英文导出不该残留中文小节名\n\(en)")

        // 3) 没有产生任何冲突文件
        let files = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertEqual(files.filter { $0.contains("conflict") }, [], "不该产生冲突文件：\(files)")

        // 4) 再切回中文，同样原地更新
        let (o3, _) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.zh))
        guard case .updated = o3 else { return XCTFail("切回中文应原地更新，实际 \(o3)") }
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("## 今日 TODO"))
    }

    /// 语言没变、内容也没变 → 仍然应当识别为「无变化」，不重复写盘。
    func testSameLanguageUnchangedStillSkipsWrite() async throws {
        var rec = record()
        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.en))
        rec.exportState = s1
        let (o2, _) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.en))
        guard case .unchanged = o2 else { return XCTFail("应为 .unchanged，实际 \(o2)") }
    }

    /// 但外部真的改了文件，切语言也不能变成覆盖的借口。
    func testExternalEditStillProducesConflictEvenAcrossLanguages() async throws {
        var rec = record()
        let (_, s1) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.zh))
        rec.exportState = s1

        try (try String(contentsOf: target, encoding: .utf8) + "\n手工加的一行\n")
            .write(to: target, atomically: true, encoding: .utf8)

        let (o2, _) = await Exporter.shared.export(record: rec, usage: nil, settings: settings(.en))
        guard case .conflict(let c) = o2 else {
            return XCTFail("外部改动过就必须走冲突，实际 \(o2)")
        }
        XCTAssertTrue(c.lastPathComponent.contains("conflict"))
        XCTAssertTrue(try String(contentsOf: target, encoding: .utf8).contains("手工加的一行"),
                      "原文件必须一字不动")
    }
}
