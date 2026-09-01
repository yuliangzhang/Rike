import SwiftUI
import AppKit

/// 统一持有挂件面板 / 主窗口 / 提示浮层，所有打开动作走同一入口，杜绝重复创建。
@MainActor
final class AppCoordinator: NSObject, ObservableObject {

    let dayStore = DayStore()
    let settingsStore = SettingsStore()
    let monitor = UsageMonitor()
    let breaker = BreakerEngine()

    private var widgetPanel: NSPanel?
    private var mainWindow: NSWindow?
    private var alertPanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var uiTimer: Timer?
    private var moveObserver: NSObjectProtocol?
    private var isProgrammaticMove = false
    /// 上一次已知的监控开关状态，用于驱动 monitor 的启停。
    private var lastMonitoringEnabled: Bool = true

    // MARK: - 启动

    func start() async {
        await settingsStore.load()
        applyAppearance(settingsStore.settings.appearance)
        dayStore.settingsProvider = { [settingsStore] in settingsStore.settings }
        monitor.settingsProvider = { [settingsStore] in settingsStore.settings }

        await dayStore.load(dayKey: DayKey(Date()))
        await breaker.refreshGauges()

        installStatusItem()
        if settingsStore.settings.widgetVisible { showWidget() }
        lastMonitoringEnabled = settingsStore.settings.monitoringEnabled
        if lastMonitoringEnabled { monitor.start() }

        uiTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        await pruneOldLogs()
    }

    func shutdown() async {
        uiTimer?.invalidate()
        uiTimer = nil
        monitor.stop()
        await monitor.drainWrites()      // 等最后的 appStop 事件真正落盘
        _ = await dayStore.saveNow()
        await settingsStore.saveNow()
        removeObservers()
    }

    /// 供 `applicationWillTerminate` 调用：全同步，不涉及任何 await。
    func shutdownSynchronously() {
        uiTimer?.invalidate()
        uiTimer = nil
        removeObservers()
        monitor.stopSynchronously()
        dayStore.saveSynchronouslyForTermination()
        settingsStore.saveSynchronouslyForTermination()
    }

    private func tick() {
        syncMonitorLifecycle()
        dayStore.reloadUsage()
        resizeWidgetToFit()
        // 跨日：自动切到新的一天，阻断器状态随之归零（「不许跨过一次睡眠」）
        let today = GongTime.dayKey(Date())
        if dayStore.record.date != today, mainWindow?.isVisible != true {
            Task { await dayStore.load(dayKey: DayKey(Date())) }
        }
        if breaker.evaluate(monitor: monitor, settings: settingsStore.settings) {
            showAlertPanel()
        } else if !breaker.alertActive {
            hideAlertPanel()
        }
        updateStatusItemTitle()
    }

    /// 设置里的「启用监控」必须**立即**启停 monitor。
    /// 靠 20 秒轮询只是把问题延迟，用户关掉开关后定时器和订阅还会继续活一会儿。
    func setMonitoring(_ enabled: Bool) {
        guard enabled != lastMonitoringEnabled else { return }
        lastMonitoringEnabled = enabled
        if enabled { monitor.start() } else { monitor.stop() }
    }

    /// 兜底：设置也可能被别的路径改动，轮询作为二重保险。
    private func syncMonitorLifecycle() {
        setMonitoring(settingsStore.settings.monitoringEnabled)
    }

    /// 挂件内容会变（0 条 TODO ↔ 3 条），面板尺寸必须跟着 SwiftUI 的固有尺寸走，
    /// 否则要么裁切要么留白。
    private func resizeWidgetToFit() {
        // 用户正按着鼠标（很可能在拖挂件）时不要动它，否则会跟用户抢位置
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard let panel = widgetPanel, panel.isVisible, let host = panel.contentView else { return }
        let fitting = host.fittingSize
        guard fitting.height > 1,
              abs(panel.frame.height - fitting.height) > 1 ||
              abs(panel.frame.width - fitting.width) > 1 else { return }
        // 保持左上角不动地改尺寸，避免挂件在屏幕上跳。
        // 这是程序性移动，不应被当成用户拖动而写进设置。
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        isProgrammaticMove = true
        panel.setContentSize(fitting)
        panel.setFrameTopLeftPoint(topLeft)
        isProgrammaticMove = false
    }

    // MARK: - 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "工"
        let menu = NSMenu()
        menu.addItem(withTitle: L(.menuOpenMain), action: #selector(openMain), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: L(.menuBringWidgetFront),
                     action: #selector(bringWidgetForward), keyEquivalent: "").target = self
        menu.addItem(withTitle: L(.menuToggleWidget),
                     action: #selector(toggleWidget), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L(.menuExportToday),
                     action: #selector(exportToday), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L(.menuQuit, L(.appName)),
                     action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    /// 语言变了要刷新 AppKit 那一侧。
    ///
    /// SwiftUI 视图会因为 SettingsStore 发布而自己重绘，但 AppKit 的这两处不会：
    /// NSMenu 的标题是构建时定死的字符串，NSWindow.title 是赋值一次的属性。
    /// 漏掉它们的话，切到英文后菜单栏和窗口标题会一直留在中文。
    func applyLanguage() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            installStatusItem()
            updateStatusItemTitle()
        }
        mainWindow?.title = L(.appName)
    }

    /// 应用外观偏好。改 NSApp.appearance 后，Theme 里所有动态色会一起解析成对应外观。
    ///
    /// 桌面挂件的 NSPanel 没有自己设 appearance，会继承 NSApp 的；
    /// 但显式赋一次更稳妥——面板是在 applyAppearance 之后才创建的路径也存在。
    func applyAppearance(_ pref: AppearancePreference) {
        NSApp.appearance = pref.nsAppearance
        widgetPanel?.appearance = pref.nsAppearance
        mainWindow?.appearance = pref.nsAppearance
    }

    private func updateStatusItemTitle() {
        statusItem?.button?.title = breaker.alertActive ? "工•" : "工"
    }

    @objc private func openMain() { showMainWindow() }
    @objc private func toggleWidget() {
        settingsStore.settings.widgetVisible.toggle()
        settingsStore.settings.widgetVisible ? showWidget() : hideWidget()
    }
    @objc private func exportToday() { Task { await dayStore.exportNow(); showMainWindow() } }
    @objc private func quit() {
        Task { await shutdown(); NSApp.terminate(nil) }
    }

    @objc func bringWidgetForward() {
        guard let p = widgetPanel else { showWidget(); return }
        let saved = p.level
        p.level = .floating
        p.orderFrontRegardless()
        // 2 秒后回落，既「一眼看到」又不长期挡路
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            p.level = self.settingsStore.settings.widgetMode == .floating ? .floating : saved
            self.applyWidgetMode(self.settingsStore.settings.widgetMode)
        }
    }

    // MARK: - 挂件

    func showWidget() {
        if widgetPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 120, y: 240, width: 288, height: 215),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            // 面板是在 start() 的 applyAppearance 之后才创建的，那次赋值对它是空操作。
            // 不设也会继承 NSApp.appearance，但显式赋一次不依赖继承行为。
            panel.appearance = settingsStore.settings.appearance.nsAppearance

            let view = WidgetView(store: dayStore, settings: settingsStore,
                                  monitor: monitor, breaker: breaker) { [weak self] in
                self?.showMainWindow()
            }
            let host = NSHostingView(rootView: view)
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            panel.setContentSize(host.fittingSize)

            if let f = settingsStore.settings.widgetFrame {
                panel.setFrameOrigin(NSPoint(x: f.x, y: f.y))
            }
            widgetPanel = panel
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.widgetMoved() }
                }
        }
        applyWidgetMode(settingsStore.settings.widgetMode)
        widgetPanel?.orderFrontRegardless()
    }

    func hideWidget() { widgetPanel?.orderOut(nil) }

    private func removeObservers() {
        if let o = moveObserver { NotificationCenter.default.removeObserver(o) }
        moveObserver = nil
    }

    private func widgetMoved() {
        guard !isProgrammaticMove, let f = widgetPanel?.frame else { return }
        settingsStore.settings.widgetFrame =
            AppSettings.WidgetFrame(x: f.origin.x, y: f.origin.y, width: f.width, height: f.height)
    }

    /// 桌面层是 best-effort：Apple 只保证层级前后关系，
    /// Stage Manager / 全屏 / Mission Control 下不保证一致。故提供 floating 兜底。
    func applyWidgetMode(_ mode: WidgetMode) {
        guard let p = widgetPanel else { return }
        switch mode {
        case .desktop:
            p.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating:
            p.level = .floating
        }
    }

    func setWidgetVisible(_ visible: Bool) { visible ? showWidget() : hideWidget() }

    // MARK: - 主窗口（普通 NSWindow + 显式激活）

    func showMainWindow() {
        if mainWindow == nil {
            let view = MainWindowView(
                store: dayStore, settings: settingsStore, monitor: monitor, breaker: breaker,
                onWidgetModeChange: { [weak self] m in self?.applyWidgetMode(m) },
                onWidgetVisibilityChange: { [weak self] v in self?.setWidgetVisible(v) },
                onMonitoringChange: { [weak self] on in self?.setMonitoring(on) },
                onAppearanceChange: { [weak self] p in self?.applyAppearance(p) },
                onLanguageChange: { [weak self] _ in self?.applyLanguage() })

            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = L(.appName)
            w.appearance = settingsStore.settings.appearance.nsAppearance
            w.contentView = NSHostingView(rootView: view)
            w.center()
            w.isReleasedWhenClosed = false
            mainWindow = w
        }
        // accessory 策略下不会自动获得 key window，必须显式激活
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - 非模态提示浮层

    private func showAlertPanel() {
        if alertPanel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 140),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.isMovableByWindowBackground = true

            let view = BreakerAlertView(breaker: breaker, settings: settingsStore) { [weak self] in
                self?.logAutoInterruption()
            } onOpenMain: { [weak self] in
                self?.breaker.clearAlert()
                self?.hideAlertPanel()
                self?.showMainWindow()
            }
            let host = NSHostingView(rootView: view)
            p.contentView = host
            p.setContentSize(host.fittingSize)
            if let screen = NSScreen.main {
                p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 320,
                                         y: screen.visibleFrame.maxY - 180))
            }
            alertPanel = p
        }
        alertPanel?.orderFrontRegardless()
    }

    private func hideAlertPanel() { alertPanel?.orderOut(nil) }

    private func logAutoInterruption() {
        let minutes = breaker.alertMinutes
        dayStore.mutate { rec in
            rec.breaker.interruptions.append(
                Interruption(trigger: .v2, minutes: minutes, autoDetected: true))
        }
        breaker.snooze(minutes: settingsStore.settings.breakerSnoozeMinutes)
        hideAlertPanel()
        Task { await breaker.refreshGauges() }
    }

    // MARK: - 日志清理

    private func pruneOldLogs() async {
        let days = settingsStore.settings.rawLogRetentionDays
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        guard let cutoff else { return }
        let cutoffKey = GongTime.dayKey(cutoff)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: GongPaths.eventsDir.path) else { return }
        for f in files where f.hasSuffix(".ndjson") {
            let key = String(f.dropLast(7))
            if key < cutoffKey {
                try? await FileStore.shared.removeItem(at: GongPaths.eventsDir.appendingPathComponent(f))
            }
        }
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(withTitle title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        addItem(item)
        return item
    }
}
