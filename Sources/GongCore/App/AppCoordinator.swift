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

    // MARK: - 启动

    func start() async {
        await settingsStore.load()
        dayStore.settingsProvider = { [settingsStore] in settingsStore.settings }
        monitor.settingsProvider = { [settingsStore] in settingsStore.settings }

        await dayStore.load(dayKey: DayKey(Date()))
        await breaker.refreshGauges()

        installStatusItem()
        if settingsStore.settings.widgetVisible { showWidget() }
        if settingsStore.settings.monitoringEnabled { monitor.start() }

        uiTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        await pruneOldLogs()
    }

    func shutdown() async {
        uiTimer?.invalidate()
        monitor.stop()
        await dayStore.saveNow()
        await settingsStore.saveNow()
    }

    /// 供 `applicationWillTerminate` 调用：全同步，不涉及任何 await。
    func shutdownSynchronously() {
        uiTimer?.invalidate()
        uiTimer = nil
        monitor.stopSynchronously()
        dayStore.saveSynchronouslyForTermination()
        settingsStore.saveSynchronouslyForTermination()
    }

    private func tick() {
        dayStore.reloadUsage()
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

    // MARK: - 菜单栏

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "工"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开主窗口", action: #selector(openMain), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "把挂件提到最前", action: #selector(bringWidgetForward), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "显示／隐藏挂件", action: #selector(toggleWidget), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "立即导出今天", action: #selector(exportToday), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Gong", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
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
            let panel = NSPanel(contentRect: NSRect(x: 120, y: 240, width: 268, height: 210),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.hidesOnDeactivate = false

            let view = WidgetView(store: dayStore, settings: settingsStore,
                                  monitor: monitor, breaker: breaker) { [weak self] in
                self?.showMainWindow()
            }
            let host = NSHostingView(rootView: view)
            host.frame = panel.contentLayoutRect
            panel.contentView = host
            panel.setContentSize(host.fittingSize)

            if let f = settingsStore.settings.widgetFrame {
                panel.setFrameOrigin(NSPoint(x: f.x, y: f.y))
            }
            widgetPanel = panel
            NotificationCenter.default.addObserver(
                self, selector: #selector(widgetMoved),
                name: NSWindow.didMoveNotification, object: panel)
        }
        applyWidgetMode(settingsStore.settings.widgetMode)
        widgetPanel?.orderFrontRegardless()
    }

    func hideWidget() { widgetPanel?.orderOut(nil) }

    @objc private func widgetMoved() {
        guard let f = widgetPanel?.frame else { return }
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
                onWidgetVisibilityChange: { [weak self] v in self?.setWidgetVisible(v) })

            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "工字表 Gong"
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
