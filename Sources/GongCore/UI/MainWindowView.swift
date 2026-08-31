import SwiftUI

struct MainWindowView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var breaker: BreakerEngine

    var onWidgetModeChange: (WidgetMode) -> Void
    var onWidgetVisibilityChange: (Bool) -> Void

    @State private var tab: Tab = .gong

    enum Tab: String, CaseIterable, Identifiable {
        case gong = "工字表", dash = "看板", breaker = "阻断器", settings = "设置"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            if let n = store.notice { noticeBar(n) }

            Divider().overlay(Theme.hairline)

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
                             onWidgetVisibilityChange: onWidgetVisibilityChange)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    private func noticeBar(_ n: DayStore.Notice) -> some View {
        HStack(spacing: 10) {
            Text(n.text).font(.system(size: 11))
                .foregroundStyle(n.level == .warning ? Theme.warn : Color.secondary)
            Spacer()
            Button("知道了") { store.dismissNotice() }
                .buttonStyle(.plain).font(Theme.monoSized(10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
        .background((n.level == .warning ? Theme.warn : Color.secondary).opacity(0.1))
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
                Text("工").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.warn)
                Text(fact).font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    breaker.snooze(minutes: settings.settings.breakerSnoozeMinutes)
                } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
            }

            Text("站起来，离开这个房间。先改变身体状态，不是先改变想法。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("记一笔") { onLog() }
                Button("打开断路程序") { onOpenMain() }
                Button("忽略 \(settings.settings.breakerSnoozeMinutes) 分钟") {
                    breaker.snooze(minutes: settings.settings.breakerSnoozeMinutes)
                }
            }
            .font(.system(size: 11))
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.warn, lineWidth: 1.5))
    }

    /// 只陈述事实，不评价。
    private var fact: String {
        let app = breaker.alertAppName ?? "当前应用"
        return "\(app) 已连续 \(breaker.alertMinutes) 分钟"
    }
}
