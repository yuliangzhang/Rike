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
        // 必须全同步。这里已经在主线程上，若用 DispatchSemaphore 等待一个
        // @MainActor Task，那个 Task 永远拿不到主线程 —— 死锁，最后的编辑会丢。
        MainActor.assumeIsolated {
            coordinator?.shutdownSynchronously()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in coordinator?.showMainWindow() }
        return true
    }
}
