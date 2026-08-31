import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var store: DayStore
    var onWidgetModeChange: (WidgetMode) -> Void
    var onWidgetVisibilityChange: (Bool) -> Void
    var onMonitoringChange: (Bool) -> Void

    @State private var loginItemError: String?

    private var s: Binding<AppSettings> { $settings.settings }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                exportSection
                privacySection
                widgetSection
                monitorSection
                breakerSection
                categorySection
                systemSection
            }
            .padding(22)
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        panel("Markdown 导出") {
            HStack {
                Text(settings.settings.exportDirectoryPath)
                    .font(Theme.monoSized(11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("选择目录…") { chooseDirectory() }
            }
            Toggle("保存时自动导出", isOn: s.autoExport)
            Text("""
            默认关闭。每次写入都存在「外部进程可能同时修改同一文件」的暴露窗口，\
            降低写入频率是最有效的缓解。需要时用下面的按钮手动导出即可。
            """)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("立即导出今天") { Task { await store.exportNow() } }
                if let n = store.notice {
                    Text(n.text)
                        .font(.system(size: 11))
                        .foregroundStyle(n.level == .warning ? Theme.warn : Color.secondary)
                        .lineLimit(2)
                }
            }
            Text("""
            安全规则：目标文件不存在时独占创建；已存在且确认是本应用生成、内容未被改动时才替换；\
            否则一律另存为 *.gong-conflict.md，原文件绝不改动。
            """)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacySection: some View {
        panel("隐私") {
            Toggle("导出应用使用明细", isOn: s.exportUsageDetail)
            Toggle("导出中断记录明细", isOn: s.exportInterruptionDetail)
            Text("""
            两项默认关闭。导出目录在 Work_Records 下，这些内容可能被同步到云盘或整体喂给 AI 阅读；\
            软件使用记录与中断记录属于个人行为数据，开启前请确认你接受这一点。
            """)
                .font(.system(size: 11)).foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 挂件

    private var widgetSection: some View {
        panel("桌面挂件") {
            Toggle("显示挂件", isOn: Binding(
                get: { settings.settings.widgetVisible },
                set: { v in settings.settings.widgetVisible = v; onWidgetVisibilityChange(v) }))

            Picker("层级", selection: Binding(
                get: { settings.settings.widgetMode },
                set: { m in settings.settings.widgetMode = m; onWidgetModeChange(m) })) {
                ForEach(WidgetMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Text("""
            桌面层的行为由系统决定，在 Stage Manager、全屏应用、Mission Control 下不保证一致可见——\
            这是 macOS 的限制，不是设置错误。需要始终可见就选「置顶」。\
            菜单栏图标里也有「把挂件提到最前」。
            """)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 监控

    private var monitorSection: some View {
        panel("使用时长监控") {
            Toggle("启用监控", isOn: Binding(
                get: { settings.settings.monitoringEnabled },
                set: { v in settings.settings.monitoringEnabled = v; onMonitoringChange(v) }))
            HStack {
                Text("空闲判定阈值").font(.system(size: 12))
                Spacer()
                Stepper("\(settings.settings.idleThresholdSeconds) 秒",
                        value: s.idleThresholdSeconds, in: 30...1800, step: 30)
            }
            HStack {
                Text("原始事件日志保留").font(.system(size: 12))
                Spacer()
                Stepper("\(settings.settings.rawLogRetentionDays) 天",
                        value: s.rawLogRetentionDays, in: 7...730, step: 7)
            }
            Text("""
            前台应用统计与空闲检测不需要任何系统权限，本应用也不会请求辅助功能或屏幕录制权限。\
            超过保留期的原始事件日志会被清理，已汇总的统计保留。
            """)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var breakerSection: some View {
        panel("注意力阻断器") {
            Toggle("启用主动提示", isOn: s.breakerEnabled)
            HStack {
                Text("「其他」类应用连续前台超过").font(.system(size: 12))
                Spacer()
                Stepper("\(settings.settings.breakerThresholdMinutes) 分钟",
                        value: s.breakerThresholdMinutes, in: 5...120, step: 5)
            }
            HStack {
                Text("忽略时长").font(.system(size: 12))
                Spacer()
                Stepper("\(settings.settings.breakerSnoozeMinutes) 分钟",
                        value: s.breakerSnoozeMinutes, in: 5...180, step: 5)
            }
            Text("提示只用挂件描边变色 + 非模态浮层，不会弹出系统对话框打断你正在做的事。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: 分类

    private var categorySection: some View {
        panel("应用分类") {
            Text("影响看板配色与阻断器判定。v1 只按应用分类，不做网页级识别。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let u = store.usage, !u.intervals.isEmpty {
                ForEach(u.totals(), id: \.bundleId) { row in
                    HStack {
                        Text(row.name).font(.system(size: 12)).frame(width: 180, alignment: .leading)
                        Text(GongTime.formatDuration(row.seconds))
                            .font(Theme.monoSized(10)).foregroundStyle(.tertiary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.settings.category(for: row.bundleId) },
                            set: { settings.settings.categories[row.bundleId] = $0 })) {
                            ForEach(AppCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(width: 100)
                    }
                }
            } else {
                Text("今天还没有监控数据，出现后会在这里列出。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var systemSection: some View {
        panel("系统") {
            Toggle("开机启动", isOn: Binding(
                get: { settings.settings.launchAtLogin },
                set: { setLoginItem($0) }))
            if let e = loginItemError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
            Text("数据位置：\(GongPaths.root.path)")
                .font(Theme.monoSized(10)).foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            settings.settings.launchAtLogin = on
            loginItemError = nil
        } catch {
            loginItemError = "设置开机启动失败：\(error.localizedDescription)"
        }
    }

    private func chooseDirectory() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.directoryURL = settings.settings.exportDirectory
        if p.runModal() == .OK, let u = p.url {
            settings.settings.exportDirectoryPath = u.path
        }
    }

    @ViewBuilder
    private func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .bold))
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
