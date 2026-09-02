import Foundation

// MARK: - 枚举

/// TODO 的类型。下限与最重要各限一条（约束在 DayRecord 层强制）。
enum TodoKind: String, Codable, CaseIterable, Sendable {
    case floor   // ⌂ 下限：再累也做得到
    case mit     // ★ 最重要：做成了今天就不白过
    case normal

    var marker: String {
        switch self {
        case .floor:  return "⌂"
        case .mit:    return "★"
        case .normal: return "·"
        }
    }

    func label(_ lang: Lang) -> String {
        switch self {
        case .floor:  return S.kindFloor.text(lang)
        case .mit:    return S.kindMit.text(lang)
        case .normal: return ""
        }
    }
    @MainActor var label: String { label(UILang.current) }
}

/// 中性状态。默认 `.notRecorded` —— `false` 读作「失败」，`notRecorded` 读作「事实」。
/// 这是「用记录代替打卡」原则的字段级落实，不要改成 Bool。
enum ItemStatus: String, Codable, Sendable {
    case notRecorded
    case done
    case skipped

    func label(_ lang: Lang) -> String {
        switch self {
        case .notRecorded: return S.statusNotRecorded.text(lang)
        case .done:        return S.statusDone.text(lang)
        case .skipped:     return S.statusSkipped.text(lang)
        }
    }
    @MainActor var label: String { label(UILang.current) }
}

enum BlockSource: String, Codable, Sendable {
    case manual
    case monitor
}

/// 触发器编号，与《注意力断路器》一致。
enum Trigger: String, Codable, CaseIterable, Sendable {
    case n1, n2, n3, v1, v2

    var code: String {
        switch self {
        case .n1: return "N-1"
        case .n2: return "N-2"
        case .n3: return "N-3"
        case .v1: return "V-1"
        case .v2: return "V-2"
        }
    }

    func scene(_ lang: Lang) -> String {
        switch self {
        case .n1: return S.triggerN1.text(lang)
        case .n2: return S.triggerN2.text(lang)
        case .n3: return S.triggerN3.text(lang)
        case .v1: return S.triggerV1.text(lang)
        case .v2: return S.triggerV2.text(lang)
        }
    }
    @MainActor var scene: String { scene(UILang.current) }
}

/// 应用类别。用「其他」而非「干扰」——中性不评价。
enum AppCategory: String, Codable, CaseIterable, Sendable {
    case focus, neutral, other

    func label(_ lang: Lang) -> String {
        switch self {
        case .focus:   return S.catFocus.text(lang)
        case .neutral: return S.catNeutral.text(lang)
        case .other:   return S.catOther.text(lang)
        }
    }
    @MainActor var label: String { label(UILang.current) }
}

// MARK: - DayKey：一天的稳定标识（含时区）

/// 一天的完整标识。**必须带时区**：否则用户旅行后打开历史记录，
/// 或实际发生地与计划地不同时，Ribbon 按哪个时区渲染是未定义的。
struct DayKey: Codable, Hashable, Sendable {
    var date: String                  // "2026-08-31"
    var timeZoneIdentifier: String
    var calendarIdentifier: String

    init(date: String,
         timeZoneIdentifier: String = TimeZone.current.identifier,
         calendarIdentifier: String = "gregorian") {
        self.date = date
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarIdentifier = calendarIdentifier
    }

    init(_ date: Date, timeZone: TimeZone = .current) {
        self.init(date: GongTime.dayKey(date, timeZone: timeZone),
                  timeZoneIdentifier: timeZone.identifier)
    }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.firstWeekday = 2
        return c
    }

    /// 该日在该时区下的真实区间。DST 当天可能不是 24 小时。
    var dayInterval: DateInterval? {
        guard let start = GongTime.date(fromDayKey: date, timeZone: timeZone) else { return nil }
        return calendar.dateInterval(of: .day, for: start)
    }

    /// 该日真实长度（分钟）。春令时 1380，秋令时 1500，平日 1440。
    var lengthMinutes: Int {
        guard let iv = dayInterval else { return 1440 }
        return Int((iv.duration / 60).rounded())
    }

    func displayLabel(_ lang: Lang) -> String {
        "\(date) \(GongTime.weekdayLabel(dayKey: date, lang: lang))"
    }
    @MainActor var displayLabel: String { displayLabel(UILang.current) }
}

// MARK: - 核心模型

struct Todo: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var text: String = ""
    var status: ItemStatus = .notRecorded
    var kind: TodoKind = .normal
    var order: Int = 0

    var isDone: Bool { status == .done }
}

/// 计划块：**墙钟意图**。「明早 9 点」在 DST 当天仍然是 9 点。
/// 不变式：`0 <= startMinute < endMinute <= 1440`。不支持跨日，跨日请拆两块。
struct PlannedBlock: Codable, Identifiable, Hashable, Sendable {
    static let dayMinutes = 24 * 60

    var id: UUID = UUID()
    private(set) var startMinute: Int
    private(set) var endMinute: Int
    var title: String = ""
    var linkedTodoId: UUID?

    init(id: UUID = UUID(), start: Int = 9 * 60, end: Int = 10 * 60,
         title: String = "", linkedTodoId: UUID? = nil) {
        self.id = id
        let (s, e) = PlannedBlock.clamp(start: start, end: end)
        self.startMinute = s
        self.endMinute = e
        self.title = title
        self.linkedTodoId = linkedTodoId
    }

    /// 唯一的合法改值入口，保证不变式。
    mutating func setRange(start: Int, end: Int) {
        let (s, e) = PlannedBlock.clamp(start: start, end: end)
        startMinute = s
        endMinute = e
    }

    static func clamp(start: Int, end: Int) -> (Int, Int) {
        let s = min(max(0, start), dayMinutes - 1)   // 0..<1440
        let e = min(max(s + 1, end), dayMinutes)     // (s, 1440]
        return (s, e)
    }

    var durationMinutes: Int { endMinute - startMinute }
    func rangeLabel(_ lang: Lang) -> String {
        GongTime.formatRange(startMinute, endMinute, lang: lang)
    }
    @MainActor var rangeLabel: String { rangeLabel(UILang.current) }
}

/// 实际块：**已发生的瞬间**，可逆、可跨时区重算。
struct ActualBlock: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
    /// 事件实际发生地的时区，仅作显示；投影一律按 DayKey 的时区。
    var timeZoneIdentifier: String = TimeZone.current.identifier
    var title: String = ""
    var source: BlockSource = .manual

    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    var durationSeconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// 墙钟标签。**必须按这个块自己发生地的时区渲染**，不能用所属记录的时区——
    /// 否则在珀斯的 09-01 记录里，一条发生在纽约 20:00 的实际块会被显示/导出成
    /// 珀斯的次日 08:00，记录语义就错了。
    /// 当它与记录所在时区不同时，标签里附上时区标识。
    func rangeLabel(recordTimeZoneIdentifier: String, lang: Lang) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        func hm(_ d: Date) -> String {
            String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
        }
        let base = "\(hm(start)) \(S.rangeSep.text(lang)) \(hm(end))"
        return timeZoneIdentifier == recordTimeZoneIdentifier
            ? base
            : "\(base)\(S.punctParenOpen.text(lang))\(timeZoneIdentifier)\(S.punctParenClose.text(lang))"
    }

    /// 与记录时区不同时返回时区标识，供 UI 在可编辑的时间格旁挂一个后缀。
    func foreignTimeZoneLabel(recordTimeZoneIdentifier: String) -> String? {
        timeZoneIdentifier == recordTimeZoneIdentifier ? nil : timeZoneIdentifier
    }

    // MARK: 墙钟编辑
    //
    // 实际块在模型里是一段绝对时间（DateInterval），但人是按墙钟来改的：
    // 「我其实是 14:00 到 15:30 干的这件事」。所以编辑入口收墙钟分钟数，
    // 一律**按本块自己的时区**解释——用记录的时区解释会把在纽约发生的事
    // 写成珀斯的时刻，和 rangeLabel 的结论自相矛盾。

    private var ownCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    private func wallClockMinutes(_ d: Date) -> Int {
        let c = ownCalendar
        return c.component(.hour, from: d) * 60 + c.component(.minute, from: d)
    }

    /// 本块在自己时区里的墙钟分钟数，供编辑框显示。
    var startWallClockMinutes: Int { wallClockMinutes(start) }
    var endWallClockMinutes: Int { wallClockMinutes(end) }

    /// 把墙钟分钟数解析成本块时区里的一个瞬间，锚定在 `anchor` 所在的那个日历日。
    /// 走 DateComponents 而不是 startOfDay + 秒偏移：DST 当天不是 1440 分钟，
    /// 秒偏移会算错；交给 Calendar 解释墙钟才是对的。
    /// 春令时的不存在时刻由 Calendar 前移到间隔之后，仍返回一个有效瞬间。
    private func instant(wallClockMinutes m: Int, anchoredOn anchor: Date) -> Date? {
        let c = ownCalendar
        var comps = c.dateComponents([.year, .month, .day], from: anchor)
        comps.hour = m / 60          // m == 1440 时 hour = 24，Calendar 自行滚到次日 00:00
        comps.minute = m % 60
        comps.second = 0
        return c.date(from: comps)
    }

    /// 改开始时刻。结束时刻原则上不动（把 09:12 改成 09:30 就该只是缩短这一块）；
    /// 只有当新的开始越过了原结束时才整块平移，保住原时长。
    /// 这里**不能**套用「结束顺延到次日」的规则——那会把 10:00–11:00 改成
    /// 14:00 时凭空造出一个二十一小时的块，显然不是人改开始时间时的意思。
    ///
    /// 开始一律夹到 `0..<1440`。`GongTime.parseMinutes` 会接受 24:00（=1440），
    /// 但 24:00 作为**开始**没有意义——那一天已经结束了。放行的话
    /// `comps.hour = 24` 会被 Calendar 滚到次日 00:00，整块静默跳到另一天。
    /// 这也与 `PlannedBlock.clamp` 的不对称约定保持一致：开始 `0..<1440`、
    /// 结束 `(start, 1440]`，两列的行为必须是同一套。
    mutating func setStartWallClock(_ minutes: Int) {
        let m = min(max(0, minutes), PlannedBlock.dayMinutes - 1)
        guard let s = instant(wallClockMinutes: m, anchoredOn: start) else { return }
        let duration = durationSeconds
        start = s
        if end <= start { end = start.addingTimeInterval(max(60, duration)) }
    }

    /// 改结束时刻。锚定在**开始所在的那一天**再向后归一化，
    /// 于是「23:00 至 01:00」（跨夜）和「23:00 至 23:30」都能按人的直觉落到正确的一天。
    mutating func setEndWallClock(_ minutes: Int) {
        guard let e = instant(wallClockMinutes: minutes, anchoredOn: start) else { return }
        end = e
        normalizeEndForward()
    }

    private mutating func normalizeEndForward() {
        guard end <= start else { return }
        if let next = ownCalendar.date(byAdding: .day, value: 1, to: end), next > start {
            end = next
        } else {
            end = start.addingTimeInterval(60)
        }
    }
}

/// 模糊拆解器的一条。第 04 栏 firstStep 为空 = 未完成。
struct ClarityEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var stuckOn: String = ""
    var escapingFrom: String = ""
    var worstCase: String = ""
    var firstStep: String = ""
    var createdAt: Date = Date()

    var isComplete: Bool { !firstStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 中断记录（原「失控」，中性命名）。
struct Interruption: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var at: Date = Date()
    var trigger: Trigger = .n1
    var minutes: Int = 0
    var escapingFrom: String = ""
    var earlierBreakPoint: String = ""
    var autoDetected: Bool = false
}

struct BreakerDay: Codable, Hashable, Sendable {
    var interruptions: [Interruption] = []
    var timerRuns: Int = 0
}

/// 成功日记的一条。灵感来自《小狗钱钱》：每天记下几件**自己做成的小事**。
/// 它和「触动」不同——触动可以是坏的，成功日记只记做成的。
struct WinEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var text: String = ""
}

/// 今日总结。
///
/// 注意：**不含 floorStatus / mitStatus**。
/// 那会与真实来源构成双重事实源，导致「已完成但总结显示未记录」。
/// 下限状态来自 `DayRecord.floor`，最重要状态来自 TODO 列表的第一条。
///
/// **新增字段一律走 `decodeIfPresent`**（见下面的 `init(from:)`）：
/// 合成的 Codable 在缺键时会**抛错**，非可选字段哪怕写了默认值也救不了旧记录，
/// 结果就是打开历史某天报「读取失败」，看起来像数据没了。
struct DaySummary: Codable, Hashable, Sendable {
    var touched: String = ""
    /// 成功日记：3~5 条自己觉得有成就的小事。
    var wins: [WinEntry] = []
    /// 明天会更好：怎么调整策略/安排，让明天做得更好。
    var tomorrow: String = ""
    var clarity: [ClarityEntry] = []
    var freeText: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        touched  = try c.decodeIfPresent(String.self, forKey: .touched) ?? ""
        wins     = try c.decodeIfPresent([WinEntry].self, forKey: .wins) ?? []
        tomorrow = try c.decodeIfPresent(String.self, forKey: .tomorrow) ?? ""
        clarity  = try c.decodeIfPresent([ClarityEntry].self, forKey: .clarity) ?? []
        freeText = try c.decodeIfPresent(String.self, forKey: .freeText) ?? ""
    }
}

/// 今日下限：**独立于 TODO**。
///
/// 用户的原话：「下限可能不是 TODO List 中的」——比如「今天必须在 23:00 前睡觉」，
/// 那不是一件要做的工作，而是一条今天无论如何都要守住的线。
/// 硬塞进 TODO 列表既别扭，也会让「再累也做得到」这条原则被工作事项淹没。
struct FloorItem: Codable, Hashable, Sendable {
    var text: String = ""
    var status: ItemStatus = .notRecorded

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text   = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        status = try c.decodeIfPresent(ItemStatus.self, forKey: .status) ?? .notRecorded
    }
}

/// Markdown 导出状态。与 DayRecord 一起原子落盘，避免两处写入交错。
struct ExportState: Codable, Hashable, Sendable {
    var path: String
    var contentHash: String
    var exportedAt: Date
}

// MARK: - 一天

struct DayRecord: Codable, Identifiable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = DayRecord.currentSchemaVersion
    var key: DayKey
    var todos: [Todo] = []
    var planned: [PlannedBlock] = []
    var actual: [ActualBlock] = []
    var summary: DaySummary = DaySummary()
    var breaker: BreakerDay = BreakerDay()
    var updatedAt: Date = Date()

    /// 今日下限。独立于 TODO —— 见 `FloorItem` 的说明。
    var floor: FloorItem = FloorItem()

    /// 单调递增，用于拒绝过期快照写入（防 lost update）。
    var revision: Int = 0

    var exportState: ExportState?

    var id: String { key.date }
    var date: String { key.date }

    init(key: DayKey) { self.key = key }
    init(date: String) { self.key = DayKey(date: date) }

    /// 手写解码，新增字段一律 `decodeIfPresent`。
    /// 合成版在缺键时会抛错，旧记录会整条读不出来。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? DayRecord.currentSchemaVersion
        key       = try c.decode(DayKey.self, forKey: .key)        // 没有它这条记录就没有意义
        todos     = try c.decodeIfPresent([Todo].self, forKey: .todos) ?? []
        planned   = try c.decodeIfPresent([PlannedBlock].self, forKey: .planned) ?? []
        actual    = try c.decodeIfPresent([ActualBlock].self, forKey: .actual) ?? []
        summary   = try c.decodeIfPresent(DaySummary.self, forKey: .summary) ?? DaySummary()
        breaker   = try c.decodeIfPresent(BreakerDay.self, forKey: .breaker) ?? BreakerDay()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        revision  = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        exportState = try c.decodeIfPresent(ExportState.self, forKey: .exportState)

        // 下限迁移：老版本把下限做成 TODO 上的一个标记。
        // 如果新字段还没有、而 TODO 里有一条标了 .floor，就把它搬过来并从列表里移除，
        // 免得同一件事出现两遍。
        if let f = try c.decodeIfPresent(FloorItem.self, forKey: .floor) {
            floor = f
        } else if let legacy = todos.first(where: { $0.kind == .floor }) {
            floor = FloorItem()
            floor.text = legacy.text
            floor.status = legacy.status
            todos.removeAll { $0.id == legacy.id }
        }
    }

    /// 最重要 = 列表里的第一条。**顺序即优先级**，不再单独打标记。
    /// 用户的原话：「TODO 重要性按照顺序排列，重要性由高到低，可自行拖拽调整」。
    /// 位置本身就是判断，比再加一个徽章更难糊弄自己。
    var mitTodo: Todo? { orderedTodos.first }

    var floorStatus: ItemStatus { floor.status }
    var mitStatus: ItemStatus   { mitTodo?.status ?? .notRecorded }

    var orderedTodos: [Todo] { todos.sorted { $0.order < $1.order } }

    /// 挂件展示顺序：就是优先级顺序。
    var widgetTodos: [Todo] { orderedTodos }

    /// 拖拽调整优先级。
    mutating func moveTodos(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = orderedTodos
        list.move(fromOffsets: source, toOffset: destination)
        for (i, t) in list.enumerated() {
            if let idx = todos.firstIndex(where: { $0.id == t.id }) { todos[idx].order = i }
        }
    }

    mutating func normalize() {
        todos.sort { $0.order < $1.order }
        for i in todos.indices {
            todos[i].order = i
            todos[i].kind = .normal      // 顺序即优先级之后，kind 不再承载语义
        }
        planned.sort { $0.startMinute < $1.startMinute }
        actual.sort { $0.start < $1.start }
    }
}

// MARK: - 使用监控

/// append-only 事件日志的一条。永不改写。
///
/// `idleStart` 的时间戳会**回溯**到 `now - idle`，可能落在若干条更晚的 heartbeat
/// 之后。仅按 `t` 排序不稳定，必须用 (t, runId, seq) 三元组定序。
struct UsageEvent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case activate
        case idleStart, idleEnd
        case sleep, wake
        case sessionInactive, sessionActive
        case heartbeat
        case appStart, appStop
    }

    var t: Date
    var e: Kind
    /// 本次应用运行的唯一 id；进程重启后 seq 归零，靠 runId 区分。
    var runId: String
    /// 本次运行内单调递增。
    var seq: Int
    var tz: String
    var bundleId: String?
    var name: String?
}

/// 稳定定序：(t, runId, seq)
func usageEventsSorted(_ events: [UsageEvent]) -> [UsageEvent] {
    events.sorted {
        if $0.t != $1.t { return $0.t < $1.t }
        if $0.runId != $1.runId { return $0.runId < $1.runId }
        return $0.seq < $1.seq
    }
}

/// reducer 的纯函数产物，可随时从事件日志重建。
struct UsageInterval: Codable, Identifiable, Hashable, Sendable {
    var bundleId: String
    var appName: String
    var start: Date
    var end: Date
    /// 这段活动**实际发生时**所在的时区，从开启该区间的 `UsageEvent.tz` 传播而来。
    /// 不能丢：丢了之后「从监控填充」只能拿记录的时区去盖，
    /// 会把纽约 09:00 的活动写成珀斯 21:00 —— 那是把错误事实写进 DayRecord。
    var timeZoneIdentifier: String = TimeZone.current.identifier

    /// **确定性** id，不用随机 UUID —— 否则同样的事件重跑 reducer 会产生不等的结果，
    /// 幂等性就无法断言。
    var id: String { "\(bundleId)|\(Int(start.timeIntervalSince1970))|\(Int(end.timeIntervalSince1970))" }

    var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct UsageDay: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = UsageDay.currentSchemaVersion
    var date: String
    var intervals: [UsageInterval] = []
    /// 数据可能不完整（崩溃后按最后 heartbeat 闭合）。
    var truncated: Bool = false

    func totals() -> [(bundleId: String, name: String, seconds: TimeInterval)] {
        var acc: [String: (String, TimeInterval)] = [:]
        for iv in intervals {
            let cur = acc[iv.bundleId] ?? (iv.appName, 0)
            acc[iv.bundleId] = (cur.0, cur.1 + iv.seconds)
        }
        return acc.map { (bundleId: $0.key, name: $0.value.0, seconds: $0.value.1) }
            .sorted { $0.seconds > $1.seconds }
    }

    var totalSeconds: TimeInterval { intervals.reduce(0) { $0 + $1.seconds } }
}
