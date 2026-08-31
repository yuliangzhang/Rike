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
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 无 Dock 图标的菜单栏应用；主窗口仍可成为 key window。
        NSApp.setActivationPolicy(.accessory)
        let c = AppCoordinator()
        coordinator = c
        Task { @MainActor in
            await c.start()
        }
    }

    /// 优雅退出路径：允许异步 shutdown（等待事件写入 drain、导出等），
    /// 完成后再回复系统。这是 Cocoa 的标准做法，也避免任何形式的主线程阻塞。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let c = coordinator, !isTerminating else { return .terminateNow }
        isTerminating = true
        Task { @MainActor in
            await c.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 兜底路径：注销/关机等场景可能跳过 applicationShouldTerminate。
        // 必须全同步 —— 这里已经在主线程上，若用 DispatchSemaphore 等待一个
        // @MainActor Task，那个 Task 永远拿不到主线程，就是死锁。
        MainActor.assumeIsolated {
            coordinator?.shutdownSynchronously()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in coordinator?.showMainWindow() }
        return true
    }
}
