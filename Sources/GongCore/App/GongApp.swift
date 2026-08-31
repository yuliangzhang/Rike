import SwiftUI
import AppKit

public struct GongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    public init() {}

    public var body: some Scene {
        // 窗口全部由 AppCoordinator 以 AppKit 方式管理（挂件必须是 NSPanel）。
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 无 Dock 图标的菜单栏应用；主窗口仍可成为 key window。
        NSApp.setActivationPolicy(.accessory)
        let c = AppCoordinator()
        coordinator = c
        Task { @MainActor in
            await c.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 同步等待落盘，避免退出时丢失最后一次编辑。
        guard let c = coordinator else { return }
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await c.shutdown()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 3)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in coordinator?.showMainWindow() }
        return true
    }
}
