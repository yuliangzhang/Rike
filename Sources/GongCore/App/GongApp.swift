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

    /// 退出：**全同步做完，直接 terminateNow。**
    ///
    /// 原来走的是 Cocoa 的标准异步套路：返回 `.terminateLater`，
    /// 起一个 `Task { @MainActor }` 做 shutdown，完成后 `reply(true)`。
    /// 那套路的前提是「主线程在等 reply 期间还能跑 MainActor 的任务」，
    /// 而这个前提在这里**不成立**——只要 terminate 是从任何一个 MainActor 任务里
    /// 同步调起来的，MainActor 就被那个任务占着，reply 的任务永远排不上号，
    /// 于是卡在嵌套事件循环里：图标还在、窗口还在、点退出没反应。
    ///
    /// 这里不再赌那个前提。`shutdownSynchronously()` 本来就是为
    /// `applicationWillTerminate` 写的全同步路径，`monitor.stopSynchronously()`
    /// 会把 appStop 直接 write + fsync 落盘，两个 store 也各有同步落盘函数。
    /// 该做的事一件不少，而且**不可能死锁**。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        MainActor.assumeIsolated { coordinator?.shutdownSynchronously() }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 兜底路径：注销/关机等场景可能跳过 applicationShouldTerminate。
        // 必须全同步 —— 这里已经在主线程上，若用 DispatchSemaphore 等待一个
        // @MainActor Task，那个 Task 永远拿不到主线程，就是死锁。
        guard !isTerminating else { return }   // 上面已经收过尾了，别做第二遍
        isTerminating = true
        MainActor.assumeIsolated {
            coordinator?.shutdownSynchronously()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in coordinator?.showMainWindow() }
        return true
    }
}
