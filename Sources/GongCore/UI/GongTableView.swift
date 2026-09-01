import SwiftUI
import AppKit

/// 「工」字表 —— 本应用的核心。
///
/// 上横 TODO（通栏，仪表）／ 中竖 计划|实际（左右内缩，形成工字剪影）／ 下横 总结（通栏，手记）
///
/// 方向 C「承重」：按「工」字本身的分工排版。上横与中竖是**仪表**——数据，
/// 无衬线加等宽，紧凑精确；下横是**手记**——写作，衬线加大行距。
/// 这产品本来就是记录仪和反思本两件事缝在一起，让形式承认它，比强行统一好。
struct GongTableView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore

    @State private var newTodoText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case newTodo, todo(UUID), touched, freeText }

    var body: some View {
        ScrollView { tableContent }
            .background(Theme.inset)
    }

    /// ScrollView 在 `ImageRenderer` 下不会布局内容，离屏渲染直接用这个。
    var tableContent: some View {
        VStack(spacing: 0) {
            topBand          // 工 · 上横
            stem             // 工 · 中竖
            bottomBand       // 工 · 下横
        }
    }

    // MARK: - 工 · 上横：今日 TODO

    private var topBand: some View {
        GongBand(title: L(.bandTodo), beamEdge: .bottom, trailing: AnyView(dateNav)) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(store.record.widgetTodos) { todo in
                    todoRow(todo)
                }
                HStack(spacing: 10) {
                    Text("＋").font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
                        .frame(width: 76, alignment: .trailing)
                    TextField(L(.todoPlaceholder), text: $newTodoText)
                        .textFieldStyle(.plain)
                        .font(Theme.ui(Theme.Size.body))
                        .focused($focusedField, equals: .newTodo)
                        .onSubmit(addTodo)
                }
                .padding(.top, 2)
            }
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            kindBadge(todo)
            Toggle("", isOn: Binding(
                get: { todo.status == .done },
                set: { on in
                    store.mutate { rec in
                        if let i = rec.todos.firstIndex(where: { $0.id == todo.id }) {
                            rec.todos[i].status = on ? .done : .notRecorded
                        }
                    }
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            BufferedTextField(contextID: ctx("todo", todo.id.uuidString),
                              value: todo.text,
                              font: Theme.ui(Theme.Size.body)) { v in
                store.mutate { rec in
                    if let i = rec.todos.firstIndex(where: { $0.id == todo.id }) {
                        rec.todos[i].text = v
                    }
                }
            }
            .foregroundStyle(todo.status == .done ? Theme.muted : Theme.ink)
            .strikethrough(todo.status == .done, color: Theme.faint)

            Button {
                store.mutate { rec in rec.todos.removeAll { $0.id == todo.id } }
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.faint)
            .help(L(.delete))
        }
    }

    /// 下限 / 最重要各限一条 —— 约束在模型层，UI 只是它的投影。
    private func kindBadge(_ todo: Todo) -> some View {
        Menu {
            Button(L(.kindFloorMenu))  { setKind(.floor, todo) }
            Button(L(.kindMitMenu))    { setKind(.mit, todo) }
            Button(L(.kindNormalMenu)) { setKind(.normal, todo) }
        } label: {
            Text(todo.kind == .normal ? "·" : "\(todo.kind.marker) \(todo.kind.label)")
                .font(Theme.ui(Theme.Size.label, todo.kind == .normal ? .regular : .semibold))
                .foregroundStyle(badgeColor(todo.kind))
                .frame(width: 76, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func badgeColor(_ k: TodoKind) -> Color {
        switch k {
        case .floor:  return Theme.actual
        case .mit:    return Theme.mark
        case .normal: return Theme.faint
        }
    }

    private func setKind(_ kind: TodoKind, _ todo: Todo) {
        store.mutate { rec in rec.setKind(kind, for: todo.id) }
    }

    private func addTodo() {
        let t = newTodoText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.mutate { rec in
            rec.todos.append(Todo(text: t, order: rec.todos.count))
        }
        newTodoText = ""
        focusedField = .newTodo
    }

    // MARK: 日期导航

    private var dateNav: some View {
        HStack(spacing: 10) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(store.record.key.displayLabel)
                .font(Theme.mono(Theme.Size.meta))
                .monospacedDigit()
                .foregroundStyle(Theme.ink2)
                .frame(minWidth: 128)
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            Button(L(.today)) { goToday() }
                .buttonStyle(.borderless)
                .font(Theme.ui(Theme.Size.meta))
                .keyboardShortcut("t", modifiers: .command)
        }
    }

    /// 切日期前先收掉焦点：让正在编辑的输入框走失焦提交路径，
    /// 把内容落到**当前这一天**，而不是被 contextID 重置丢掉。
    private func resignFocusBeforeDayChange() {
        focusedField = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func shiftDay(_ delta: Int) {
        resignFocusBeforeDayChange()
        let key = store.record.key
        guard let d = GongTime.date(fromDayKey: key.date, timeZone: key.timeZone),
              let next = key.calendar.date(byAdding: .day, value: delta, to: d) else { return }
        Task { await store.load(dayKey: DayKey(next, timeZone: key.timeZone)) }
    }

    private func goToday() {
        resignFocusBeforeDayChange()
        Task { await store.load(dayKey: DayKey(Date())) }
    }

    // MARK: - 工 · 中竖：Ribbon + 计划 | 实际

    private var projection: DayProjection {
        DayTimelineProjection.project(record: store.record, now: Date(), lang: UILang.current)
    }

    private var stem: some View {
        VStack(spacing: 12) {
            let proj = projection
            if let recTZ = timeZoneMismatch { timeZoneNote(recTZ) }
            RibbonView(projection: proj)
            if !proj.outOfRange.isEmpty { outOfRangeNote(proj.outOfRange) }
            HStack(alignment: .top, spacing: 0) {
                plannedColumn
                Rectangle().fill(Theme.rule).frame(width: 1)
                actualColumn
            }
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius).strokeBorder(Theme.rule))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
        }
        .padding(.horizontal, Theme.Metric.stemInset)   // 内缩 → 工字剪影
        .padding(.vertical, 20)
    }

    /// 记录时区 ≠ 当前系统时区时常驻提示。统计与时间轴都按**记录建立时的时区**
    /// 计算日界，这会让「今天」的边界与你此刻所在地不同——必须说清楚，不能让用户自己猜。
    private func timeZoneNote(_ recTZ: String) -> some View {
        calloutBox(color: Theme.plan) {
            Text(L(.tzNoteTitle, recTZ))
                .font(Theme.ui(Theme.Size.meta, .semibold)).foregroundStyle(Theme.plan)
            Explain(L(.tzNoteBody, TimeZone.current.identifier))
        }
    }

    /// 有实际记录落在当日投影范围之外时，明确告知——绝不静默隐藏数据。
    private func outOfRangeNote(_ blocks: [OutOfRangeBlock]) -> some View {
        calloutBox(color: Theme.mark) {
            Text(L(.outOfRangeTitle, blocks.count))
                .font(Theme.ui(Theme.Size.meta, .semibold)).foregroundStyle(Theme.mark)
            Explain(L(.outOfRangeBody, store.record.key.timeZoneIdentifier))
            ForEach(blocks) { b in
                Text("· \(b.label)（\(b.timeZoneIdentifier)）\(b.title)")
                    .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private func calloutBox<C: View>(color: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.09))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
    }

    private var plannedColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(L(.colPlan), color: Theme.plan,
                         sum: GongTime.formatMinutesDuration(
                            store.record.planned.reduce(0) { $0 + $1.durationMinutes }))

            ForEach(store.record.planned) { blk in
                HStack(spacing: 8) {
                    timeField(text: GongTime.formatMinutes(blk.startMinute), style: .plan,
                              id: ctx("plannedStart", blk.id.uuidString)) { m in
                        updatePlanned(blk.id) { $0.setRange(start: m, end: $0.endMinute) }
                    }
                    rangeSeparator
                    timeField(text: GongTime.formatMinutes(blk.endMinute), style: .plan,
                              id: ctx("plannedEnd", blk.id.uuidString)) { m in
                        updatePlanned(blk.id) { $0.setRange(start: $0.startMinute, end: m) }
                    }
                    BufferedTextField(contextID: ctx("planned", blk.id.uuidString),
                                      placeholder: L(.blockContent), value: blk.title,
                                      font: Theme.ui(Theme.Size.body)) { v in
                        updatePlanned(blk.id) { $0.title = v }
                    }
                    deleteButton { store.mutate { $0.planned.removeAll { $0.id == blk.id } } }
                }
            }

            Button(L(.addPlan)) {
                store.mutate { rec in
                    let last = rec.planned.last?.endMinute ?? (9 * 60)
                    rec.planned.append(PlannedBlock(start: last, end: min(last + 60, 1440)))
                }
            }
            .buttonStyle(.plain).font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.muted)
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actualColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            columnHeader(L(.colActual), color: Theme.actual,
                         sum: GongTime.formatDuration(
                            store.record.actual.reduce(0) { $0 + $1.durationSeconds }))

            ForEach(store.record.actual) { blk in
                HStack(spacing: 8) {
                    // 时间可改：我们并不是一直坐在电脑前，监控填进来的区间和
                    // 「＋新增」给的默认一小时都只是起点，必须让人改成事实。
                    timeField(text: GongTime.formatMinutes(blk.startWallClockMinutes), style: .actual,
                              id: ctx("actualStart", blk.id.uuidString)) { m in
                        updateActual(blk.id) { $0.setStartWallClock(m) }
                    }
                    rangeSeparator
                    timeField(text: GongTime.formatMinutes(blk.endWallClockMinutes), style: .actual,
                              id: ctx("actualEnd", blk.id.uuidString)) { m in
                        updateActual(blk.id) { $0.setEndWallClock(m) }
                    }
                    if let tz = blk.foreignTimeZoneLabel(
                        recordTimeZoneIdentifier: store.record.key.timeZoneIdentifier) {
                        Text(tz)
                            .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.mark)
                            .lineLimit(1).truncationMode(.middle)
                            .help(L(.foreignTZHelp, tz))
                    }
                    BufferedTextField(contextID: ctx("actual", blk.id.uuidString),
                                      placeholder: L(.blockContent), value: blk.title,
                                      font: Theme.ui(Theme.Size.body)) { v in
                        store.mutate { rec in
                            if let i = rec.actual.firstIndex(where: { $0.id == blk.id }) {
                                rec.actual[i].title = v
                            }
                        }
                    }
                    deleteButton { store.mutate { $0.actual.removeAll { $0.id == blk.id } } }
                }
            }

            HStack(spacing: 16) {
                Button(L(.addActual)) { addActualManually() }
                    .buttonStyle(.plain).font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.muted)
                Button(L(.fillFromMonitor)) { fillFromMonitor() }
                    .buttonStyle(.plain).font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.muted)
                    .disabled(store.usage == nil)
                    .help(L(.fillFromMonitorHelp))
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangeSeparator: some View {
        Text(L(.rangeSep)).font(Theme.ui(Theme.Size.meta)).foregroundStyle(Theme.faint)
    }

    private func columnHeader(_ title: String, color: Color, sum: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.ui(Theme.Size.panelTitle, .bold))
                .tracking(0.4).foregroundStyle(color)
            Spacer()
            Text(L(.colTotal, sum))
                .font(Theme.mono(Theme.Size.label)).monospacedDigit()
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(color.opacity(0.55)).frame(height: 1.5) }
        .padding(.bottom, 4)
    }

    private func timeField(text: String, style: TimeEntryField.Style, id: String,
                           onCommit: @escaping (Int) -> Void) -> some View {
        // .id() 让换日时底层 NSTextField 连同未提交内容一起重建，
        // 杜绝 r3 那类「上一天的输入落进新一天」的缺陷。
        TimeEntryField(initial: text, style: style, onCommit: onCommit).id(id)
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 9)) }
            .buttonStyle(.plain).foregroundStyle(Theme.faint)
    }

    private func updatePlanned(_ id: UUID, _ change: (inout PlannedBlock) -> Void) {
        store.mutate { rec in
            if let i = rec.planned.firstIndex(where: { $0.id == id }) { change(&rec.planned[i]) }
        }
    }

    private func updateActual(_ id: UUID, _ change: (inout ActualBlock) -> Void) {
        store.mutate { rec in
            if let i = rec.actual.firstIndex(where: { $0.id == id }) { change(&rec.actual[i]) }
        }
    }

    private func addActualManually() {
        let now = Date()
        store.mutate { rec in
            rec.actual.append(ActualBlock(start: now, end: now.addingTimeInterval(3600),
                                          title: "", source: .manual))
        }
    }

    /// 记录所属时区与当前系统时区不一致时，统计口径需要明说。
    private var timeZoneMismatch: String? {
        let recTZ = store.record.key.timeZoneIdentifier
        let sysTZ = TimeZone.current.identifier
        return recTZ == sysTZ ? nil : recTZ
    }

    /// 把真实的前台区间转成「实际」条目。
    private func fillFromMonitor() {
        guard let usage = store.usage else { return }
        let merged = usage.intervals.filter { $0.seconds >= 600 }   // 10 分钟以上才值得记
        guard !merged.isEmpty else {
            // 不要静默什么都不做 —— 说明为什么没有可填的内容
            if let recTZ = timeZoneMismatch {
                store.note(.warning, L(.noFillIntervalsTZ, recTZ, TimeZone.current.identifier))
            } else {
                store.note(.info, L(.noFillIntervals))
            }
            return
        }
        store.mutate { rec in
            for iv in merged {
                let exists = rec.actual.contains {
                    $0.source == .monitor && abs($0.start.timeIntervalSince(iv.start)) < 60
                }
                guard !exists else { continue }
                // 用区间**自己**的时区，不是记录的时区
                rec.actual.append(ActualBlock(start: iv.start, end: iv.end,
                                              timeZoneIdentifier: iv.timeZoneIdentifier,
                                              title: iv.appName, source: .monitor))
            }
        }
    }

    // MARK: - 工 · 下横：今日总结（手记）

    private var bottomBand: some View {
        GongBand(title: L(.bandSummary), beamEdge: .top,
                 trailing: AnyView(statusLine), journal: true) {
            VStack(alignment: .leading, spacing: 18) {
                labeledEditor(L(.summaryTouched), hint: L(.summaryTouchedHint),
                              value: store.record.summary.touched, serif: true) { v in
                    store.mutate { $0.summary.touched = v }
                }

                clarityBlock

                labeledEditor(L(.summaryNote), hint: L(.summaryNoteHint),
                              value: store.record.summary.freeText, serif: true) { v in
                    store.mutate { $0.summary.freeText = v }
                }
            }
        }
    }

    /// 中性措辞：「已完成 / 未记录」，不是「✓ 达成 / ✗ 未达成」。
    private var statusLine: some View {
        HStack(spacing: 16) {
            Text(L(.statusFloor, store.record.floorStatus.label))
            Text(L(.statusMit, store.record.mitStatus.label))
        }
        .font(Theme.ui(Theme.Size.label, .medium))
        .foregroundStyle(Theme.muted)
    }

    private var clarityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MicroLabel(text: L(.clarityTitle))
                Spacer()
                Button(L(.clarityAdd)) {
                    store.mutate { $0.summary.clarity.append(ClarityEntry()) }
                }
                .buttonStyle(.plain).font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.muted)
            }
            ForEach(store.record.summary.clarity) { entry in
                ClarityRow(entry: entry, store: store)
            }
        }
    }

    private func labeledEditor(_ label: String, hint: String, value: String,
                               serif: Bool = false,
                               onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: label)
            BufferedTextEditor(contextID: ctx("summary", label), value: value,
                               hint: hint,
                               font: serif ? Theme.serif(Theme.Size.bodyLarge)
                                           : Theme.ui(Theme.Size.body),
                               lineSpacing: serif ? 6 : 2,
                               onChange: onChange)
        }
    }

    /// 缓冲上下文标识：记录日期 + 字段身份。
    /// 日期一变，所有缓冲立即重置，杜绝把上一天的文字提交进新一天。
    private func ctx(_ kind: String, _ id: String) -> String {
        "\(store.record.key.date)|\(kind)|\(id)"
    }
}

// MARK: - 模糊拆解器的一行

private struct ClarityRow: View {
    let entry: ClarityEntry
    @ObservedObject var store: DayStore
    private var dayKey: String { store.record.key.date }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            field(L(.clarity01), entry.stuckOn)      { v in update { $0.stuckOn = v } }
            field(L(.clarity02), entry.escapingFrom) { v in update { $0.escapingFrom = v } }
            field(L(.clarity03), entry.worstCase)    { v in update { $0.worstCase = v } }
            field(L(.clarity04), entry.firstStep)    { v in update { $0.firstStep = v } }
            HStack {
                // 第 04 栏是完成判据 —— 没拆出动作就不算写完
                Text(entry.isComplete ? L(.clarityDone) : L(.clarityUndone))
                    .font(Theme.ui(Theme.Size.label, .medium))
                    .foregroundStyle(entry.isComplete ? Theme.actual : Theme.mark)
                Spacer()
                Button(L(.delete)) {
                    store.mutate { $0.summary.clarity.removeAll { $0.id == entry.id } }
                }
                .buttonStyle(.plain).font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
            }
            .padding(.top, 3)
        }
        .padding(11)
        .background(Theme.inset)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
    }

    private func field(_ label: String, _ value: String,
                       _ set: @escaping (String) -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.faint)
                .frame(width: 250, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)   // 英文更长，允许折行而不是截断
            BufferedTextField(contextID: "\(dayKey)|clarity|\(entry.id.uuidString)|\(label)",
                              value: value, font: Theme.ui(Theme.Size.body), onChange: set)
        }
    }

    private func update(_ change: @escaping (inout ClarityEntry) -> Void) {
        store.mutate { rec in
            if let i = rec.summary.clarity.firstIndex(where: { $0.id == entry.id }) {
                change(&rec.summary.clarity[i])
            }
        }
    }
}

// MARK: - 宽松时间输入

/// 支持 `9` / `930` / `9:30` / `09:30`，失焦或回车时解析。
///
/// 样式承载语义：**计划＝虚线描边**（意图，还没发生），**实际＝实心填充**（事实，已发生）。
/// 这比再多找一个色相更能一眼分清左右两列，而且这个区别本身有意义。
struct TimeEntryField: View {
    enum Style { case plan, actual }

    let initial: String
    var style: Style = .plan
    let onCommit: (Int) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.mono(Theme.Size.time, .medium))
            .monospacedDigit()
            .foregroundStyle(style == .plan ? Theme.plan : Theme.actual)
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .padding(.vertical, 2)
            .background(background)
            .focused($focused)
            .onAppear { text = initial }
            .onChange(of: initial) { _, new in if !focused { text = new } }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        switch style {
        case .plan:
            shape.strokeBorder(Theme.plan.opacity(focused ? 0.9 : 0.55),
                               style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5]))
        case .actual:
            ZStack {
                shape.fill(Theme.actualBG)
                shape.strokeBorder(Theme.actual.opacity(focused ? 0.9 : 0.35), lineWidth: 1)
            }
        }
    }

    private func commit() {
        if let m = GongTime.parseMinutes(text) {
            onCommit(m)
        } else {
            text = initial       // 解析失败就还原，不静默吞掉
        }
    }
}
