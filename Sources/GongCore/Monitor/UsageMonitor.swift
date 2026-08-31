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
    /// 串行写入链，保证事件按顺序落盘且退出前可等待。
    private var writeChain: Task<Void, Never>?
    /// 每入队一条事件递增，用于判断 drain 期间是否又有新事件排进来。
    private var writeGeneration: Int = 0

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
        observe(NSWorkspace.willSleepNotification)              { [weak self] in self?.suspend(.sleep) }
        observe(NSWorkspace.didWakeNotification)                { [weak self] in
            self?.resume(reason: "wake")
        }
        observe(NSWorkspace.screensDidSleepNotification)        { [weak self] in self?.suspend(.sleep) }
        observe(NSWorkspace.screensDidWakeNotification)         { [weak self] in
            self?.resume(reason: "screenWake")
        }
        observe(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.suspend(.sessionInactive) }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.resume(reason: "sessionActive", kind: .sessionActive)
        }
    }

    /// 恢复：唤醒 / 会话激活。重新采样并把连续前台的起点重置为**现在**。
    private func resume(reason: String, kind: UsageEvent.Kind = .wake) {
        emit(kind)
        currentBundleId = nil        // 强制下一次采样重新记一条 activate
        sampleFrontmost(reason: reason)
        if currentSince == nil, currentBundleId != nil { currentSince = Date() }
    }

    /// 挂起：睡眠 / 锁屏 / 会话失活。
    /// **必须清掉 currentSince** —— 否则睡了 8 小时醒来，阻断器会把这 8 小时
    /// 当成「连续前台 480 分钟」并立刻误报。
    private func suspend(_ kind: UsageEvent.Kind) {
        emit(kind)
        currentSince = nil
    }

    /// 启动 / 唤醒 / 会话恢复时都必须主动采样：
    /// `didActivateApplication` 只在切换时触发，不会告诉你「现在」是谁在前台。
    private func sampleFrontmost(reason: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bid = app.bundleIdentifier ?? "unknown.\(app.processIdentifier)"
        let name = app.localizedName ?? bid

        guard bid != currentBundleId else { return }      // 未变则不重复记

        if GongPaths.isIgnored(bid) {
            // 关键：**仍然要写事件**。若在这里直接 return，用户点开 Gong 或控制中心
            // 待上 20 分钟，reducer 看不到边界，那 20 分钟会全部算给上一个应用。
            // 写进去，由 reducer 的过滤逻辑闭合区间并把 currentApp 置空。
            currentBundleId = nil
            currentAppName = nil
            currentSince = nil
            emit(.activate, bundleId: bid, name: name)
            return
        }

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
        // stop 之后仍可能有已排队的 timer / 通知闭包执行到这里。
        // 除 appStop 外一律丢弃，否则会写出「appStop 之后还有事件」的日志。
        guard isRunning || kind == .appStop else { return }
        guard settingsProvider().monitoringEnabled || kind == .appStop else { return }
        seq += 1
        let ev = UsageEvent(t: date, e: kind, runId: runId, seq: seq,
                            tz: TimeZone.current.identifier, bundleId: bundleId, name: name)
        onEvent?(ev)
        enqueueWrite(ev)
    }

    /// 事件写入必须**串行且可等待**。
    /// 原来用 `Task.detached` 各写各的：既不保证落盘顺序，`stop()` 也不等它们完成，
    /// 正常退出时最后的 appStop 事件可能丢掉。
    private func enqueueWrite(_ ev: UsageEvent) {
        writeGeneration += 1
        let previous = writeChain
        writeChain = Task { [store] in
            _ = await previous?.result
            let url = GongPaths.eventsFile(GongTime.dayKey(ev.t))
            try? await store.appendEvent(ev, to: url)
        }
    }

    /// 等待已排队的事件全部落盘。
    /// 循环到链尾稳定：等待期间可能又有闭包 enqueue 出新的一节。
    func drainWrites() async {
        for _ in 0..<10 {
            let mark = writeGeneration
            guard let chain = writeChain else { return }
            _ = await chain.result
            if writeGeneration == mark { return }   // 等待期间没有新事件入队，说明排空了
        }
    }

    /// 当前应用已连续在前台多久（秒）。空闲时为 0。
    var currentForegroundSeconds: TimeInterval {
        guard !isIdle, let since = currentSince else { return 0 }
        return Date().timeIntervalSince(since)
    }
}
