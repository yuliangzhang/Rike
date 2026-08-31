import Foundation
import AppKit
import CoreGraphics

/// 前台应用监控。只写 append-only 事件日志，统计一律由 `UsageReducer` 重建。
///
/// 权限：`NSWorkspace` 前台应用通知与 `CGEventSource` 空闲检测**均不需要任何权限**。
/// 窗口标题细分（区分 Claude Code 与宿主终端）需要辅助功能权限，v1 不做。
@MainActor
final class UsageMonitor: ObservableObject {

    /// kCGAnyInputEventType：任意输入事件。具名常量，避免 `.init(rawValue: ~0)!` 这种不可读写法。
    private static let anyInputEvent = CGEventType(rawValue: UInt32.max)!

    @Published private(set) var isRunning = false
    @Published private(set) var currentBundleId: String?
    @Published private(set) var currentAppName: String?
    /// 当前应用连续在前台的开始时刻（用于阻断器阈值判断）。
    @Published private(set) var currentSince: Date?
    @Published private(set) var isIdle = false

    private let store = FileStore.shared
    private let runId = UUID().uuidString
    private var seq = 0

    private var heartbeatTimer: Timer?
    private var idleTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    var settingsProvider: () -> AppSettings = { AppSettings() }
    /// 事件写入后回调，供阻断器/UI 刷新。
    var onEvent: ((UsageEvent) -> Void)?

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        emit(.appStart)
        sampleFrontmost(reason: "start")
        subscribe()

        let s = settingsProvider()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(15, s.heartbeatSeconds)),
                                              repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit(.heartbeat) }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollIdle() }
        }
    }

    /// 同步停止：退出路径专用，appStop 事件直接落盘，不经过 Task。
    func stopSynchronously() {
        guard isRunning else { return }
        seq += 1
        let ev = UsageEvent(t: Date(), e: .appStop, runId: runId, seq: seq,
                            tz: TimeZone.current.identifier, bundleId: nil, name: nil)
        if let line = try? JSONEncoder.gongLine.encode(ev),
           var text = String(data: line, encoding: .utf8) {
            text.append("\n")
            let url = GongPaths.eventsFile(GongTime.dayKey(Date()))
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            if fd >= 0 {
                _ = text.withCString { Darwin.write(fd, $0, strlen($0)) }
                _ = fsync(fd)
                close(fd)
            }
        }
        teardown()
    }

    func stop() {
        guard isRunning else { return }
        emit(.appStop)
        teardown()
    }

    private func teardown() {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
        isRunning = false
        currentBundleId = nil
        currentSince = nil
    }

    // MARK: - 订阅（全部使用文档化 API）

    private func subscribe() {
        let center = NSWorkspace.shared.notificationCenter

        // handler 必须标 @Sendable：它被捕获进跨线程投递的通知闭包里。
        // 严格并发检查会拒绝非 Sendable 的函数值，这不是形式主义——
        // 通知可能在非主线程投递，再由 Task 跳回 MainActor。
        func observe(_ name: NSNotification.Name,
                     _ handler: @escaping @Sendable @MainActor () -> Void) {
            let o = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { @MainActor in handler() }
            }
            observers.append(o)
        }

        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] in
            self?.sampleFrontmost(reason: "activate")
        }
        observe(NSWorkspace.willSleepNotification)              { [weak self] in self?.emit(.sleep) }
        observe(NSWorkspace.didWakeNotification)                { [weak self] in
            self?.emit(.wake); self?.sampleFrontmost(reason: "wake")
        }
        observe(NSWorkspace.screensDidSleepNotification)        { [weak self] in self?.emit(.sleep) }
        observe(NSWorkspace.screensDidWakeNotification)         { [weak self] in
            self?.emit(.wake); self?.sampleFrontmost(reason: "screenWake")
        }
        observe(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.emit(.sessionInactive) }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.emit(.sessionActive); self?.sampleFrontmost(reason: "sessionActive")
        }
    }

    /// 启动 / 唤醒 / 会话恢复时都必须主动采样：
    /// `didActivateApplication` 只在切换时触发，不会告诉你「现在」是谁在前台。
    private func sampleFrontmost(reason: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bid = app.bundleIdentifier ?? "unknown.\(app.processIdentifier)"
        let name = app.localizedName ?? bid

        guard !GongPaths.isIgnored(bid) else { return }   // 过滤自身与系统瞬时进程
        guard bid != currentBundleId else { return }      // 未变则不重复记

        currentBundleId = bid
        currentAppName = name
        currentSince = Date()
        emit(.activate, bundleId: bid, name: name)
    }

    // MARK: - 空闲

    private func pollIdle() {
        let threshold = TimeInterval(max(30, settingsProvider().idleThresholdSeconds))
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState,
                                                           eventType: UsageMonitor.anyInputEvent)
        if idle >= threshold {
            if !isIdle {
                isIdle = true
                // 时间戳回溯到空闲真正开始的时刻；reducer 会用 (t, runId, seq) 放回正确位置
                emit(.idleStart, at: Date().addingTimeInterval(-idle))
                currentSince = nil
            }
        } else if isIdle {
            isIdle = false
            emit(.idleEnd)
            sampleFrontmost(reason: "idleEnd")
            if currentSince == nil { currentSince = Date() }
        }
    }

    // MARK: - 写事件

    private func emit(_ kind: UsageEvent.Kind,
                      at date: Date = Date(),
                      bundleId: String? = nil,
                      name: String? = nil) {
        guard settingsProvider().monitoringEnabled || kind == .appStop else { return }
        seq += 1
        let ev = UsageEvent(t: date, e: kind, runId: runId, seq: seq,
                            tz: TimeZone.current.identifier, bundleId: bundleId, name: name)
        onEvent?(ev)
        let url = GongPaths.eventsFile(GongTime.dayKey(date))
        Task.detached(priority: .utility) { [store] in
            try? await store.appendEvent(ev, to: url)
        }
    }

    /// 当前应用已连续在前台多久（秒）。空闲时为 0。
    var currentForegroundSeconds: TimeInterval {
        guard !isIdle, let since = currentSince else { return 0 }
        return Date().timeIntervalSince(since)
    }
}
