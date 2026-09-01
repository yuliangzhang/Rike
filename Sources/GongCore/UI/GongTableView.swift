import SwiftUI
import AppKit

/// 「工」字表 —— 本应用的核心。
/// 上横 TODO（通栏）／ 中竖 计划|实际（左右内缩，形成工字剪影）／ 下横 总结（通栏）
struct GongTableView: View {
    @ObservedObject var store: DayStore
    @ObservedObject var settings: SettingsStore

    @State private var newTodoText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case newTodo, todo(UUID), touched, freeText }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBand          // 工 · 上横
                stem             // 工 · 中竖
                bottomBand       // 工 · 下横
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 工 · 上横：今日 TODO

    private var topBand: some View {
        GongBand(title: "今日 TODO", trailing: AnyView(dateNav)) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.record.widgetTodos) { todo in
                    todoRow(todo)
                }
                HStack(spacing: 8) {
                    Text("＋").font(Theme.monoSized(12)).foregroundStyle(.tertiary)
                        .frame(width: 62, alignment: .trailing)
                    TextField("新增任务，回车确认", text: $newTodoText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focusedField, equals: .newTodo)
                        .onSubmit(addTodo)
                }
                .padding(.top, 2)
            }
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(spacing: 8) {
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
                              value: todo.text, font: .system(size: 13)) { v in
                store.mutate { rec in
                    if let i = rec.todos.firstIndex(where: { $0.id == todo.id }) {
                        rec.todos[i].text = v
                    }
                }
            }
            .foregroundStyle(todo.status == .done ? .secondary : .primary)
            .strikethrough(todo.status == .done, color: .secondary)

            Button {
                store.mutate { rec in rec.todos.removeAll { $0.id == todo.id } }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("删除")
        }
    }

    /// 下限 / 最重要各限一条 —— 约束在模型层，UI 只是它的投影。
    private func kindBadge(_ todo: Todo) -> some View {
        Menu {
            Button("⌂ 下限（再累也做得到）") { setKind(.floor, todo) }
            Button("★ 最重要（做成了今天就不白过）") { setKind(.mit, todo) }
            Button("· 普通") { setKind(.normal, todo) }
        } label: {
            Text(todo.kind == .normal ? "·" : "\(todo.kind.marker) \(todo.kind.label)")
                .font(Theme.monoSized(9))
                .foregroundStyle(badgeColor(todo.kind))
                .frame(width: 62, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func badgeColor(_ k: TodoKind) -> Color {
        switch k {
        case .floor:  return Theme.actual
        case .mit:    return Theme.warn
        case .normal: return Color.secondary.opacity(0.6)
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
        HStack(spacing: 8) {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Text(store.record.key.displayLabel)
                .font(Theme.monoSized(12))
                .frame(minWidth: 122)
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
            Button("今天") { goToday() }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
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
        DayTimelineProjection.project(record: store.record, now: Date())
    }

    private var stem: some View {
        VStack(spacing: 10) {
            let proj = projection
            RibbonView(projection: proj)
            if !proj.outOfRange.isEmpty { outOfRangeNote(proj.outOfRange) }
            HStack(alignment: .top, spacing: 0) {
                plannedColumn
                Divider().overlay(Theme.hairline)
                actualColumn
            }
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 52)          // 内缩 → 工字剪影
        .padding(.vertical, 16)
    }

    /// 有实际记录落在当日投影范围之外时，明确告知——绝不静默隐藏数据。
    private func outOfRangeNote(_ blocks: [OutOfRangeBlock]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(blocks.count) 条实际记录落在该日时间轴之外")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.warn)
            Text("这一天按 \(store.record.key.timeZoneIdentifier) 的日界投影。以下记录发生在该范围外，画不到轴上，但仍在记录里，也会正常导出。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(blocks) { b in
                Text("· \(b.label)（\(b.timeZoneIdentifier)）\(b.title)")
                    .font(Theme.monoSized(10)).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warn.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.warn.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var plannedColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            columnHeader("计划", color: Theme.plan,
                         sum: GongTime.formatMinutesDuration(
                            store.record.planned.reduce(0) { $0 + $1.durationMinutes }))

            ForEach(store.record.planned) { blk in
                HStack(spacing: 8) {
                    timeField(text: GongTime.formatMinutes(blk.startMinute)) { m in
                        updatePlanned(blk.id) { $0.setRange(start: m, end: $0.endMinute) }
                    }
                    Text("至").font(.system(size: 10)).foregroundStyle(.tertiary)
                    timeField(text: GongTime.formatMinutes(blk.endMinute)) { m in
                        updatePlanned(blk.id) { $0.setRange(start: $0.startMinute, end: m) }
                    }
                    BufferedTextField(contextID: ctx("planned", blk.id.uuidString),
                                      placeholder: "内容", value: blk.title) { v in
                        updatePlanned(blk.id) { $0.title = v }
                    }
                    deleteButton { store.mutate { $0.planned.removeAll { $0.id == blk.id } } }
                }
            }

            Button("＋ 新增计划") {
                store.mutate { rec in
                    let last = rec.planned.last?.endMinute ?? (9 * 60)
                    rec.planned.append(PlannedBlock(start: last, end: min(last + 60, 1440)))
                }
            }
            .buttonStyle(.plain).font(Theme.monoSized(10)).foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actualColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            columnHeader("实际", color: Theme.actual,
                         sum: GongTime.formatDuration(
                            store.record.actual.reduce(0) { $0 + $1.durationSeconds }))

            ForEach(store.record.actual) { blk in
                HStack(spacing: 8) {
                    Text(actualRange(blk))
                        .font(Theme.monoSized(11)).foregroundStyle(.secondary)
                        .frame(width: 96, alignment: .leading)
                    BufferedTextField(contextID: ctx("actual", blk.id.uuidString),
                                      placeholder: "内容", value: blk.title) { v in
                        store.mutate { rec in
                            if let i = rec.actual.firstIndex(where: { $0.id == blk.id }) {
                                rec.actual[i].title = v
                            }
                        }
                    }
                    deleteButton { store.mutate { $0.actual.removeAll { $0.id == blk.id } } }
                }
            }

            HStack(spacing: 12) {
                Button("＋ 新增") { addActualManually() }
                    .buttonStyle(.plain).font(Theme.monoSized(10)).foregroundStyle(.secondary)
                Button("⟲ 从监控填充") { fillFromMonitor() }
                    .buttonStyle(.plain).font(Theme.monoSized(10)).foregroundStyle(.secondary)
                    .disabled(store.usage == nil)
                    .help("把今天前台停留超过 10 分钟的应用区间填入实际列")
            }
            .padding(.top, 2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func columnHeader(_ title: String, color: Color, sum: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            Spacer()
            Text("共 \(sum)").font(Theme.monoSized(9)).foregroundStyle(.tertiary)
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func timeField(text: String, onCommit: @escaping (Int) -> Void) -> some View {
        TimeEntryField(initial: text, onCommit: onCommit)
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 8)) }
            .buttonStyle(.plain).foregroundStyle(.tertiary)
    }

    private func updatePlanned(_ id: UUID, _ change: (inout PlannedBlock) -> Void) {
        store.mutate { rec in
            if let i = rec.planned.firstIndex(where: { $0.id == id }) { change(&rec.planned[i]) }
        }
    }

    private func actualRange(_ blk: ActualBlock) -> String {
        let cal = store.record.key.calendar
        func hm(_ d: Date) -> String {
            String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
        }
        return "\(hm(blk.start)) 至 \(hm(blk.end))"
    }

    private func addActualManually() {
        let now = Date()
        store.mutate { rec in
            rec.actual.append(ActualBlock(start: now, end: now.addingTimeInterval(3600),
                                          title: "", source: .manual))
        }
    }

    /// R6 的回报：把真实的前台区间转成「实际」条目。
    private func fillFromMonitor() {
        guard let usage = store.usage else { return }
        let merged = usage.intervals.filter { $0.seconds >= 600 }   // 10 分钟以上才值得记
        guard !merged.isEmpty else {
            store.mutate { _ in }
            return
        }
        store.mutate { rec in
            for iv in merged {
                let exists = rec.actual.contains {
                    $0.source == .monitor && abs($0.start.timeIntervalSince(iv.start)) < 60
                }
                guard !exists else { continue }
                rec.actual.append(ActualBlock(start: iv.start, end: iv.end,
                                              timeZoneIdentifier: rec.key.timeZoneIdentifier,
                                              title: iv.appName, source: .monitor))
            }
        }
    }

    // MARK: - 工 · 下横：今日总结

    private var bottomBand: some View {
        GongBand(title: "今日总结", trailing: AnyView(statusLine)) {
            VStack(alignment: .leading, spacing: 12) {
                labeledEditor("触动", hint: "今天最触动我的一件事，好坏都算，写细",
                              value: store.record.summary.touched) { v in
                    store.mutate { $0.summary.touched = v }
                }

                clarityBlock

                labeledEditor("备注", hint: "可留空",
                              value: store.record.summary.freeText) { v in
                    store.mutate { $0.summary.freeText = v }
                }
            }
        }
    }

    /// 中性措辞：「已完成 / 未记录」，不是「✓ 达成 / ✗ 未达成」。
    private var statusLine: some View {
        HStack(spacing: 14) {
            Text("下限：\(store.record.floorStatus.label)")
            Text("最重要：\(store.record.mitStatus.label)")
        }
        .font(Theme.monoSized(10))
        .foregroundStyle(.secondary)
    }

    private var clarityBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("模糊清单").font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
                Spacer()
                Button("＋ 拆解一条") {
                    store.mutate { $0.summary.clarity.append(ClarityEntry()) }
                }
                .buttonStyle(.plain).font(Theme.monoSized(10)).foregroundStyle(.secondary)
            }
            ForEach(store.record.summary.clarity) { entry in
                ClarityRow(entry: entry, store: store)
            }
        }
    }

    private func labeledEditor(_ label: String, hint: String,
                               value: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.monoSized(9)).foregroundStyle(.tertiary).tracking(1)
            BufferedTextEditor(contextID: ctx("summary", label), value: value,
                               hint: hint, onChange: onChange)
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
        VStack(alignment: .leading, spacing: 3) {
            field("01 卡住的具体位置", entry.stuckOn) { v in update { $0.stuckOn = v } }
            field("02 真正想逃开的是", entry.escapingFrom) { v in update { $0.escapingFrom = v } }
            field("03 最坏情况", entry.worstCase) { v in update { $0.worstCase = v } }
            field("04 明天 30 分钟内的第一步", entry.firstStep) { v in update { $0.firstStep = v } }
            HStack {
                // 第 04 栏是完成判据 —— 没拆出动作就不算写完
                Text(entry.isComplete ? "已拆出具体动作" : "第 04 栏还空着，没拆出动作就不算写完")
                    .font(Theme.monoSized(9))
                    .foregroundStyle(entry.isComplete ? Theme.actual : Theme.warn)
                Spacer()
                Button("删除") {
                    store.mutate { $0.summary.clarity.removeAll { $0.id == entry.id } }
                }
                .buttonStyle(.plain).font(Theme.monoSized(9)).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func field(_ label: String, _ value: String,
                       _ set: @escaping (String) -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Theme.monoSized(9)).foregroundStyle(.tertiary)
                .frame(width: 168, alignment: .leading)
            BufferedTextField(contextID: "\(dayKey)|clarity|\(entry.id.uuidString)|\(label)",
                              value: value, onChange: set)
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
private struct TimeEntryField: View {
    let initial: String
    let onCommit: (Int) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Theme.monoSized(11))
            .frame(width: 44)
            .focused($focused)
            .onAppear { text = initial }
            .onChange(of: initial) { _, new in if !focused { text = new } }
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        if let m = GongTime.parseMinutes(text) {
            onCommit(m)
        } else {
            text = initial       // 解析失败就还原，不静默吞掉
        }
    }
}
