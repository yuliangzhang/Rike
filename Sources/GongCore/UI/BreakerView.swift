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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                gauges
                hardRule
                procedure
                timerPanel
                logPanel
                triggerTable
            }
            .padding(22)
        }
        .task { await breaker.refreshGauges() }
    }

    private var gauges: some View {
        HStack(spacing: 1) {
            VStack(alignment: .leading, spacing: 5) {
                Text("上次中断记录").font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
                Text(breaker.lastInterruptionLabel).font(Theme.monoSized(24, weight: .semibold))
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))

            VStack(alignment: .leading, spacing: 5) {
                Text("本月最长一次").font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
                Text(breaker.longestThisMonthMinutes.map { "\($0)" } ?? "—")
                    .font(Theme.monoSized(24, weight: .semibold)).foregroundStyle(Theme.warn)
                Text("分钟").font(Theme.monoSized(9)).foregroundStyle(.tertiary)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))

            VStack(alignment: .leading, spacing: 5) {
                Text("只看这两个数").font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
                Text("第二个数在下降就是在赢。这里给的是日期，不是连续天数——连续天数是打卡计数器的变体。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(Theme.hairline)
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var hardRule: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("唯一的硬规则").font(Theme.monoSized(9)).foregroundStyle(Theme.stop).tracking(1)
            Text("任何一次中断，不许跨过一次睡眠。").font(.system(size: 16, weight: .bold))
            Text("跨日自动归零，不做连续天数展示——愧疚是 N-1 触发器的燃料。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.stop.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.stop).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var procedure: some View {
        panel("30 秒断路程序") {
            Text("已经开始下滑时，按顺序做，不要先跟自己讲道理。跟渴望辩论必输。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 11) {
                    Text(String(format: "%02d", i + 1))
                        .font(Theme.monoSized(11, weight: .semibold)).foregroundStyle(Theme.stop)
                        .frame(width: 20, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.0).font(.system(size: 12, weight: .medium))
                        Text(s.1).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static let steps: [(String, String)] = [
        ("站起来，离开这个房间", "先改变身体状态，不是先改变想法。"),
        ("手机／平板放到另一个房间", "不是抽屉，是另一个房间。"),
        ("出门走 10 分钟，或洗把冷水脸、吃点东西", "目标是打断状态，不是说服自己。"),
        ("写一句：我刚才真正想逃开的是 ___", "把迷雾变成对象。你逃的是无边界，不是难。"),
        ("做那件事的 5 分钟版本，然后允许自己停", "让开放回路挂回工作上，而不是挂在下一章。")
    ]

    private var timerPanel: some View {
        panel("10 分钟延迟计时器") {
            HStack(spacing: 20) {
                Text(breaker.timerLabel)
                    .font(Theme.monoSized(38, weight: .semibold))
                    .foregroundStyle(breaker.timerRunning ? Theme.warn
                                     : breaker.timerRemaining == 0 ? Theme.actual : .primary)
                    .frame(minWidth: 120, alignment: .leading)
                Text("想打开的那一刻，先按开始。渴望是一条会自己落下去的曲线，通常十几分钟就过峰。十分钟后你还想看，那就去看——但那时是你在决定。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    Button(breaker.timerRunning ? "暂停" : "开始") {
                        breaker.timerRunning ? breaker.pauseTimer() : breaker.startTimer()
                    }
                    Button("重置") { breaker.resetTimer() }
                }
            }
        }
    }

    private var logPanel: some View {
        panel("记一笔（中性记录，不写评价）") {
            HStack(spacing: 10) {
                Picker("", selection: $newTrigger) {
                    ForEach(Trigger.allCases, id: \.self) { t in
                        Text("\(t.code) \(t.scene)").tag(t)
                    }
                }
                .labelsHidden().frame(width: 260)

                TextField("分钟", text: $newMinutes)
                    .frame(width: 60).font(Theme.monoSized(11))

                TextField("真正想逃开的是…", text: $newEscaping)
                    .font(.system(size: 12))

                Button("记录") { logInterruption() }
                    .disabled(Int(newMinutes) == nil)
            }
            if !store.record.breaker.interruptions.isEmpty {
                Divider().overlay(Theme.hairline)
                ForEach(store.record.breaker.interruptions) { i in
                    HStack(spacing: 10) {
                        Text(i.trigger.code).font(Theme.monoSized(10)).foregroundStyle(Theme.warn)
                        Text("\(i.minutes) 分钟").font(Theme.monoSized(10)).foregroundStyle(.secondary)
                        Text(i.escapingFrom).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("删除") {
                            store.mutate { $0.breaker.interruptions.removeAll { $0.id == i.id } }
                        }
                        .buttonStyle(.plain).font(Theme.monoSized(9)).foregroundStyle(.tertiary)
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
        panel("触发器对照") {
            ForEach(Trigger.allCases, id: \.self) { t in
                HStack(alignment: .top, spacing: 12) {
                    Text(t.code).font(Theme.monoSized(10, weight: .semibold))
                        .foregroundStyle(t.rawValue.hasPrefix("n") ? Theme.warn : Theme.actual)
                        .frame(width: 34, alignment: .leading)
                    Text(t.scene).font(.system(size: 12))
                    Spacer()
                }
            }
            Text("V-1 / V-2 可由监控自动检测：「其他」类应用连续前台超过设定阈值时，挂件描边变色并出现非模态提示。绝不使用系统模态弹窗。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
}
