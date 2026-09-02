import XCTest
import SwiftUI
import AppKit
@testable import GongCore

/// 离屏渲染各视图为 PNG。
///
/// 两个用途：
/// ① 冒烟测试 —— 视图能否在中/英 × 明/暗四种组合下构建并绘制出非空图像。
///    SwiftUI 的崩溃大多发生在实际布局时，只 `swift build` 是看不出来的。
/// ② 改版时不用截屏权限就能看到成品（这台机器没给终端屏幕录制权限）。
///
/// 输出目录由 `GONG_PREVIEW_DIR` 指定；不设就跳过写盘，只做冒烟检查。
@MainActor
final class PreviewRenderTests: XCTestCase {

    private func sampleStores() -> (DayStore, SettingsStore, UsageMonitor, BreakerEngine) {
        let day = DayStore(dayKey: DayKey(date: "2026-09-01",
                                          timeZoneIdentifier: TimeZone.current.identifier))
        day.mutate { rec in
            rec.floor.text = "今天必须在 23:00 前睡觉"
            rec.floor.status = .done
            rec.todos = [
                Todo(text: "把审查意见过一遍并合并进主干", order: 0),
                Todo(text: "蜂箱数据管线重写：先写失败用例", order: 1),
                Todo(text: "回复蜂博会的展位邀请", order: 2)
            ]
            rec.planned = [
                PlannedBlock(start: 9 * 60, end: 11 * 60 + 30, title: "深度：蜂箱数据管线重写"),
                PlannedBlock(start: 11 * 60 + 30, end: 12 * 60, title: "邮件与消息"),
                PlannedBlock(start: 14 * 60, end: 16 * 60, title: "深度：审查意见合并"),
                PlannedBlock(start: 16 * 60, end: 17 * 60, title: "现场巡查")
            ]
            let base = GongTime.date(fromDayKey: "2026-09-01") ?? Date()
            func at(_ h: Int, _ m: Int) -> Date { base.addingTimeInterval(TimeInterval(h * 3600 + m * 60)) }
            rec.actual = [
                ActualBlock(start: at(9, 12), end: at(11, 5), title: "Xcode", source: .monitor),
                ActualBlock(start: at(11, 5), end: at(11, 40), title: "Mail", source: .monitor),
                ActualBlock(start: at(14, 20), end: at(15, 50), title: "Terminal", source: .monitor),
                ActualBlock(start: at(16, 0), end: at(16, 35), title: "Chrome", source: .monitor)
            ]
            rec.summary.touched = "卡在时区那段两个小时，第一反应又是想去翻小说。"
                + "停下来花三分钟把「到底卡在哪」写出来，那股劲儿就散了——"
                + "原来我逃的不是这个问题，是「又要重写一遍」的挫败。"
            rec.summary.wins = [
                WinEntry(text: "把拖了三周的展位邀请回掉了"),
                WinEntry(text: "删干净了 reducer 里那段没人敢动的代码")
            ]
            rec.summary.tomorrow = "上午不排会，把最完整的两小时留给数据管线。"
            var c = ClarityEntry()
            c.stuckOn = "实际块跨时区时该按谁的墙钟存"
            c.escapingFrom = "怕结论错了要把三个文件全推倒"
            c.worstCase = "改半天发现方案不对，损失一个下午"
            c.firstStep = "先只写一个跨时区的失败用例"
            rec.summary.clarity = [c]
        }
        return (day, SettingsStore(), UsageMonitor(), BreakerEngine())
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat,
                                 dark: Bool, name: String) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var image: NSImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content:
                view.frame(width: width, height: height)
                    .environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            image = renderer.nsImage
        }
        guard let img = image else { return XCTFail("\(name) 渲染为空") }
        XCTAssertGreaterThan(img.size.width, 0, "\(name) 宽度为 0")

        guard let dir = ProcessInfo.processInfo.environment["GONG_PREVIEW_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("\(name) 无法编码 PNG")
        }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testRendersGongTableInAllCombinations() {
        let (day, settings, _, _) = sampleStores()
        for lang in [Lang.zh, .en] {
            UILang.set(lang == .zh ? .zh : .en)
            for dark in [false, true] {
                render(GongTableView(store: day, settings: settings).tableContent
                        .background(Theme.inset),
                       width: 980, height: 1080, dark: dark,
                       name: "table-\(lang.rawValue)-\(dark ? "dark" : "light")")
            }
        }
        UILang.set(.zh)
    }

    func testRendersWidget() {
        let (day, settings, monitor, breaker) = sampleStores()
        for dark in [false, true] {
            render(WidgetView(store: day, settings: settings, monitor: monitor,
                              breaker: breaker, onOpenMain: {})
                    .padding(24).background(dark ? Color.black : Color.white),
                   width: 340, height: 260, dark: dark,
                   name: "widget-\(dark ? "dark" : "light")")
        }
    }

    func testRendersBreakerAndSettings() {
        let (day, settings, monitor, breaker) = sampleStores()
        for dark in [false, true] {
            render(BreakerView(store: day, settings: settings, breaker: breaker, monitor: monitor)
                        .pageContent.background(Theme.inset),
                   width: 980, height: 1150, dark: dark, name: "breaker-\(dark ? "dark" : "light")")
            render(SettingsView(settings: settings, store: day,
                                onWidgetModeChange: { _ in }, onWidgetVisibilityChange: { _ in },
                                onMonitoringChange: { _ in }, onAppearanceChange: { _ in },
                                onLanguageChange: { _ in }).pageContent.background(Theme.inset),
                   width: 980, height: 1250, dark: dark, name: "settings-\(dark ? "dark" : "light")")
        }
    }
}
