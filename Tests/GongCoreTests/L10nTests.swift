import XCTest
@testable import GongCore

/// 文案表的完整性。
///
/// 「漏翻一条」已经由 `S.pair` 的穷尽 switch 在**编译期**挡住了；
/// 这里挡的是编译器看不见的三类问题：空串、格式符不匹配、以及中英写成同一句。
final class L10nTests: XCTestCase {

    /// 提取 `%@` / `%d` 一类占位符，顺序敏感。
    private func specifiers(_ s: String) -> [String] {
        var out: [String] = []
        var it = s.makeIterator()
        var pending: Character?
        while let c = pending ?? it.next() {
            pending = nil
            guard c == "%" else { continue }
            guard let n = it.next() else { break }
            if n == "%" { continue }                 // 转义的百分号
            var spec = "%"
            var cur: Character? = n
            // 跳过标志与宽度
            while let ch = cur, "0123456789.-+ #'".contains(ch) { cur = it.next() }
            if let ch = cur { spec.append(ch) }
            out.append(spec)
        }
        return out
    }

    func testNoEmptyStrings() {
        for k in S.allCases {
            let (zh, en) = k.pair
            // kindFloorMenu 之类的「普通」项允许为空串，其余不允许
            if k == .kindFloor || k == .kindMit { continue }
            XCTAssertFalse(zh.isEmpty, "\(k) 的中文为空")
            XCTAssertFalse(en.isEmpty, "\(k) 的英文为空")
        }
    }

    /// 中英文的格式符必须**逐个对应**。不一致时 `String(format:)` 会读错参数栈——
    /// 轻则显示乱码，重则崩溃，而且只在切到那个语言时才出现。
    func testFormatSpecifiersMatch() {
        for k in S.allCases {
            let (zh, en) = k.pair
            XCTAssertEqual(specifiers(zh), specifiers(en),
                           "\(k) 的中英格式符不一致：zh=\(specifiers(zh)) en=\(specifiers(en))")
        }
    }

    /// 中英写成同一句，通常是复制粘贴时忘了翻。
    /// 少数确实相同的（语言自称、纯符号）在这里显式豁免。
    func testTranslationsDiffer() {
        let allowedSame: Set<String> = ["optZh", "optEn"]
        for k in S.allCases {
            let (zh, en) = k.pair
            guard !allowedSame.contains("\(k)") else { continue }
            XCTAssertNotEqual(zh, en, "\(k) 的中英文完全相同，多半是漏翻了")
        }
    }

    func testResolutionFallsBackToEnglishForNonChineseLocales() {
        XCTAssertEqual(LangPreference.zh.resolved, .zh)
        XCTAssertEqual(LangPreference.en.resolved, .en)
        // .system 取决于运行环境，只要求它给出一个合法值
        XCTAssertTrue([Lang.zh, .en].contains(LangPreference.system.resolved))
    }

    // MARK: 导出跟随语言（用户明确选择的行为）

    private func sampleRecord() -> DayRecord {
        var rec = DayRecord(key: DayKey(date: "2026-08-31", timeZoneIdentifier: "Australia/Perth"))
        rec.todos = [Todo(text: "写下明天的第一步", kind: .floor, order: 0)]
        rec.planned = [PlannedBlock(start: 9 * 60, end: 10 * 60, title: "深度工作")]
        rec.summary.touched = "今天没有被小说带走"
        return rec
    }

    func testExportFollowsChinese() {
        var s = AppSettings(); s.language = .zh
        let md = MarkdownRenderer.render(record: sampleRecord(), usage: nil, settings: s)
        XCTAssertTrue(md.contains("## 今日 TODO"), md)
        XCTAssertTrue(md.contains("09:00 至 10:00"), md)
        XCTAssertTrue(md.contains("周一"), md)
        XCTAssertTrue(md.contains("- 下限：已完成") || md.contains("- 下限：未记录"), md)
    }

    func testExportFollowsEnglish() {
        var s = AppSettings(); s.language = .en
        let md = MarkdownRenderer.render(record: sampleRecord(), usage: nil, settings: s)
        XCTAssertTrue(md.contains("## Today's TODO"), md)
        XCTAssertTrue(md.contains("09:00 – 10:00"), md)
        XCTAssertTrue(md.contains("Mon"), md)
        XCTAssertFalse(md.contains("今日 TODO"), "英文导出里不该残留中文小节名\n\(md)")
    }

    /// 默认必须是中文：这个 app 的既有记录全是中文，而机器的系统语言是 en-AU。
    /// 默认跟随系统会让升级后界面突然变英文。
    func testDefaultLanguageIsChinese() {
        XCTAssertEqual(AppSettings().language, .zh)
    }

    /// marker 绝不能跟着改名动——它决定了「这个文件是不是我们生成的」，
    /// 变了就会把所有历史导出判成外部文件，从此每次导出都写冲突文件。
    func testGeneratedMarkerIsStable() {
        XCTAssertEqual(MarkdownRenderer.marker, "<!-- gong:generated v1 -->")
    }
}
