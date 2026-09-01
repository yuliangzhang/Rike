import SwiftUI

/// 桌面挂件内容。**不承载任何文本编辑**——点击即打开主窗口。
struct WidgetView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var breaker: BreakerEngine
    var onOpenMain: () -> Void

    private var topThree: [Todo] { Array(store.record.widgetTodos.prefix(3)) }
    private var hasMore: Bool { store.record.widgetTodos.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.beam).frame(height: 2)
            VStack(alignment: .leading, spacing: 8) {
                if topThree.isEmpty {
                    Text(L(.widgetEmpty)).font(Theme.ui(Theme.Size.meta)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(topThree) { t in todoLine(t) }
                }
                Rectangle().fill(Theme.rule).frame(height: 1).padding(.vertical, 2)
                currentBlockLine
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 288)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(breaker.alertActive ? Theme.mark : Theme.rule,
                              lineWidth: breaker.alertActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onTapGesture(perform: onOpenMain)
        .help(L(.widgetTapHelp))
    }

    private var header: some View {
        HStack {
            Text(String(store.record.key.date.dropFirst(5)) + " " +
                 GongTime.weekdayLabel(dayKey: store.record.key.date, lang: UILang.current))
                .font(Theme.mono(Theme.Size.meta)).monospacedDigit()
                .foregroundStyle(Theme.ink2)
            Spacer()
            // 溢出时给一个中性的可发现入口，但不显示「还有 N 条」（那是压力，不是信息）
            if hasMore {
                Text("⋯").font(Theme.mono(Theme.Size.meta)).foregroundStyle(Theme.muted)
                    .help(L(.widgetMore))
            }
            GongMark(size: 13)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.band)
    }

    private func todoLine(_ t: Todo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(t.kind.marker)
                .font(Theme.mono(Theme.Size.meta, .medium))
                .foregroundStyle(t.kind == .floor ? Theme.actual
                                 : t.kind == .mit ? Theme.mark : Theme.faint)
                .frame(width: 13)
            Text(t.text.isEmpty ? L(.emptyBrackets) : t.text)
                .font(Theme.ui(Theme.Size.body))
                .foregroundStyle(t.status == .done ? Theme.muted : Theme.ink)
                .strikethrough(t.status == .done, color: Theme.faint)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var currentBlockLine: some View {
        Group {
            if let blk = currentPlanned {
                Text("\(blk.rangeLabel)　\(blk.title)")
                    .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.plan).lineLimit(1)
            } else if let app = monitor.currentAppName {
                Text(L(.widgetCurrent, app))
                    .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.muted).lineLimit(1)
            } else {
                Text("—").font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var currentPlanned: PlannedBlock? {
        let cal = store.record.key.calendar
        let now = Date()
        let m = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return store.record.planned.first { $0.startMinute <= m && m < $0.endMinute }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let u = store.usage {
                let totals = UsageReducer.categoryTotals(u, settings: settings.settings)
                Text(L(.widgetFocus, GongTime.formatDuration(totals[.focus] ?? 0)))
                    .foregroundStyle(Theme.actual)
                Text(L(.widgetOther, GongTime.formatDuration(totals[.other] ?? 0)))
                    .foregroundStyle(Theme.mark)
            } else {
                Text(L(.widgetMonitorOff)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
        .font(Theme.mono(Theme.Size.label))
    }
}
