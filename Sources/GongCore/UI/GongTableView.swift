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
    @State private var showDatePicker = false
    @State private var draggingTodo: UUID?
    @State private var dropTarget: UUID?
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
            VStack(alignment: .leading, spacing: 12) {
                floorRow
                todoList
            }
        }
    }

    // MARK: 下限（独立于 TODO）

    /// 下限单独一行，不混在 TODO 里。
    /// 用户的原话：「下限可能不是 TODO List 中的」——比如「今天必须在 23:00 前睡觉」。
    /// 那不是一件要做的工作，是一条今天无论如何都要守住的线；
    /// 塞进工作清单会被淹掉，也就失去了「再累也做得到」的意思。
    private var floorRow: some View {
        HStack(spacing: 10) {
            Text(TodoKind.floor.marker)
                .font(Theme.ui(Theme.Size.body, .semibold))
                .foregroundStyle(Theme.actual)
                .frame(width: 16)
            Text(L(.kindFloor))
                .font(Theme.ui(Theme.Size.label, .semibold))
                .foregroundStyle(Theme.actual)
                .frame(width: 40, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { store.record.floor.status == .done },
                set: { on in store.mutate { $0.floor.status = on ? .done : .notRecorded } }))
                .labelsHidden().toggleStyle(.checkbox)

            BufferedTextField(contextID: ctx("floor", "text"),
                              placeholder: L(.floorPlaceholder),
                              value: store.record.floor.text,
                              font: Theme.ui(Theme.Size.body)) { v in
                store.mutate { $0.floor.text = v }
            }
            .foregroundStyle(store.record.floor.status == .done ? Theme.muted : Theme.ink)
            .strikethrough(store.record.floor.status == .done, color: Theme.faint)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Theme.actual.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(Theme.actual).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
    }

    // MARK: TODO 列表（顺序即优先级）

    private var todoList: some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(text: L(.todoPriorityHint))
                .padding(.bottom, 2)

            // 用普通 VStack 而不是 List：List 自带滚动与行高管理，
            // 嵌在外层 ScrollView 里会互相抢，行高也只能靠猜。
            // 拖拽用 onDrag/onDrop 自己接，布局完全可控。
            ForEach(Array(store.record.orderedTodos.enumerated()), id: \.element.id) { idx, todo in
                todoRow(todo, rank: idx)
                    .background(dropTarget == todo.id
                                ? Theme.plan.opacity(0.12) : Color.clear)
                    .overlay(alignment: .top) {
                        // 拖到哪儿，哪儿就出现一条插入线
                        if dropTarget == todo.id {
                            Rectangle().fill(Theme.plan).frame(height: 2)
                        }
                    }
                    .onDrag {
                        draggingTodo = todo.id
                        return NSItemProvider(object: todo.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], isTargeted: Binding(
                        get: { dropTarget == todo.id },
                        set: { on in dropTarget = on ? todo.id : (dropTarget == todo.id ? nil : dropTarget) }
                    )) { _ in
                        defer { draggingTodo = nil; dropTarget = nil }
                        guard let from = draggingTodo,
                              let src = store.record.orderedTodos.firstIndex(where: { $0.id == from })
                        else { return false }
                        // SwiftUI 的 move 语义：往下移时目标要 +1
                        let dst = src < idx ? idx + 1 : idx
                        store.mutate { $0.moveTodos(fromOffsets: IndexSet(integer: src), toOffset: dst) }
                        return true
                    }
            }

            HStack(spacing: 10) {
                Text("＋").font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
                    .frame(width: 46, alignment: .trailing)
                TextField(L(.todoPlaceholder), text: $newTodoText)
                    .textFieldStyle(.plain)
                    .font(Theme.ui(Theme.Size.body))
                    .focused($focusedField, equals: .newTodo)
                    .onSubmit(addTodo)
            }
            .padding(.top, 4)
        }
    }

    private func todoRow(_ todo: Todo, rank: Int) -> some View {
        HStack(spacing: 10) {
            // 排名即优先级。第一条是今天的「最重要」，用 ★ 点出来——
            // 位置本身就是判断，不需要再让人手动打一个标记。
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint.opacity(0.7))
                    .help(L(.todoDragHelp))
                Text(rank == 0 ? TodoKind.mit.marker : "\(rank + 1)")
                    .font(Theme.mono(Theme.Size.label, rank == 0 ? .bold : .regular))
                    .foregroundStyle(rank == 0 ? Theme.mark : Theme.faint)
            }
            .frame(width: 46, alignment: .trailing)

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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
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

    /// 日期导航。
    ///
    /// 使用场景是明确的：昨天的计划今早补总结、看到未来的会议先跳过去记一笔。
    /// 所以除了左右各一天，还必须能**直接跳到任意一天**——靠点箭头翻五次不叫能用。
    ///
    /// 三条路都给：箭头（相邻一天）、点日期开日历（任意一天）、键盘（⌘← ⌘→ ⌘T）。
    private var dateNav: some View {
        HStack(spacing: 6) {
            navArrow("chevron.left", -1)

            // 点日期 → 日历弹出，任意一天直达
            Button { showDatePicker.toggle() } label: {
                HStack(spacing: 6) {
                    Text(store.record.key.displayLabel)
                        .font(Theme.mono(Theme.Size.meta, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .frame(minWidth: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.rule))
            .help(L(.pickDateHelp))
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                datePickerPopover
            }

            navArrow("chevron.right", 1)

            Button(L(.today)) { goToday() }
                .buttonStyle(.plain)
                .font(Theme.ui(Theme.Size.meta, .medium))
                .foregroundStyle(isToday ? Theme.faint : Theme.plan)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .contentShape(Rectangle())
                .disabled(isToday)
                .keyboardShortcut("t", modifiers: .command)
        }
    }

    /// 箭头按钮。给足点击面积并显式声明 contentShape ——
    /// 只画一个 chevron 的话可点区域就只有那几笔的墨迹。
    private func navArrow(_ symbol: String, _ delta: Int) -> some View {
        Button { shiftDay(delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.plan)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(delta < 0 ? .leftArrow : .rightArrow, modifiers: .command)
        .help(delta < 0 ? L(.prevDayHelp) : L(.nextDayHelp))
    }

    private var isToday: Bool {
        store.record.key.date == GongTime.dayKey(Date(), timeZone: store.record.key.timeZone)
    }

    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("", selection: Binding(
                get: {
                    GongTime.date(fromDayKey: store.record.key.date,
                                  timeZone: store.record.key.timeZone) ?? Date()
                },
                set: { picked in
                    showDatePicker = false
                    resignFocusBeforeDayChange()
                    Task { await store.load(dayKey: DayKey(picked,
                                                           timeZone: store.record.key.timeZone)) }
                }),
                displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(width: 260)
        }
        .padding(14)
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
                Text("· \(b.label)\(L(.punctParenOpen))\(b.timeZoneIdentifier)\(L(.punctParenClose)) \(b.title)")
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
            VStack(alignment: .leading, spacing: 20) {
                labeledEditor(L(.summaryTouched), hint: L(.summaryTouchedHint),
                              value: store.record.summary.touched, serif: true) { v in
                    store.mutate { $0.summary.touched = v }
                }

                winsBlock

                labeledEditor(L(.summaryTomorrow), hint: L(.summaryTomorrowHint),
                              value: store.record.summary.tomorrow, serif: true) { v in
                    store.mutate { $0.summary.tomorrow = v }
                }

                clarityBlock

                labeledEditor(L(.summaryNote), hint: L(.summaryNoteHint),
                              value: store.record.summary.freeText, serif: true) { v in
                    store.mutate { $0.summary.freeText = v }
                }
            }
        }
    }

    // MARK: 成功日记

    /// 《小狗钱钱》的成功日记：每天记下几件**自己做成的小事**。
    /// 和「触动」区别开——触动可以是坏的，这里只记做成的。
    /// 不设上限也不打分，写几条都算数（提示写 3~5 条，但空着也不报错）。
    private var winsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                MicroLabel(text: L(.summaryWins))
                Text(L(.summaryWinsHint))
                    .font(Theme.ui(Theme.Size.label)).foregroundStyle(Theme.faint)
                Spacer()
                Button(L(.summaryWinsAdd)) {
                    store.mutate { $0.summary.wins.append(WinEntry()) }
                }
                .buttonStyle(.plain).font(Theme.ui(Theme.Size.label, .medium))
                .foregroundStyle(Theme.muted)
            }
            if store.record.summary.wins.isEmpty {
                Text(L(.summaryWinsEmpty))
                    .font(Theme.serif(Theme.Size.body)).foregroundStyle(Theme.faint)
                    .padding(.vertical, 3)
            }
            ForEach(Array(store.record.summary.wins.enumerated()), id: \.element.id) { idx, win in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(idx + 1)")
                        .font(Theme.mono(Theme.Size.label)).foregroundStyle(Theme.actual)
                        .frame(width: 18, alignment: .trailing)
                        .padding(.top, 2)
                    BufferedTextField(contextID: ctx("win", win.id.uuidString),
                                      placeholder: L(.summaryWinsPlaceholder),
                                      value: win.text,
                                      font: Theme.serif(Theme.Size.bodyLarge)) { v in
                        store.mutate { rec in
                            if let i = rec.summary.wins.firstIndex(where: { $0.id == win.id }) {
                                rec.summary.wins[i].text = v
                            }
                        }
                    }
                    Button {
                        store.mutate { $0.summary.wins.removeAll { $0.id == win.id } }
                    } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
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
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Theme.inset)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
    }

    /// 一行 = 标签列 + 分隔线 + 输入列。
    ///
    /// 改前两列之间什么都没有，输入框也没有边框，光标停在一片空白里，
    /// 看不出哪儿能写、写到哪儿为止。现在：标签列右侧一条竖线把两列分开，
    /// 输入区给底色和下划线，聚焦时下划线变亮。
    private func field(_ label: String, _ value: String,
                       _ set: @escaping (String) -> Void) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(Theme.ui(Theme.Size.label, .medium)).foregroundStyle(Theme.muted)
                .frame(width: 210, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)   // 英文更长，允许折行而不是截断
                .padding(.trailing, 12)
                .padding(.vertical, 6)

            Rectangle().fill(Theme.rule).frame(width: 1)        // 两列之间的分隔线

            BufferedTextField(contextID: "\(dayKey)|clarity|\(entry.id.uuidString)|\(label)",
                              placeholder: "…",
                              value: value, font: Theme.ui(Theme.Size.body), onChange: set)
                .padding(.leading, 12)
                .padding(.vertical, 6)
        }
        .background(Theme.surface.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
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
///
/// **为什么是 NSViewRepresentable 而不是 SwiftUI 的 TextField：**
/// 需要「点进来就整段选中」——框里是 21:16 时直接敲 1400 就该变成 14:00，
/// 而不是插成 `21:161400`。而这件事**只能挂在 mouseDown 之后**：
/// `NSTextField.mouseDown` 会跑一个模态跟踪循环直到 mouseUp，循环期间它照样泵 runloop，
/// 所以挂在 SwiftUI `@FocusState` 变化上的 `DispatchQueue.main.async` 会在**循环内部**执行，
/// 随后到来的 mouseUp 又把插入点设回点击位置，选区就没了。
/// （这条是实测出来的：模拟 0ms 的瞬时点击会「通过」，模拟真人的 80ms 按住就复现问题。）
/// `super.mouseDown` 返回时跟踪循环已经结束、mouseUp 已处理完，那时再全选才稳。
struct TimeEntryField: View {
    enum Style { case plan, actual }

    let initial: String
    var style: Style = .plan
    let onCommit: (Int) -> Void

    @State private var editing = false

    var body: some View {
        SelectAllOnClickField(initial: initial,
                              color: style == .plan ? Theme.nsPlan : Theme.nsActual,
                              editing: $editing,
                              onCommit: onCommit)
            .frame(width: 52, height: 17)
            .padding(.vertical, 2)
            .background(background)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        switch style {
        case .plan:
            shape.strokeBorder(Theme.plan.opacity(editing ? 0.9 : 0.55),
                               style: StrokeStyle(lineWidth: 1, dash: [3.5, 2.5]))
        case .actual:
            ZStack {
                shape.fill(Theme.actualBG)
                shape.strokeBorder(Theme.actual.opacity(editing ? 0.9 : 0.35), lineWidth: 1)
            }
        }
    }

    /// 只留数字和一个冒号，最长 5 个字符（`09:30`）。
    /// 全角冒号归一成半角——中文输入法下敲出来的是全角。
    ///
    /// **必须幂等**：`controlTextDidChange` 里回写会再触发一次通知，不幂等就是无限循环。
    static func sanitize(_ raw: String) -> String {
        var out = ""
        var sawColon = false
        for ch in raw {
            guard out.count < 5 else { break }
            if ch.isNumber {
                out.append(ch)
            } else if ch == ":" || ch == "：", !sawColon {
                out.append(":")
                sawColon = true
            }
        }
        return out
    }
}

// MARK: 点击即全选的 NSTextField

/// 点进来就整段选中的文本框。
final class ClickSelectsAllTextField: NSTextField {
    /// 鼠标点击进入时全选。
    ///
    /// 关键在于时机：`super.mouseDown` 内部会一直跑到 mouseUp 才返回，
    /// 所以**返回之后**再全选，才不会被 mouseUp 的插入点定位覆盖掉。
    override func mouseDown(with event: NSEvent) {
        // 已经在编辑中的再点一下，是想定位光标（比如只改分钟），此时不要全选
        let alreadyEditing = currentEditor() != nil
        super.mouseDown(with: event)
        guard !alreadyEditing else { return }

        selectText(nil)
        // 兜底再排一次。`super.mouseDown` 什么时候返回、mouseUp 什么时候把插入点
        // 设回点击位置，取决于跟踪循环的实现细节——我用合成事件测过，不同的按住时长
        // 结果并不一致，说明这个时序不该被当成保证。多排一轮 runloop 的代价是零
        // （已经全选时这是无害的重复），但能挡住「跟踪循环提前返回」的那一支。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentEditor() != nil else { return }
            self.selectText(nil)
        }
    }

    /// Tab / 程序设焦点进来时也全选。这条路径没有跟踪循环，直接选即可。
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { currentEditor()?.selectAll(nil) }
        return ok
    }
}

private struct SelectAllOnClickField: NSViewRepresentable {
    let initial: String
    let color: NSColor
    @Binding var editing: Bool
    let onCommit: (Int) -> Void

    func makeNSView(context: Context) -> ClickSelectsAllTextField {
        let tf = ClickSelectsAllTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.alignment = .center
        tf.lineBreakMode = .byClipping
        tf.cell?.usesSingleLineMode = true
        tf.font = NSFont.monospacedDigitSystemFont(ofSize: Theme.Size.time, weight: .medium)
        tf.delegate = context.coordinator
        tf.stringValue = initial
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateNSView(_ tf: ClickSelectsAllTextField, context: Context) {
        context.coordinator.parent = self
        tf.textColor = color
        // 外部值变化（切日期、从监控填充）只在没人正在编辑时回灌，
        // 否则会把正在输入的半截内容冲掉。
        if tf.currentEditor() == nil, tf.stringValue != initial {
            tf.stringValue = initial
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectAllOnClickField
        init(_ parent: SelectAllOnClickField) { self.parent = parent }

        /// 边打边过滤：挡住字母、多余的冒号和第 6 个字符。
        /// 否则要等失焦才发现解析失败、整段被还原，白打一遍。
        func controlTextDidChange(_ note: Notification) {
            guard let tf = note.object as? NSTextField else { return }
            let clean = TimeEntryField.sanitize(tf.stringValue)
            guard clean != tf.stringValue else { return }
            // 回写会把光标顶到末尾。这里的输入都很短（≤5 字符），
            // 而且只有输入了非法字符才会走到这条路，可以接受。
            tf.stringValue = clean
            tf.currentEditor()?.selectedRange = NSRange(location: clean.count, length: 0)
        }

        func controlTextDidBeginEditing(_ note: Notification) {
            DispatchQueue.main.async { self.parent.editing = true }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            DispatchQueue.main.async { self.parent.editing = false }
            commit(note.object as? NSTextField)
        }

        /// 回车提交。返回 true 表示已处理，避免 AppKit 再发一声警告音。
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy sel: Selector) -> Bool {
            guard sel == #selector(NSResponder.insertNewline(_:)) else { return false }
            commit(control as? NSTextField)
            control.window?.makeFirstResponder(nil)   // 收焦点，让人看到格式化后的结果
            return true
        }

        private func commit(_ tf: NSTextField?) {
            guard let tf else { return }
            guard let m = GongTime.parseMinutes(tf.stringValue) else {
                tf.stringValue = parent.initial              // 解析失败就还原，不静默吞掉
                return
            }
            let normalized = GongTime.formatMinutes(m)
            tf.stringValue = normalized                      // 立刻显示规范化后的值
            // **值没变就不要提交**。onCommit 会走 store.mutate，
            // 而 mutate 一律 revision+1、置 dirty、重排、重建整棵视图树。
            // 只是路过一下输入框（比如去点日期箭头）也触发一次重建，
            // 会把正在进行的那次点击打断——按钮看起来「点了没反应」。
            guard normalized != parent.initial else { return }
            parent.onCommit(m)
        }
    }
}
