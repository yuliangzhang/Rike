import Foundation
import SwiftUI

/// 注意力阻断器。
///
/// 产品约束（不可协商）：
/// - **不显示连续天数**。连续天数是打卡计数器的变体，愧疚正是 N-1 触发器的燃料。
///   仪表只给「上次中断记录的日期」这个事实。
/// - **绝不使用系统模态弹窗**。只用非模态浮层 + 挂件描边变色。
@MainActor
final class BreakerEngine: ObservableObject {

    @Published private(set) var alertActive = false
    @Published private(set) var alertAppName: String?
    @Published private(set) var alertMinutes: Int = 0

    @Published private(set) var timerRemaining: Int = 600
    @Published private(set) var timerRunning = false

    /// 仪表：上次中断的**日期**（不是「已坚持 N 天」）。
    @Published private(set) var lastInterruptionDay: String?
    @Published private(set) var longestThisMonthMinutes: Int?

    private var snoozeUntil: Date?
    private var timer: Timer?
    private let store = FileStore.shared

    // MARK: - 主动触发

    /// 由 UI 定时调用。返回是否新触发。
    @discardableResult
    func evaluate(monitor: UsageMonitor, settings: AppSettings) -> Bool {
        guard settings.breakerEnabled, settings.monitoringEnabled else {
            clearAlert(); return false
        }
        if let s = snoozeUntil, Date() < s { return false }
        guard let bid = monitor.currentBundleId else { clearAlert(); return false }
        guard settings.category(for: bid) == .other else { clearAlert(); return false }

        let minutes = Int(monitor.currentForegroundSeconds / 60)
        guard minutes >= settings.breakerThresholdMinutes else { clearAlert(); return false }

        let wasActive = alertActive
        alertActive = true
        alertAppName = monitor.currentAppName
        alertMinutes = minutes
        return !wasActive
    }

    func clearAlert() {
        alertActive = false
        alertAppName = nil
        alertMinutes = 0
    }

    func snooze(minutes: Int) {
        snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        clearAlert()
    }

    // MARK: - 10 分钟延迟计时器

    func startTimer() {
        guard !timerRunning else { return }
        timerRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickTimer() }
        }
    }

    func pauseTimer() {
        timerRunning = false
        timer?.invalidate(); timer = nil
    }

    func resetTimer() {
        pauseTimer()
        timerRemaining = 600
    }

    private func tickTimer() {
        guard timerRemaining > 0 else { pauseTimer(); return }
        timerRemaining -= 1
        if timerRemaining == 0 { pauseTimer() }
    }

    var timerLabel: String {
        timerRemaining == 0 ? "结束"
            : String(format: "%d:%02d", timerRemaining / 60, timerRemaining % 60)
    }

    // MARK: - 仪表

    /// 扫描已有记录，取「上次中断日期」与「本月最长一次」。
    func refreshGauges() async {
        let keys = await store.listDayKeys()
        guard !keys.isEmpty else { return }

        let thisMonthPrefix = String(GongTime.dayKey(Date()).prefix(7))   // "2026-08"
        var lastDay: String?
        var longest = 0

        for k in keys.sorted().reversed() {
            guard let r = try? await store.read(DayRecord.self, from: GongPaths.dayFile(k)),
                  !r.breaker.interruptions.isEmpty else { continue }
            if lastDay == nil { lastDay = k }
            if k.hasPrefix(thisMonthPrefix) {
                longest = max(longest, r.breaker.interruptions.map(\.minutes).max() ?? 0)
            }
        }
        lastInterruptionDay = lastDay
        longestThisMonthMinutes = longest > 0 ? longest : nil
    }

    /// 事实陈述，不做连续天数。
    var lastInterruptionLabel: String {
        guard let d = lastInterruptionDay else { return "无记录" }
        return String(d.dropFirst(5))     // "08-25"
    }
}
