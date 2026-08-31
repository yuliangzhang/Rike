import XCTest
@testable import GongCore

/// 生成一份真实感的导出样例，写到 /tmp 供人工检视。
final class SampleExportTests: XCTestCase {
    func testWriteSampleForInspection() throws {
        var rec = DayRecord(key: DayKey(date: "2026-09-01", timeZoneIdentifier: "Australia/Perth"))
        var floor = Todo(text: "把蜂箱数据分析报告的图表跑通一张", kind: .floor)
        floor.status = .done
        rec.todos = [
            floor,
            Todo(text: "完成 apis prime 原型的登录流，发给 Xiaojia 过一遍", kind: .mit),
            Todo(text: "回 Liz 关于专家评审时间的邮件", order: 2)
        ]
        rec.planned = [
            PlannedBlock(start: 8 * 60, end: 9 * 60, title: "晨会 + 当日排程"),
            PlannedBlock(start: 9 * 60, end: 11 * 60 + 30, title: "蜂箱监测数据分析"),
            PlannedBlock(start: 13 * 60, end: 15 * 60, title: "apis prime 原型：登录流")
        ]
        let dayStart = GongTime.date(fromDayKey: "2026-09-01",
                                     timeZone: TimeZone(identifier: "Australia/Perth")!)!
        func at(_ h: Int, _ m: Int) -> Date { dayStart.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
        rec.actual = [
            ActualBlock(start: at(8, 15), end: at(9, 30),
                        timeZoneIdentifier: "Australia/Perth", title: "晨会"),
            ActualBlock(start: at(9, 30), end: at(10, 20),
                        timeZoneIdentifier: "Australia/Perth", title: "蜂箱监测数据分析"),
            ActualBlock(start: at(13, 10), end: at(15, 40),
                        timeZoneIdentifier: "Australia/Perth", title: "apis prime 原型：登录流")
        ]
        rec.summary.touched = "图表跑通那一下，卡了三天的其实只是坐标轴单位错了。卡住的时候先写下来，比再想一小时有用。"
        rec.summary.clarity = [ClarityEntry(
            stuckOn: "登录流的 token 刷新策略不确定，长短期两种方案没定",
            escapingFrom: "怕选错了以后要重构，其实重构成本没那么高",
            worstCase: "选错了改一天",
            firstStep: "把两个方案各写三行发给 Xiaojia 选")]
        rec.breaker.interruptions = [Interruption(trigger: .v2, minutes: 80,
                                                  escapingFrom: "token 方案没定")]

        let text = MarkdownRenderer.render(record: rec, usage: nil, settings: AppSettings())
        try text.write(to: URL(fileURLWithPath: "/tmp/gong_sample_export.md"),
                       atomically: true, encoding: .utf8)
        XCTAssertTrue(text.contains("# 20260901 周二"))
    }
}
