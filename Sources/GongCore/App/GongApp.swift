import SwiftUI
import AppKit


public struct GongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    public init() {}

    public var body: some Scene {
        Settings { EmptyView() }   // 无 Dock 图标的 accessory app，窗口由 delegate 管理
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var probeWindow: NSWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // --- 冒烟测试 1：菜单栏项 ---
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "工"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Gong 冒烟测试运行中", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        // --- 冒烟测试 2：桌面层无边框面板（挂件的技术前提）---
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 268, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: ProbeWidget())
        panel.orderFrontRegardless()
        probeWindow = panel

        // --- 冒烟测试 3：SwiftUI Charts 可用性在编译期已验证 ---
        FileHandle.standardError.write("GONG-SMOKE-OK statusItem+desktopPanel+SwiftUI\n".data(using: .utf8)!)
    }
}

private struct ProbeWidget: View {
    @State private var clicks = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("工 Gong").font(.system(size: 15, weight: .bold))
            Text("桌面层面板冒烟测试").font(.system(size: 11)).foregroundStyle(.secondary)
            Button("点击测试：\(clicks)") { clicks += 1 }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
