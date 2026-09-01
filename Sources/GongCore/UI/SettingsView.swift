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
    var onAppearanceChange: (AppearancePreference) -> Void
    var onLanguageChange: (LangPreference) -> Void

    private var s: Binding<AppSettings> { $settings.settings }

    var body: some View {
        ScrollView { pageContent }
            .background(Theme.inset)
    }

    var pageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            appearanceSection
            exportSection
            privacySection
            widgetSection
            monitorSection
            breakerSection
            categorySection
            systemSection
        }
        .padding(24)
    }

    // MARK: 外观与语言

    private var appearanceSection: some View {
        Panel(title: L(.setAppearanceTitle)) {
            Picker(L(.setLanguage), selection: Binding(
                get: { settings.settings.language },
                set: { p in
                    settings.settings.language = p
                    UILang.set(p)          // 界面立即生效，不用重启
                    onLanguageChange(p)    // 菜单栏标题是构建时定死的，得让它重建
                })) {
                Text(L(.optSystem)).tag(LangPreference.system)
                Text(L(.optZh)).tag(LangPreference.zh)
                Text(L(.optEn)).tag(LangPreference.en)
            }
            .pickerStyle(.segmented).frame(maxWidth: 340)

            Picker(L(.setAppearance), selection: Binding(
                get: { settings.settings.appearance },
                set: { p in
                    settings.settings.appearance = p
                    onAppearanceChange(p)
                })) {
                Text(L(.optSystem)).tag(AppearancePreference.system)
                Text(L(.optLight)).tag(AppearancePreference.light)
                Text(L(.optDark)).tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented).frame(maxWidth: 340)
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        Panel(title: L(.setExport)) {
            HStack {
                Text(settings.settings.exportDirectoryPath)
                    .font(Theme.mono(Theme.Size.meta)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L(.setChooseDir)) { chooseDirectory() }
            }
            Toggle(L(.setAutoExport), isOn: s.autoExport)
            Explain(L(.setAutoExportBody))

            HStack {
                Button(L(.setExportNow)) { Task { await store.exportNow() } }
                if let n = store.notice {
                    Text(n.text)
                        .font(Theme.ui(Theme.Size.meta))
                        .foregroundStyle(n.level == .warning ? Theme.mark : Theme.muted)
                        .lineLimit(2)
                }
            }
            Explain(L(.setExportSafety))
        }
    }

    private var privacySection: some View {
        Panel(title: L(.setPrivacy)) {
            Toggle(L(.setExportUsage), isOn: s.exportUsageDetail)
            Toggle(L(.setExportInterruptions), isOn: s.exportInterruptionDetail)
            Explain(L(.setPrivacyBody), color: Theme.mark)
        }
    }

    // MARK: 挂件

    private var widgetSection: some View {
        Panel(title: L(.setWidget)) {
            Toggle(L(.setWidgetShow), isOn: Binding(
                get: { settings.settings.widgetVisible },
                set: { v in settings.settings.widgetVisible = v; onWidgetVisibilityChange(v) }))

            Picker(L(.setWidgetLevel), selection: Binding(
                get: { settings.settings.widgetMode },
                set: { m in settings.settings.widgetMode = m; onWidgetModeChange(m) })) {
                ForEach(WidgetMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Explain(L(.setWidgetBody))
        }
    }

    // MARK: 监控

    private var monitorSection: some View {
        Panel(title: L(.setMonitor)) {
            Toggle(L(.setMonitorEnable), isOn: Binding(
                get: { settings.settings.monitoringEnabled },
                set: { v in settings.settings.monitoringEnabled = v; onMonitoringChange(v) }))
            HStack {
                Text(L(.setIdleThreshold)).font(Theme.ui(Theme.Size.body))
                Spacer()
                Stepper(L(.setSecondsCount, settings.settings.idleThresholdSeconds),
                        value: s.idleThresholdSeconds, in: 30...1800, step: 30)
            }
            HStack {
                Text(L(.setRetention)).font(Theme.ui(Theme.Size.body))
                Spacer()
                Stepper(L(.setDaysCount, settings.settings.rawLogRetentionDays),
                        value: s.rawLogRetentionDays, in: 7...730, step: 7)
            }
            Explain(L(.setMonitorBody))
        }
    }

    private var breakerSection: some View {
        Panel(title: L(.setBreaker)) {
            Toggle(L(.setBreakerEnable), isOn: s.breakerEnabled)
            HStack {
                Text(L(.setBreakerThreshold)).font(Theme.ui(Theme.Size.body))
                Spacer()
                Stepper(L(.setMinutesCount, settings.settings.breakerThresholdMinutes),
                        value: s.breakerThresholdMinutes, in: 5...120, step: 5)
            }
            HStack {
                Text(L(.setSnooze)).font(Theme.ui(Theme.Size.body))
                Spacer()
                Stepper(L(.setMinutesCount, settings.settings.breakerSnoozeMinutes),
                        value: s.breakerSnoozeMinutes, in: 5...180, step: 5)
            }
            Explain(L(.setBreakerBody))
        }
    }

    // MARK: 分类

    private var categorySection: some View {
        Panel(title: L(.setCategories)) {
            Explain(L(.setCategoriesBody))
            if let u = store.usage, !u.intervals.isEmpty {
                ForEach(u.totals(), id: \.bundleId) { row in
                    HStack {
                        Text(row.name).font(Theme.ui(Theme.Size.body))
                            .frame(width: 190, alignment: .leading)
                        Text(GongTime.formatDuration(row.seconds))
                            .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.faint)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.settings.category(for: row.bundleId) },
                            set: { settings.settings.categories[row.bundleId] = $0 })) {
                            ForEach(AppCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .labelsHidden().frame(width: 110)
                    }
                }
            } else {
                Explain(L(.setCategoriesEmpty))
            }
        }
    }

    private var systemSection: some View {
        Panel(title: L(.setSystem)) {
            Toggle(L(.setLaunchAtLogin), isOn: Binding(
                get: { settings.settings.launchAtLogin },
                set: { setLoginItem($0) }))
            if let e = loginItemError {
                Explain(e, color: Theme.mark)
            }
            Text(L(.setDataLocation, GongPaths.root.path))
                .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.faint)
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
            loginItemError = L(.setLoginFailed, error.localizedDescription)
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

}
