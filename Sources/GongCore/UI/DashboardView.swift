import SwiftUI
import Charts

/// 使用时长看板。**只用 macOS 14 就有的 Charts 子集**（Chart + BarMark）。
struct DashboardView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore

    @State private var weekDays: [(day: String, seconds: TimeInterval, focus: TimeInterval)] = []

    private var usage: UsageDay? { store.usage }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gauges
                todayByApp
                weekChart
                limitationNote
            }
            .padding(22)
        }
        .task(id: store.record.date) { await loadWeek() }
    }

    private var gauges: some View {
        let totals = usage.map { UsageReducer.categoryTotals($0, settings: settings.settings) } ?? [:]
        let total = usage?.totalSeconds ?? 0
        return HStack(spacing: 1) {
            gauge("今日在机时长", GongTime.formatDuration(total), nil)
            gauge("专注", GongTime.formatDuration(totals[.focus] ?? 0), Theme.actual)
            gauge("中性", GongTime.formatDuration(totals[.neutral] ?? 0), Theme.plan)
            gauge("其他", GongTime.formatDuration(totals[.other] ?? 0), Theme.warn)
        }
        .background(Theme.hairline)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func gauge(_ label: String, _ value: String, _ color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
            Text(value).font(Theme.monoSized(19, weight: .semibold))
                .foregroundStyle(color ?? .primary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var todayByApp: some View {
        panel("今日各应用时长") {
            if let u = usage, !u.intervals.isEmpty {
                let rows = Array(u.totals().prefix(10))
                Chart(rows, id: \.bundleId) { row in
                    BarMark(
                        x: .value("时长", row.seconds / 60),
                        y: .value("应用", row.name)
                    )
                    .foregroundStyle(Theme.categoryColor(settings.settings.category(for: row.bundleId)))
                }
                .chartXAxisLabel("分钟")
                .frame(height: CGFloat(max(120, rows.count * 26)))

                HStack(spacing: 16) {
                    legend("专注", Theme.actual)
                    legend("中性", Theme.plan)
                    legend("其他", Theme.warn)
                    Spacer()
                    Text("类别可在「设置」中逐个应用修改")
                        .font(Theme.monoSized(9)).foregroundStyle(.tertiary)
                }
            } else {
                Text("今天还没有监控数据。").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if usage?.truncated == true {
                Text("注：上次退出未正常结束，最后一段按最后心跳截断，可能少计几十秒。")
                    .font(Theme.monoSized(9)).foregroundStyle(Theme.warn)
            }
        }
    }

    private var weekChart: some View {
        panel("近 7 天") {
            if weekDays.isEmpty {
                Text("暂无数据。").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Chart(weekDays, id: \.day) { d in
                    BarMark(x: .value("日期", String(d.day.dropFirst(5))),
                            y: .value("小时", d.seconds / 3600))
                        .foregroundStyle(Theme.plan.opacity(0.45))
                    BarMark(x: .value("日期", String(d.day.dropFirst(5))),
                            y: .value("专注小时", d.focus / 3600))
                        .foregroundStyle(Theme.actual)
                }
                .chartYAxisLabel("小时")
                .frame(height: 180)
                Text("深色为专注时长，浅色为在机总时长。")
                    .font(Theme.monoSized(9)).foregroundStyle(.tertiary)
            }
        }
    }

    private var limitationNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("关于统计口径").font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
            Text("""
            Claude Code 运行在 Terminal / iTerm 里，系统层面看到的是宿主应用，因此统计为 Terminal。\
            要区分需要辅助功能权限读取窗口标题，本版本不做，也不会请求该权限。\
            前台应用统计与空闲检测均不需要任何系统权限。
            """)
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bandBG)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 9, height: 9)
            Text(t).font(Theme.monoSized(9)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func panel<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .bold))
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func loadWeek() async {
        let store2 = FileStore.shared
        let key = store.record.key
        guard let base = GongTime.date(fromDayKey: key.date, timeZone: key.timeZone) else { return }
        var rows: [(String, TimeInterval, TimeInterval)] = []

        for offset in stride(from: -6, through: 0, by: 1) {
            guard let d = key.calendar.date(byAdding: .day, value: offset, to: base) else { continue }
            let dk = DayKey(d, timeZone: key.timeZone)
            var events: [UsageEvent] = []
            for needed in UsageReducer.requiredDayKeys(for: dk) {
                if let e = try? await store2.readEvents(from: GongPaths.eventsFile(needed)) {
                    events.append(contentsOf: e)
                }
            }
            guard !events.isEmpty else { continue }
            let day = UsageReducer.reduce(events: events, for: dk,
                                          liveNow: dk.date == GongTime.dayKey(Date()) ? Date() : nil)
            let cat = UsageReducer.categoryTotals(day, settings: settings.settings)
            rows.append((dk.date, day.totalSeconds, cat[.focus] ?? 0))
        }
        weekDays = rows.map { (day: $0.0, seconds: $0.1, focus: $0.2) }
    }
}
