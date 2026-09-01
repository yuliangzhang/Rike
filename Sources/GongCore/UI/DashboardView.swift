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
            .padding(24)
        }
        .background(Theme.inset)
        .task(id: store.record.date) { await loadWeek() }
    }

    private var gauges: some View {
        let totals = usage.map { UsageReducer.categoryTotals($0, settings: settings.settings) } ?? [:]
        let total = usage?.totalSeconds ?? 0
        return HStack(spacing: 1) {
            gauge(L(.dashTimeAtComputer), GongTime.formatDuration(total), nil)
            gauge(L(.catFocus), GongTime.formatDuration(totals[.focus] ?? 0), Theme.actual)
            gauge(L(.catNeutral), GongTime.formatDuration(totals[.neutral] ?? 0), Theme.plan)
            gauge(L(.catOther), GongTime.formatDuration(totals[.other] ?? 0), Theme.mark)
        }
        .background(Theme.rule)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
    }

    private func gauge(_ label: String, _ value: String, _ color: Color?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: label)
            Text(value).font(Theme.mono(Theme.Size.gauge, .semibold)).monospacedDigit()
                .foregroundStyle(color ?? Theme.ink)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
    }

    private var todayByApp: some View {
        Panel(title: L(.dashByApp)) {
            if let u = usage, !u.intervals.isEmpty {
                let rows = Array(u.totals().prefix(10))
                Chart(rows, id: \.bundleId) { row in
                    BarMark(
                        x: .value(L(.axisDuration), row.seconds / 60),
                        y: .value(L(.axisApp), row.name)
                    )
                    .foregroundStyle(Theme.categoryColor(settings.settings.category(for: row.bundleId)))
                }
                .chartXAxisLabel(L(.axisMinutes))
                .frame(height: CGFloat(max(130, rows.count * 28)))

                HStack(spacing: 16) {
                    legend(L(.catFocus), Theme.actual)
                    legend(L(.catNeutral), Theme.plan)
                    legend(L(.catOther), Theme.mark)
                    Spacer()
                    Text(L(.dashCategoryHint))
                        .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
                }
            } else {
                Explain(L(.dashNoData))
            }
            if usage?.truncated == true {
                Explain(L(.dashTruncated), color: Theme.mark)
            }
        }
    }

    private var weekChart: some View {
        Panel(title: L(.dashWeek)) {
            if weekDays.isEmpty {
                Explain(L(.dashNoWeekData))
            } else {
                Chart(weekDays, id: \.day) { d in
                    BarMark(x: .value(L(.axisDate), String(d.day.dropFirst(5))),
                            y: .value(L(.axisHours), d.seconds / 3600))
                        .foregroundStyle(Theme.plan.opacity(0.4))
                    BarMark(x: .value(L(.axisDate), String(d.day.dropFirst(5))),
                            y: .value(L(.axisFocusHours), d.focus / 3600))
                        .foregroundStyle(Theme.actual)
                }
                .chartYAxisLabel(L(.axisHours))
                .frame(height: 190)
                Explain(L(.dashWeekLegend))
            }
        }
    }

    private var limitationNote: some View {
        VStack(alignment: .leading, spacing: 7) {
            MicroLabel(text: L(.dashScopeTitle))
            Explain(L(.dashScopeBody))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.band)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(t).font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.muted)
        }
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
