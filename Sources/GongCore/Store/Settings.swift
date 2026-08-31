import Foundation

enum WidgetMode: String, Codable, CaseIterable, Sendable {
    case desktop    // 桌面层：像原生 widget，不挡工作窗口（默认）
    case floating   // 置顶：始终可见

    var label: String {
        switch self {
        case .desktop:  return "桌面层（不挡窗口）"
        case .floating: return "置顶（始终可见）"
        }
    }
}

struct AppSettings: Codable, Sendable, Hashable {
    // 导出
    var exportDirectoryPath: String = GongPaths.defaultExportDirectory.path
    /// 默认关闭自动导出。理由：每次写入都有一个「外部进程可能同时改文件」的暴露窗口，
    /// 降低写入频率是最有效的缓解。用户可在设置中开启。
    var autoExport: Bool = false
    /// 隐私：使用明细会进入 Work_Records（用户会同步云盘 / 喂给 AI），默认不导出。
    var exportUsageDetail: Bool = false
    var exportInterruptionDetail: Bool = false

    // 挂件
    var widgetMode: WidgetMode = .desktop
    var widgetVisible: Bool = true
    var widgetFrame: WidgetFrame?

    // 监控
    var monitoringEnabled: Bool = true
    var idleThresholdSeconds: Int = 180
    var heartbeatSeconds: Int = 60
    /// 原始事件日志保留天数；超期只保留 reducer 汇总。
    var rawLogRetentionDays: Int = 180

    // 阻断器
    var breakerEnabled: Bool = true
    var breakerThresholdMinutes: Int = 15
    var breakerSnoozeMinutes: Int = 30

    // 分类：bundleId -> 类别。v1 只按应用分类。
    var categories: [String: AppCategory] = [:]

    var launchAtLogin: Bool = false

    struct WidgetFrame: Codable, Sendable, Hashable {
        var x: Double, y: Double, width: Double, height: Double
    }

    var exportDirectory: URL { URL(fileURLWithPath: exportDirectoryPath, isDirectory: true) }

    /// 内置默认分类。用户可逐个覆盖，覆盖值存在 `categories` 里。
    static let builtinCategories: [String: AppCategory] = [
        "com.apple.dt.Xcode":            .focus,
        "com.microsoft.VSCode":          .focus,
        "com.apple.Terminal":            .focus,
        "com.googlecode.iterm2":         .focus,
        "dev.warp.Warp-Stable":          .focus,
        "com.figma.Desktop":             .focus,
        "com.apple.Notes":               .focus,
        "com.apple.finder":              .neutral,
        "com.google.Chrome":             .neutral,
        "com.apple.Safari":              .neutral,
        "com.apple.mail":                .neutral,
        "com.tencent.xinWeChat":         .other,
        "com.tencent.WeWorkMac":         .other,
        "com.xingin.discover":           .other,
        "tv.danmaku.bilianimev2":        .other
    ]

    func category(for bundleId: String) -> AppCategory {
        categories[bundleId] ?? AppSettings.builtinCategories[bundleId] ?? .neutral
    }
}
