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

    var label: String {
        switch self {
        case .floor:  return "下限"
        case .mit:    return "最重要"
        case .normal: return ""
        }
    }
}

/// 中性状态。默认 `.notRecorded` —— `false` 读作「失败」，`notRecorded` 读作「事实」。
/// 这是「用记录代替打卡」原则的字段级落实，不要改成 Bool。
enum ItemStatus: String, Codable, Sendable {
    case notRecorded
    case done
    case skipped

    var label: String {
        switch self {
        case .notRecorded: return "未记录"
        case .done:        return "已完成"
        case .skipped:     return "已跳过"
        }
    }
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

    var scene: String {
        switch self {
        case .n1: return "卡住了，不知道怎么办"
        case .n2: return "干完硬活想放松"
        case .n3: return "随手点开"
        case .v1: return "想学东西却滑进短视频"
        case .v2: return "排队等待的空档"
        }
    }
}

/// 应用类别。用「其他」而非「干扰」——中性不评价。
enum AppCategory: String, Codable, CaseIterable, Sendable {
    case focus, neutral, other

    var label: String {
        switch self {
        case .focus:   return "专注"
        case .neutral: return "中性"
        case .other:   return "其他"
        }
    }
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

    var displayLabel: String { "\(date) \(GongTime.weekdayLabel(dayKey: date))" }
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
    var rangeLabel: String { GongTime.formatRange(startMinute, endMinute) }
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
    func rangeLabel(recordTimeZoneIdentifier: String) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        func hm(_ d: Date) -> String {
            String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
        }
        let base = "\(hm(start)) 至 \(hm(end))"
        return timeZoneIdentifier == recordTimeZoneIdentifier
            ? base
            : "\(base)（\(timeZoneIdentifier)）"
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
    mutating func setStartWallClock(_ minutes: Int) {
        guard let s = instant(wallClockMinutes: minutes, anchoredOn: start) else { return }
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

/// 注意：**不含 floorStatus / mitStatus**。
/// 那会与 `Todo.status` 构成双重事实源，导致「TODO 已完成但总结显示未记录」。
/// 下限/最重要的状态一律从 kind == .floor/.mit 的 Todo 派生。
struct DaySummary: Codable, Hashable, Sendable {
    var touched: String = ""
    var clarity: [ClarityEntry] = []
    var freeText: String = ""
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

    /// 单调递增，用于拒绝过期快照写入（防 lost update）。
    var revision: Int = 0

    var exportState: ExportState?

    var id: String { key.date }
    var date: String { key.date }

    init(key: DayKey) { self.key = key }
    init(date: String) { self.key = DayKey(date: date) }

    // MARK: 约束：下限 / 最重要各限一条

    mutating func setKind(_ kind: TodoKind, for todoId: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == todoId }) else { return }
        if kind != .normal {
            for i in todos.indices where todos[i].kind == kind && todos[i].id != todoId {
                todos[i].kind = .normal
            }
        }
        todos[idx].kind = kind
    }

    var floorTodo: Todo? { todos.first { $0.kind == .floor } }
    var mitTodo: Todo?   { todos.first { $0.kind == .mit } }

    /// 从 Todo 派生，杜绝双重事实源。
    var floorStatus: ItemStatus { floorTodo?.status ?? .notRecorded }
    var mitStatus: ItemStatus   { mitTodo?.status ?? .notRecorded }

    /// 挂件展示顺序：下限 → 最重要 → 其余按 order。
    var widgetTodos: [Todo] {
        todos.filter { $0.kind == .floor }
            + todos.filter { $0.kind == .mit }
            + todos.filter { $0.kind == .normal }.sorted { $0.order < $1.order }
    }

    mutating func normalize() {
        var seenFloor = false, seenMit = false
        for i in todos.indices {
            switch todos[i].kind {
            case .floor: if seenFloor { todos[i].kind = .normal } else { seenFloor = true }
            case .mit:   if seenMit   { todos[i].kind = .normal } else { seenMit = true }
            case .normal: break
            }
        }
        for i in todos.indices { todos[i].order = i }
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
