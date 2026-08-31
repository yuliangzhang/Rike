import Foundation

/// 所有路径的唯一来源。**不硬编码 `~/Library/...`**，一律走 FileManager API。
enum GongPaths {
    static let bundleIdentifier = "com.ybjv.gong"

    /// <ApplicationSupport>/com.ybjv.gong/
    static var root: URL {
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

    static func exportFile(in directory: URL, dayKey: String) -> URL {
        directory.appendingPathComponent("\(GongTime.compactKey(dayKey)).md")
    }

    static func conflictFile(in directory: URL, dayKey: String) -> URL {
        directory.appendingPathComponent("\(GongTime.compactKey(dayKey)).gong-conflict.md")
    }

    static var allDirectories: [URL] { [root, daysDir, eventsDir, usageDir] }
}
