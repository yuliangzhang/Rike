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
            Divider().overlay(Theme.hairline)
            VStack(alignment: .leading, spacing: 7) {
                if topThree.isEmpty {
                    Text("今天还没有记录").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    ForEach(topThree) { t in todoLine(t) }
                }
                Divider().overlay(Theme.hairline).padding(.vertical, 1)
                currentBlockLine
                footer
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 268)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(breaker.alertActive ? Theme.warn : Theme.hairline,
                              lineWidth: breaker.alertActive ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onTapGesture(perform: onOpenMain)
        .help("点击打开主窗口")
    }

    private var header: some View {
        HStack {
            Text(String(store.record.key.date.dropFirst(5)) + " " +
                 GongTime.weekdayLabel(dayKey: store.record.key.date))
                .font(Theme.monoSized(11))
            Spacer()
            // 溢出时给一个中性的可发现入口，但不显示「还有 N 条」（那是压力，不是信息）
            if hasMore {
                Text("⋯").font(Theme.monoSized(11)).foregroundStyle(.secondary)
                    .help("还有更多，点击打开主窗口")
            }
            Text("工").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.plan)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bandBG)
    }

    private func todoLine(_ t: Todo) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(t.kind.marker)
                .font(Theme.monoSized(11))
                .foregroundStyle(t.kind == .floor ? Theme.actual
                                 : t.kind == .mit ? Theme.warn : Color.secondary)
                .frame(width: 12)
            Text(t.text.isEmpty ? "（空）" : t.text)
                .font(.system(size: 12))
                .foregroundStyle(t.status == .done ? .secondary : .primary)
                .strikethrough(t.status == .done, color: .secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var currentBlockLine: some View {
        Group {
            if let blk = currentPlanned {
                Text("\(blk.rangeLabel)　\(blk.title)")
                    .font(Theme.monoSized(10)).foregroundStyle(Theme.plan).lineLimit(1)
            } else if let app = monitor.currentAppName {
                Text("当前：\(app)")
                    .font(Theme.monoSized(10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("—").font(Theme.monoSized(10)).foregroundStyle(.tertiary)
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
                Text("● 专注 \(GongTime.formatDuration(totals[.focus] ?? 0))")
                    .foregroundStyle(Theme.actual)
                Text("○ 其他 \(GongTime.formatDuration(totals[.other] ?? 0))")
                    .foregroundStyle(Theme.warn)
            } else {
                Text("监控未启用").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .font(Theme.monoSized(9))
    }
}
