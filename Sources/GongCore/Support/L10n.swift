import Foundation

// MARK: - 语言

public enum Lang: String, Codable, Sendable, CaseIterable {
    case zh, en
}

/// 用户偏好。`system` 跟随系统首选语言。
public enum LangPreference: String, Codable, Sendable, CaseIterable, Hashable {
    case system, zh, en

    var resolved: Lang {
        switch self {
        case .zh: return .zh
        case .en: return .en
        case .system:
            let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return code.hasPrefix("zh") ? .zh : .en
        }
    }
}

/// 界面当前语言。视图渲染时读它。
///
/// 之所以用 MainActor 全局而不是 Environment：文案在几十处被引用，
/// 逐个穿参会让每个视图签名都变脏；而语言变化时 SettingsStore 会 publish，
/// 所有视图本来就会重绘，此刻读取全局是正确的。
@MainActor
public enum UILang {
    public private(set) static var current: Lang = LangPreference.system.resolved
    static func set(_ p: LangPreference) { current = p.resolved }
}

/// 取当前界面语言的文案。
@MainActor func L(_ k: S) -> String { k.text(UILang.current) }
/// 带参数版本。参数用 `%@`（字符串）/ `%d`（整数）。
@MainActor func L(_ k: S, _ args: CVarArg...) -> String {
    String(format: k.text(UILang.current), arguments: args)
}

// MARK: - 文案表

/// 全应用文案。
///
/// **不用 .lproj 资源包**：本应用是 SPM 可执行文件手工组装成 `.app` 的，
/// `Bundle.module` 在手工组装的包里路径不稳。纯 Swift 表更可靠。
///
/// 用 `switch` 返回 `(zh, en)` 而不是查字典：**漏翻一条是编译错误**，
/// 不是运行时的空白标签。这是选这个写法的全部理由。
enum S: CaseIterable {
    // 应用与导航
    case appName, tabTable, tabDashboard, tabBreaker, tabSettings, gotIt

    // 工字表
    case bandTodo, bandSummary, todoPlaceholder
    case kindFloorMenu, kindMitMenu, kindNormalMenu, delete, today
    case pickDateHelp, prevDayHelp, nextDayHelp
    case colPlan, colActual, colTotal, rangeSep, blockContent
    case addPlan, addActual, fillFromMonitor, fillFromMonitorHelp
    case foreignTZHelp, tzNoteTitle, tzNoteBody, outOfRangeTitle, outOfRangeBody
    case summaryTouched, summaryTouchedHint, summaryNote, summaryNoteHint
    case clarityTitle, clarityAdd, clarity01, clarity02, clarity03, clarity04
    case clarityDone, clarityUndone
    case statusFloor, statusMit
    case noFillIntervals, noFillIntervalsTZ

    // 模型
    case kindFloor, kindMit
    case statusNotRecorded, statusDone, statusSkipped
    case triggerN1, triggerN2, triggerN3, triggerV1, triggerV2
    case catFocus, catNeutral, catOther
    case untitled, emptyBrackets
    case punctColon, punctParenOpen, punctParenClose, punctPipe

    // 挂件
    case widgetEmpty, widgetCurrent, widgetMore, widgetTapHelp
    case widgetFocus, widgetOther, widgetMonitorOff

    // 看板
    case dashTimeAtComputer, dashByApp, dashWeek
    case axisMinutes, axisHours, axisDuration, axisApp, axisDate, axisFocusHours
    case dashNoData, dashNoWeekData, dashCategoryHint, dashTruncated, dashWeekLegend
    case dashScopeTitle, dashScopeBody

    // 阻断器
    case brkLastInterruption, brkLongestThisMonth, brkMinutesUnit, brkNoRecord, brkEnded
    case brkOnlyTwo, brkOnlyTwoBody
    case brkHardRuleLabel, brkHardRule, brkHardRuleBody
    case brkProcedure, brkProcedureBody
    case brkStep1, brkStep1Sub, brkStep2, brkStep2Sub, brkStep3, brkStep3Sub
    case brkStep4, brkStep4Sub, brkStep5, brkStep5Sub
    case brkTimer, brkTimerBody, brkStart, brkPause, brkReset
    case brkLog, brkMinutesField, brkEscapingPlaceholder, brkRecord
    case brkTriggerTable, brkTriggerNote, brkMinutesCount
    case alertFact, alertCurrentApp, alertBody, alertLog, alertOpen, alertSnooze

    // 设置
    case setExport, setChooseDir, setAutoExport, setAutoExportBody, setExportNow, setExportSafety
    case setPrivacy, setExportUsage, setExportInterruptions, setPrivacyBody
    case setWidget, setWidgetShow, setWidgetLevel, setWidgetBody
    case widgetModeDesktop, widgetModeFloating
    case setMonitor, setMonitorEnable, setIdleThreshold, setSecondsCount
    case setRetention, setDaysCount, setMonitorBody
    case setBreaker, setBreakerEnable, setBreakerThreshold, setMinutesCount, setSnooze, setBreakerBody
    case setCategories, setCategoriesBody, setCategoriesEmpty
    case setSystem, setLaunchAtLogin, setLoginFailed, setDataLocation
    case setAppearanceTitle, setLanguage, setAppearance
    case optSystem, optZh, optEn, optLight, optDark

    // 菜单栏
    case menuOpenMain, menuBringWidgetFront, menuToggleWidget, menuExportToday, menuQuit

    // 通知与错误
    case noticeSwitchBlocked, noticeReadFailed, noticeRecordTZ, noticeSaveFailed
    case noticeExportStateFailed, noticeExported, noticeUpdated, noticeUnsynced
    case noticeNoChange, noticeConflict
    case errExportDirFailed, errCreateFailed, errExportState, errExportFailed
    case errConflictWriteFailed, errTooManyConflicts

    // Markdown 导出
    case mdTodo, mdNotRecorded, mdFloorPrefix, mdMitPrefix, mdPlan, mdActual
    case mdSummary, mdTouched, mdClarity
    case mdStuckOn, mdEscapingFrom, mdWorstCase, mdFirstStep
    case mdNote, mdStatus, mdFloorLine, mdMitLine
    case mdAttention, mdInterruption, mdEscaping, mdUsageTop5
}

extension S {
    func text(_ lang: Lang) -> String { lang == .zh ? pair.zh : pair.en }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    var pair: (zh: String, en: String) {
        switch self {

        // MARK: 应用与导航
        case .appName:      return ("日课", "Rike")
        case .tabTable:     return ("工字表", "Table")
        case .tabDashboard: return ("看板", "Dashboard")
        case .tabBreaker:   return ("阻断器", "Breaker")
        case .tabSettings:  return ("设置", "Settings")
        case .gotIt:        return ("知道了", "Got it")

        // MARK: 工字表
        case .bandTodo:       return ("今日 TODO", "Today's TODO")
        case .bandSummary:    return ("今日总结", "Today's Summary")
        case .todoPlaceholder:return ("新增任务，回车确认", "New task, press return")
        case .kindFloorMenu:  return ("⌂ 下限（再累也做得到）", "⌂ Floor (doable however tired)")
        case .kindMitMenu:    return ("★ 最重要（做成了今天就不白过）",
                                     "★ Most important (makes the day count)")
        case .kindNormalMenu: return ("· 普通", "· Normal")
        case .delete:         return ("删除", "Delete")
        case .today:          return ("今天", "Today")
        case .pickDateHelp:   return ("点击选择任意一天（补昨天的总结、给未来的安排先记一笔）",
                                     "Click to jump to any day (backfill yesterday, pre-note a future meeting)")
        case .prevDayHelp:    return ("前一天　⌘←", "Previous day　⌘←")
        case .nextDayHelp:    return ("后一天　⌘→", "Next day　⌘→")
        case .colPlan:        return ("计划", "Plan")
        case .colActual:      return ("实际", "Actual")
        case .colTotal:       return ("共 %@", "%@ total")
        case .rangeSep:       return ("至", "–")
        case .blockContent:   return ("内容", "Content")
        case .addPlan:        return ("＋ 新增计划", "＋ Add plan")
        case .addActual:      return ("＋ 新增", "＋ Add")
        case .fillFromMonitor:return ("⟲ 从监控填充", "⟲ Fill from monitor")
        case .fillFromMonitorHelp:
            return ("把今天前台停留超过 10 分钟的应用区间填入实际列",
                    "Add today's foreground app intervals longer than 10 minutes to the Actual column")
        case .foreignTZHelp:
            return ("这条记录发生在 %@，时间按该时区显示与编辑",
                    "This block happened in %@; times are shown and edited in that zone")
        case .tzNoteTitle:
            return ("这一天按 %@ 的日界计算", "This day uses %@ day boundaries")
        case .tzNoteBody:
            return ("记录建立于该时区。你当前在 %@，因此时间轴与使用统计的日界与你此刻的当地日期不同，部分活动会归到相邻的一天。",
                    "The record was created in that zone. You are now in %@, so the timeline and usage day boundaries differ from your current local date; some activity falls on an adjacent day.")
        case .outOfRangeTitle:
            return ("%d 条实际记录落在该日时间轴之外",
                    "%d actual entries fall outside this day's timeline")
        case .outOfRangeBody:
            return ("这一天按 %@ 的日界投影。以下记录发生在该范围外，画不到轴上，但仍在记录里，也会正常导出。",
                    "This day is projected using %@ day boundaries. The entries below fall outside that range and cannot be drawn on the axis, but they remain in the record and export normally.")
        case .summaryTouched:    return ("触动", "What moved me")
        case .summaryTouchedHint:return ("今天最触动我的一件事，好坏都算，写细",
                                         "The one thing that moved me today — good or bad. Be specific.")
        case .summaryNote:       return ("备注", "Notes")
        case .summaryNoteHint:   return ("可留空", "Optional")
        case .clarityTitle:      return ("模糊清单", "Fog list")
        case .clarityAdd:        return ("＋ 拆解一条", "＋ Break one down")
        case .clarity01: return ("01 卡住的具体位置", "01 Exactly where I'm stuck")
        case .clarity02: return ("02 真正想逃开的是", "02 What I'm actually escaping")
        case .clarity03: return ("03 最坏情况", "03 Worst case")
        case .clarity04: return ("04 明天 30 分钟内的第一步", "04 First step tomorrow, within 30 min")
        case .clarityDone:  return ("已拆出具体动作", "A concrete action is written down")
        case .clarityUndone:return ("第 04 栏还空着，没拆出动作就不算写完",
                                    "Line 04 is still empty — without an action it isn't finished")
        case .statusFloor: return ("下限：%@", "Floor: %@")
        case .statusMit:   return ("最重要：%@", "Most important: %@")
        case .noFillIntervals:
            return ("这一天还没有超过 10 分钟的前台区间可供填充。",
                    "No foreground interval longer than 10 minutes on this day yet.")
        case .noFillIntervalsTZ:
            return ("没有可填充的区间。这一天按 %@ 的日界统计（记录建于该时区），你当前在 %@，本时段的活动可能被归到相邻的一天。",
                    "Nothing to fill. This day is counted using %@ day boundaries (the record was created there); you are now in %@, so activity from this period may fall on an adjacent day.")

        // MARK: 模型
        case .kindFloor: return ("下限", "Floor")
        case .kindMit:   return ("最重要", "Most important")
        case .statusNotRecorded: return ("未记录", "Not recorded")
        case .statusDone:        return ("已完成", "Done")
        case .statusSkipped:     return ("已跳过", "Skipped")
        case .triggerN1: return ("卡住了，不知道怎么办", "Stuck, no idea what to do")
        case .triggerN2: return ("干完硬活想放松", "Finished something hard, want to unwind")
        case .triggerN3: return ("随手点开", "Opened it without thinking")
        case .triggerV1: return ("想学东西却滑进短视频", "Meant to learn, slid into short video")
        case .triggerV2: return ("排队等待的空档", "Idle gap while waiting")
        case .catFocus:   return ("专注", "Focus")
        case .catNeutral: return ("中性", "Neutral")
        case .catOther:   return ("其他", "Other")
        case .untitled:      return ("（无标题）", "(untitled)")
        case .emptyBrackets: return ("（空）", "(empty)")
        // 标点也要跟着语言走。英文正文里夹全角「：（）｜」会很扎眼，
        // 而且导出的 markdown 是给未来的自己读的，不该中英标点混排。
        case .punctColon:      return ("：", ": ")
        case .punctParenOpen:  return ("（", " (")
        case .punctParenClose: return ("）", ")")
        case .punctPipe:       return (" ｜ ", " | ")

        // MARK: 挂件
        case .widgetEmpty:   return ("今天还没有记录", "Nothing recorded yet today")
        case .widgetCurrent: return ("当前：%@", "Now: %@")
        case .widgetMore:    return ("还有更多，点击打开主窗口", "More items — click to open the main window")
        case .widgetTapHelp: return ("点击打开主窗口", "Click to open the main window")
        case .widgetFocus:   return ("● 专注 %@", "● Focus %@")
        case .widgetOther:   return ("○ 其他 %@", "○ Other %@")
        case .widgetMonitorOff: return ("监控未启用", "Monitoring off")

        // MARK: 看板
        case .dashTimeAtComputer: return ("今日在机时长", "Time at computer")
        case .dashByApp:          return ("今日各应用时长", "Today by app")
        case .dashWeek:           return ("近 7 天", "Last 7 days")
        case .axisMinutes:    return ("分钟", "Minutes")
        case .axisHours:      return ("小时", "Hours")
        case .axisDuration:   return ("时长", "Duration")
        case .axisApp:        return ("应用", "App")
        case .axisDate:       return ("日期", "Date")
        case .axisFocusHours: return ("专注小时", "Focus hours")
        case .dashNoData:     return ("今天还没有监控数据。", "No monitoring data yet today.")
        case .dashNoWeekData: return ("暂无数据。", "No data yet.")
        case .dashCategoryHint:
            return ("类别可在「设置」中逐个应用修改", "Categories can be changed per app in Settings")
        case .dashTruncated:
            return ("注：上次退出未正常结束，最后一段按最后心跳截断，可能少计几十秒。",
                    "Note: the last session did not exit cleanly; the final segment was cut at the last heartbeat and may undercount by tens of seconds.")
        case .dashWeekLegend:
            return ("深色为专注时长，浅色为在机总时长。",
                    "Dark is focus time; light is total time at the computer.")
        case .dashScopeTitle: return ("关于统计口径", "About these numbers")
        case .dashScopeBody:
            return ("Claude Code 运行在 Terminal / iTerm 里，系统层面看到的是宿主应用，因此统计为 Terminal。要区分需要辅助功能权限读取窗口标题，本版本不做，也不会请求该权限。前台应用统计与空闲检测均不需要任何系统权限。",
                    "Claude Code runs inside Terminal / iTerm, so at the system level it is the host app that is visible and it is counted as Terminal. Telling them apart would require Accessibility permission to read window titles; this version does not do that and never requests it. Foreground-app tracking and idle detection need no system permission at all.")

        // MARK: 阻断器
        case .brkLastInterruption: return ("上次中断记录", "Last interruption logged")
        case .brkLongestThisMonth: return ("本月最长一次", "Longest this month")
        case .brkMinutesUnit: return ("分钟", "minutes")
        case .brkNoRecord:    return ("无记录", "None")
        case .brkEnded:       return ("结束", "ended")
        case .brkOnlyTwo:     return ("只看这两个数", "Only these two numbers")
        case .brkOnlyTwoBody:
            return ("第二个数在下降就是在赢。这里给的是日期，不是连续天数——连续天数是打卡计数器的变体。",
                    "If the second number is falling, you're winning. This shows a date, not a streak — a streak is just a check-in counter in disguise.")
        case .brkHardRuleLabel: return ("唯一的硬规则", "The one hard rule")
        case .brkHardRule:      return ("任何一次中断，不许跨过一次睡眠。",
                                       "No interruption may survive a night's sleep.")
        case .brkHardRuleBody:
            return ("跨日自动归零，不做连续天数展示——愧疚是 N-1 触发器的燃料。",
                    "It resets at the day boundary and no streak is shown — guilt is fuel for the N-1 trigger.")
        case .brkProcedure: return ("30 秒断路程序", "30-second circuit breaker")
        case .brkProcedureBody:
            return ("已经开始下滑时，按顺序做，不要先跟自己讲道理。跟渴望辩论必输。",
                    "Once you're already sliding, run these in order. Don't reason with yourself first — you lose arguments with craving.")
        case .brkStep1:    return ("站起来，离开这个房间", "Stand up and leave the room")
        case .brkStep1Sub: return ("先改变身体状态，不是先改变想法。",
                                  "Change your physical state first, not your thoughts.")
        case .brkStep2:    return ("手机／平板放到另一个房间", "Phone / tablet goes to another room")
        case .brkStep2Sub: return ("不是抽屉，是另一个房间。", "Not a drawer. Another room.")
        case .brkStep3:    return ("出门走 10 分钟，或洗把冷水脸、吃点东西",
                                  "Walk 10 minutes, or splash cold water, or eat something")
        case .brkStep3Sub: return ("目标是打断状态，不是说服自己。",
                                  "The goal is to break the state, not to persuade yourself.")
        case .brkStep4:    return ("写一句：我刚才真正想逃开的是 ___",
                                  "Write one line: what I actually wanted to escape was ___")
        case .brkStep4Sub: return ("把迷雾变成对象。你逃的是无边界，不是难。",
                                  "Turn fog into an object. You're escaping formlessness, not difficulty.")
        case .brkStep5:    return ("做那件事的 5 分钟版本，然后允许自己停",
                                  "Do the 5-minute version, then let yourself stop")
        case .brkStep5Sub: return ("让开放回路挂回工作上，而不是挂在下一章。",
                                  "Leave the open loop on the work, not on the next chapter.")
        case .brkTimer: return ("10 分钟延迟计时器", "10-minute delay timer")
        case .brkTimerBody:
            return ("想打开的那一刻，先按开始。渴望是一条会自己落下去的曲线，通常十几分钟就过峰。十分钟后你还想看，那就去看——但那时是你在决定。",
                    "The moment you want to open it, press Start. Craving is a curve that comes down on its own, usually cresting within about fifteen minutes. If you still want it after ten, go ahead — but then it's you deciding.")
        case .brkStart: return ("开始", "Start")
        case .brkPause: return ("暂停", "Pause")
        case .brkReset: return ("重置", "Reset")
        case .brkLog:   return ("记一笔（中性记录，不写评价）",
                               "Log it (a neutral record, not a judgement)")
        case .brkMinutesField: return ("分钟", "Minutes")
        case .brkEscapingPlaceholder: return ("真正想逃开的是…", "What I was actually escaping…")
        case .brkRecord:       return ("记录", "Log")
        case .brkTriggerTable: return ("触发器对照", "Trigger reference")
        case .brkTriggerNote:
            return ("V-1 / V-2 可由监控自动检测：「其他」类应用连续前台超过设定阈值时，挂件描边变色并出现非模态提示。绝不使用系统模态弹窗。",
                    "V-1 / V-2 can be detected automatically: when an app categorised Other stays in the foreground past the threshold, the widget border changes colour and a non-modal note appears. Never a system modal dialog.")
        case .brkMinutesCount: return ("%d 分钟", "%d min")
        case .alertFact:       return ("%@ 已连续 %d 分钟", "%@ for %d minutes straight")
        case .alertCurrentApp: return ("当前应用", "This app")
        case .alertBody:
            return ("站起来，离开这个房间。先改变身体状态，不是先改变想法。",
                    "Stand up and leave the room. Change your physical state first, not your thoughts.")
        case .alertLog:    return ("记一笔", "Log it")
        case .alertOpen:   return ("打开断路程序", "Open the breaker")
        case .alertSnooze: return ("忽略 %d 分钟", "Snooze %d min")

        // MARK: 设置
        case .setExport:     return ("Markdown 导出", "Markdown export")
        case .setChooseDir:  return ("选择目录…", "Choose folder…")
        case .setAutoExport: return ("保存时自动导出", "Export automatically on save")
        case .setAutoExportBody:
            return ("默认关闭。每次写入都存在「外部进程可能同时修改同一文件」的暴露窗口，降低写入频率是最有效的缓解。需要时用下面的按钮手动导出即可。",
                    "Off by default. Every write opens a window in which another process could be modifying the same file; writing less often is the most effective mitigation. Use the button below when you want a file.")
        case .setExportNow: return ("立即导出今天", "Export today now")
        case .setExportSafety:
            return ("安全规则：目标文件不存在时独占创建；已存在且确认是本应用生成、内容未被改动时才替换；否则一律另存为 *.rike-conflict.md，原文件绝不改动。",
                    "Safety rule: if the target file does not exist it is created exclusively; if it exists it is replaced only when it is confirmed to be ours and unmodified; otherwise the export is written to *.rike-conflict.md and the original is never touched.")
        case .setPrivacy:              return ("隐私", "Privacy")
        case .setExportUsage:          return ("导出应用使用明细", "Export app-usage detail")
        case .setExportInterruptions:  return ("导出中断记录明细", "Export interruption detail")
        case .setPrivacyBody:
            return ("两项默认关闭。导出目录在 Work_Records 下，这些内容可能被同步到云盘或整体喂给 AI 阅读；软件使用记录与中断记录属于个人行为数据，开启前请确认你接受这一点。",
                    "Both off by default. The export folder lives under Work_Records, which may be synced to cloud storage or handed to an AI to read. App-usage and interruption records are personal behavioural data — make sure you're comfortable with that before turning these on.")
        case .setWidget:      return ("桌面挂件", "Desktop widget")
        case .setWidgetShow:  return ("显示挂件", "Show widget")
        case .setWidgetLevel: return ("层级", "Level")
        case .setWidgetBody:
            return ("桌面层的行为由系统决定，在 Stage Manager、全屏应用、Mission Control 下不保证一致可见——这是 macOS 的限制，不是设置错误。需要始终可见就选「置顶」。菜单栏图标里也有「把挂件提到最前」。",
                    "Desktop-level behaviour is decided by the system and is not guaranteed to stay visible under Stage Manager, full-screen apps or Mission Control — that's a macOS limitation, not a misconfiguration. Choose Always on top if you need it always visible. The menu-bar icon also has Bring widget to front.")
        case .widgetModeDesktop:  return ("桌面层（不挡窗口）", "Desktop level (never covers windows)")
        case .widgetModeFloating: return ("置顶（始终可见）", "Always on top")
        case .setMonitor:       return ("使用时长监控", "Usage monitoring")
        case .setMonitorEnable: return ("启用监控", "Enable monitoring")
        case .setIdleThreshold: return ("空闲判定阈值", "Idle threshold")
        case .setSecondsCount:  return ("%d 秒", "%d s")
        case .setRetention:     return ("原始事件日志保留", "Keep raw event log for")
        case .setDaysCount:     return ("%d 天", "%d days")
        case .setMonitorBody:
            return ("前台应用统计与空闲检测不需要任何系统权限，本应用也不会请求辅助功能或屏幕录制权限。超过保留期的原始事件日志会被清理，已汇总的统计保留。",
                    "Foreground-app tracking and idle detection need no system permission, and this app never requests Accessibility or Screen Recording. Raw event logs past the retention period are cleaned up; the summarised statistics are kept.")
        case .setBreaker:          return ("注意力阻断器", "Attention breaker")
        case .setBreakerEnable:    return ("启用主动提示", "Enable active prompts")
        case .setBreakerThreshold: return ("「其他」类应用连续前台超过",
                                          "Prompt after an Other app stays in front for")
        case .setMinutesCount:     return ("%d 分钟", "%d min")
        case .setSnooze:           return ("忽略时长", "Snooze for")
        case .setBreakerBody:
            return ("提示只用挂件描边变色 + 非模态浮层，不会弹出系统对话框打断你正在做的事。",
                    "Prompts are only a widget border colour change plus a non-modal panel — never a system dialog that interrupts what you're doing.")
        case .setCategories: return ("应用分类", "App categories")
        case .setCategoriesBody:
            return ("影响看板配色与阻断器判定。v1 只按应用分类，不做网页级识别。",
                    "Affects dashboard colours and breaker decisions. v1 categorises by app only, not per website.")
        case .setCategoriesEmpty:
            return ("今天还没有监控数据，出现后会在这里列出。",
                    "No monitoring data yet today; apps will be listed here once there is.")
        case .setSystem:        return ("系统", "System")
        case .setLaunchAtLogin: return ("开机启动", "Launch at login")
        case .setLoginFailed:   return ("设置开机启动失败：%@", "Could not set launch at login: %@")
        case .setDataLocation:  return ("数据位置：%@", "Data location: %@")
        case .setAppearanceTitle: return ("外观与语言", "Appearance & language")
        case .setLanguage:      return ("语言", "Language")
        case .setAppearance:    return ("外观", "Appearance")
        case .optSystem: return ("跟随系统", "System")
        case .optZh:     return ("中文", "中文")
        case .optEn:     return ("English", "English")
        case .optLight:  return ("浅色", "Light")
        case .optDark:   return ("深色", "Dark")

        // MARK: 菜单栏
        case .menuOpenMain:         return ("打开主窗口", "Open main window")
        case .menuBringWidgetFront: return ("把挂件提到最前", "Bring widget to front")
        case .menuToggleWidget:     return ("显示／隐藏挂件", "Show / hide widget")
        case .menuExportToday:      return ("立即导出今天", "Export today now")
        case .menuQuit:             return ("退出 %@", "Quit %@")

        // MARK: 通知与错误
        case .noticeSwitchBlocked:
            return ("当前内容尚未全部保存，已取消切换日期。稍后再试或先解决保存失败的原因。",
                    "Not everything is saved yet, so the date change was cancelled. Try again shortly, or fix the save failure first.")
        case .noticeReadFailed:  return ("读取当日记录失败：%@", "Could not read this day's record: %@")
        case .noticeRecordTZ:    return ("这一天记录于 %@，按记录时的时区显示。",
                                        "This day was recorded in %@ and is shown in that zone.")
        case .noticeSaveFailed:  return ("保存失败：%@", "Save failed: %@")
        case .noticeExportStateFailed:
            return ("导出状态保存失败：%@", "Could not save export state: %@")
        case .noticeExported: return ("已导出：%@", "Exported: %@")
        case .noticeUpdated:  return ("已更新：%@", "Updated: %@")
        case .noticeUnsynced:
            return ("已写入 %@，但磁盘未确认持久化（%@）。内容已就位，断电时可能丢失这一次写入。",
                    "Wrote %@, but the disk did not confirm the flush (%@). The content is in place, but this one write could be lost on power failure.")
        case .noticeNoChange: return ("内容无变化，未写入：%@", "No change, nothing written: %@")
        case .noticeConflict:
            return ("目标文件被外部修改或非本应用生成，已另存为 %@，原文件未改动",
                    "The target file was modified externally or wasn't ours; saved as %@ instead, original untouched")
        case .errExportDirFailed: return ("无法创建导出目录：%@ —— %@",
                                          "Could not create the export folder: %@ — %@")
        case .errCreateFailed:    return ("创建失败：%@", "Create failed: %@")
        case .errExportState:     return ("导出状态异常", "Inconsistent export state")
        case .errExportFailed:    return ("导出失败：%@", "Export failed: %@")
        case .errConflictWriteFailed: return ("冲突文件写入失败：%@", "Could not write conflict file: %@")
        case .errTooManyConflicts:
            return ("冲突文件过多（已有 100 个），请先清理导出目录",
                    "Too many conflict files (100 already); please clean up the export folder first")

        // MARK: Markdown 导出
        case .mdTodo:        return ("今日 TODO", "Today's TODO")
        case .mdNotRecorded: return ("（未记录）", "(not recorded)")
        case .mdFloorPrefix: return ("⌂ 下限：", "⌂ Floor: ")
        case .mdMitPrefix:   return ("★ 最重要：", "★ Most important: ")
        case .mdPlan:        return ("计划", "Plan")
        case .mdActual:      return ("实际", "Actual")
        case .mdSummary:     return ("今日总结", "Today's Summary")
        case .mdTouched:     return ("触动", "What moved me")
        case .mdClarity:     return ("模糊清单", "Fog list")
        case .mdStuckOn:       return ("卡住的具体位置", "Exactly where I'm stuck")
        case .mdEscapingFrom:  return ("真正想逃开的是", "What I'm actually escaping")
        case .mdWorstCase:     return ("最坏情况", "Worst case")
        case .mdFirstStep:     return ("明天 30 分钟内的第一步", "First step tomorrow, within 30 min")
        case .mdNote:      return ("备注", "Notes")
        case .mdStatus:    return ("状态", "Status")
        case .mdFloorLine: return ("下限", "Floor")
        case .mdMitLine:   return ("最重要", "Most important")
        case .mdAttention:    return ("注意力", "Attention")
        case .mdInterruption: return ("中断 %d 分钟 · 触发 %@", "Interrupted %d min · trigger %@")
        case .mdEscaping:     return (" · 真正想逃开的：%@", " · actually escaping: %@")
        case .mdUsageTop5:    return ("使用时长（前 5）", "Time by app (top 5)")
        }
    }
}
