import SwiftUI

/// 注意力阻断器。仪表只给事实（上次中断的日期），**不给连续天数**。
struct BreakerView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore
    @ObservedObject var breaker: BreakerEngine
    @ObservedObject var monitor: UsageMonitor

    @State private var newTrigger: Trigger = .n1
    @State private var newMinutes = ""
    @State private var newEscaping = ""

    var body: some View {
        ScrollView { pageContent }
            .background(Theme.inset)
            .task { await breaker.refreshGauges() }
    }

    var pageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            gauges
            hardRule
            procedure
            timerPanel
            logPanel
            triggerTable
        }
        .padding(24)
    }

    private var gauges: some View {
        HStack(spacing: 1) {
            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: L(.brkLastInterruption))
                Text(breaker.lastInterruptionLabel)
                    .font(Theme.mono(Theme.Size.gauge, .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)

            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: L(.brkLongestThisMonth))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(breaker.longestThisMonthMinutes.map { "\($0)" } ?? "—")
                        .font(Theme.mono(Theme.Size.gauge, .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.mark)
                    Text(L(.brkMinutesUnit))
                        .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
                }
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)

            VStack(alignment: .leading, spacing: 7) {
                MicroLabel(text: L(.brkOnlyTwo))
                Explain(L(.brkOnlyTwoBody))
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
        }
        .background(Theme.rule)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
    }

    private var hardRule: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: L(.brkHardRuleLabel), color: Theme.stop)
            Text(L(.brkHardRule)).font(Theme.ui(18, .bold)).foregroundStyle(Theme.ink)
            Explain(L(.brkHardRuleBody))
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stop.opacity(0.09))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.stop).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
    }

    private var procedure: some View {
        Panel(title: L(.brkProcedure)) {
            Explain(L(.brkProcedureBody))
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 13) {
                    Text(String(format: "%02d", i + 1))
                        .font(Theme.mono(Theme.Size.meta, .semibold)).foregroundStyle(Theme.stop)
                        .frame(width: 22, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(step.0)).font(Theme.ui(Theme.Size.body, .medium))
                            .foregroundStyle(Theme.ink)
                        Explain(L(step.1))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private static let steps: [(S, S)] = [
        (.brkStep1, .brkStep1Sub),
        (.brkStep2, .brkStep2Sub),
        (.brkStep3, .brkStep3Sub),
        (.brkStep4, .brkStep4Sub),
        (.brkStep5, .brkStep5Sub)
    ]

    private var timerPanel: some View {
        Panel(title: L(.brkTimer)) {
            HStack(alignment: .top, spacing: 22) {
                Text(breaker.timerLabel)
                    .font(Theme.mono(40, .semibold)).monospacedDigit()
                    .foregroundStyle(breaker.timerRunning ? Theme.mark
                                     : breaker.timerRemaining == 0 ? Theme.actual : Theme.ink)
                    .frame(minWidth: 130, alignment: .leading)
                Explain(L(.brkTimerBody))
                VStack(spacing: 7) {
                    Button(breaker.timerRunning ? L(.brkPause) : L(.brkStart)) {
                        breaker.timerRunning ? breaker.pauseTimer() : breaker.startTimer()
                    }
                    Button(L(.brkReset)) { breaker.resetTimer() }
                }
                .font(Theme.ui(Theme.Size.meta))
            }
        }
    }

    private var logPanel: some View {
        Panel(title: L(.brkLog)) {
            HStack(spacing: 11) {
                Picker("", selection: $newTrigger) {
                    ForEach(Trigger.allCases, id: \.self) { t in
                        Text("\(t.code) \(t.scene)").tag(t)
                    }
                }
                .labelsHidden().frame(width: 280)

                TextField(L(.brkMinutesField), text: $newMinutes)
                    .frame(width: 66).font(Theme.mono(Theme.Size.time))

                TextField(L(.brkEscapingPlaceholder), text: $newEscaping)
                    .font(Theme.ui(Theme.Size.body))

                Button(L(.brkRecord)) { logInterruption() }
                    .disabled(Int(newMinutes) == nil)
            }
            if !store.record.breaker.interruptions.isEmpty {
                Rectangle().fill(Theme.rule).frame(height: 1)
                ForEach(store.record.breaker.interruptions) { i in
                    HStack(spacing: 11) {
                        Text(i.trigger.code)
                            .font(Theme.mono(Theme.Size.label, .semibold)).foregroundStyle(Theme.mark)
                        Text(L(.brkMinutesCount, i.minutes))
                            .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.muted)
                        Text(i.escapingFrom)
                            .font(Theme.ui(Theme.Size.meta)).foregroundStyle(Theme.ink2)
                        Spacer()
                        Button(L(.delete)) {
                            store.mutate { $0.breaker.interruptions.removeAll { $0.id == i.id } }
                        }
                        .buttonStyle(.plain).font(Theme.ui(Theme.Size.label))
                        .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
    }

    private func logInterruption() {
        guard let m = Int(newMinutes) else { return }
        store.mutate { rec in
            rec.breaker.interruptions.append(
                Interruption(trigger: newTrigger, minutes: m, escapingFrom: newEscaping))
        }
        newMinutes = ""; newEscaping = ""
        Task { await breaker.refreshGauges() }
    }

    private var triggerTable: some View {
        Panel(title: L(.brkTriggerTable)) {
            ForEach(Trigger.allCases, id: \.self) { t in
                HStack(alignment: .top, spacing: 14) {
                    Text(t.code).font(Theme.mono(Theme.Size.meta, .semibold))
                        .foregroundStyle(t.rawValue.hasPrefix("n") ? Theme.mark : Theme.actual)
                        .frame(width: 38, alignment: .leading)
                    Text(t.scene).font(Theme.ui(Theme.Size.body)).foregroundStyle(Theme.ink2)
                    Spacer()
                }
            }
            Explain(L(.brkTriggerNote))
        }
    }

}
