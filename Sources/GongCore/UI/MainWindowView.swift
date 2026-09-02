import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var breaker: BreakerEngine

    var onWidgetModeChange: (WidgetMode) -> Void
    var onWidgetVisibilityChange: (Bool) -> Void
    var onMonitoringChange: (Bool) -> Void
    var onAppearanceChange: (AppearancePreference) -> Void
    var onLanguageChange: (LangPreference) -> Void
    var onThemeChange: (ThemePalette) -> Void

    @State private var tab: Tab = .gong

    enum Tab: String, CaseIterable, Identifiable {
        case gong, dash, breaker, settings
        var id: String { rawValue }
        @MainActor var title: String {
            switch self {
            case .gong:     return L(.tabTable)
            case .dash:     return L(.tabDashboard)
            case .breaker:  return L(.tabBreaker)
            case .settings: return L(.tabSettings)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                GongMark(size: 16)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Theme.band)

            if let n = store.notice { noticeBar(n) }

            Rectangle().fill(Theme.beam).frame(height: Theme.Metric.beamWidth)

            switch tab {
            case .gong:
                GongTableView(store: store, settings: settings)
            case .dash:
                DashboardView(store: store, settings: settings)
            case .breaker:
                BreakerView(store: store, settings: settings, breaker: breaker, monitor: monitor)
            case .settings:
                SettingsView(settings: settings,
                             store: store,
                             onWidgetModeChange: onWidgetModeChange,
                             onWidgetVisibilityChange: onWidgetVisibilityChange,
                             onMonitoringChange: onMonitoringChange,
                             onAppearanceChange: onAppearanceChange,
                             onLanguageChange: onLanguageChange,
                             onThemeChange: onThemeChange)
            }
        }
        .frame(minWidth: 940, minHeight: 680)
    }

    private func noticeBar(_ n: DayStore.Notice) -> some View {
        HStack(spacing: 10) {
            Text(n.text).font(Theme.ui(Theme.Size.meta))
                .foregroundStyle(n.level == .warning ? Theme.mark : Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L(.gotIt)) { store.dismissNotice() }
                .buttonStyle(.plain).font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background((n.level == .warning ? Theme.mark : Theme.plan).opacity(0.12))
    }
}

/// 阻断器的**非模态**浮层。绝不用 NSAlert —— 模态弹窗会阻塞一切，且与「中性不评价」冲突。
struct BreakerAlertView: View {
    @ObservedObject var breaker: BreakerEngine
    @ObservedObject var settings: SettingsStore
    var onLog: () -> Void
    var onOpenMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GongMark(size: 13)
                Text(fact).font(Theme.ui(Theme.Size.meta, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    breaker.snooze(minutes: settings.settings.breakerSnoozeMinutes)
                } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            Explain(L(.alertBody))

            HStack(spacing: 8) {
                Button(L(.alertLog)) { onLog() }
                Button(L(.alertOpen)) { onOpenMain() }
                Button(L(.alertSnooze, settings.settings.breakerSnoozeMinutes)) {
                    breaker.snooze(minutes: settings.settings.breakerSnoozeMinutes)
                }
            }
            .font(Theme.ui(Theme.Size.meta))
        }
        .padding(15)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.mark, lineWidth: 1.5))
    }

    /// 只陈述事实，不评价。
    private var fact: String {
        L(.alertFact, breaker.alertAppName ?? L(.alertCurrentApp), breaker.alertMinutes)
    }
}
