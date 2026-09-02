import Foundation

/// 所有路径的唯一来源。**不硬编码 `~/Library/...`**，一律走 FileManager API。
enum GongPaths {
    static let bundleIdentifier = "com.ybjv.gong"

    /// 仅供测试覆盖，避免单元测试写进用户真实数据目录。生产代码永远不设置它。
    nonisolated(unsafe) static var overrideRoot: URL?

    /// <ApplicationSupport>/com.ybjv.gong/
    static var root: URL {
        if let o = overrideRoot { return o }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var daysDir: URL   { root.appendingPathComponent("days",   isDirectory: true) }
    static var eventsDir: URL { root.appendingPathComponent("events", isDirectory: true) }
    static var usageDir: URL  { root.appendingPathComponent("usage",  isDirectory: true) }
    static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    static func dayFile(_ dayKey: String)    -> URL { daysDir.appendingPathComponent("\(dayKey).json") }
    static func eventsFile(_ dayKey: String) -> URL { eventsDir.appendingPathComponent("\(dayKey).ndjson") }
    static func usageFile(_ dayKey: String)  -> URL { usageDir.appendingPathComponent("\(dayKey).json") }

    /// 默认导出目录：~/Documents/Work_Records/daily/
    /// 用 `daily/` 子目录，与用户既有的 `20260519_records.md` 等手写文件天然不冲突。
    static var defaultExportDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return docs
            .appendingPathComponent("Work_Records", isDirectory: true)
            .appendingPathComponent("daily", isDirectory: true)
    }

    /// 导出文件的基名：`2026-08-31-daily-record`。
    ///
    /// 用户定的格式。带横杠的日期在 Finder 里按名字排序就是按时间排序，
    /// 而且一眼看得出是哪天的——比 `20260831` 好认。
    /// **三处（正常导出／冲突文件／带序号的冲突文件）都从这里取**，
    /// 各自拼字符串迟早会漂。
    static func exportBaseName(dayKey: String) -> String {
        "\(dayKey)-daily-record"
    }

    static func exportFile(in directory: URL, dayKey: String) -> URL {
        directory.appendingPathComponent("\(exportBaseName(dayKey: dayKey)).md")
    }

    static func conflictFile(in directory: URL, dayKey: String) -> URL {
        directory.appendingPathComponent("\(exportBaseName(dayKey: dayKey)).gong-conflict.md")
    }

    static func conflictFile(in directory: URL, dayKey: String, index: Int) -> URL {
        directory.appendingPathComponent(
            "\(exportBaseName(dayKey: dayKey)).gong-conflict-\(index).md")
    }

    static var allDirectories: [URL] { [root, daysDir, eventsDir, usageDir] }

    /// 系统瞬时进程：登录窗口、控制中心、Spotlight、Dock 等。
    /// 它们会短暂成为前台应用，计入统计只会制造噪音。
    static let ignoredBundleIds: Set<String> = [
        bundleIdentifier,
        "com.apple.loginwindow",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.ScreenSaver.Engine",
        "com.apple.SecurityAgent",
        "com.apple.CoreAuthUI"
    ]

    static func isIgnored(_ bundleId: String) -> Bool { ignoredBundleIds.contains(bundleId) }
}
