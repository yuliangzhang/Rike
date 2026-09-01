import SwiftUI

/// 带本地缓冲的文本框。
///
/// 为什么需要缓冲：所有编辑都走 `DayStore.mutate`，每次按键都会替换整个 `DayRecord`
/// 并触发视图重建。若 TextField 直接绑定模型派生值，每次重建都拿到新的 Binding，
/// 光标位置可能被重置（中文 IME 下尤其明显）。
///
/// **为什么必须有 contextID**：缓冲在获得焦点时会拒绝外部回灌，以免打断正在输入的人。
/// 但如果此时底层记录被换掉（例如在备注框里保持焦点、按 ⌘T 切到第二天），
/// 缓冲里仍是**前一天**的文字，下一次按键就会把它提交进新一天的记录，
/// **覆盖掉新一天已有的内容**。因此 context 一变就必须无条件重置缓冲，
/// 且只接受与当前 context 匹配的提交。
struct BufferedTextField: View {
    /// 标识「这个缓冲属于哪条记录的哪个字段」，例如 "2026-09-01|todo|<uuid>"。
    let contextID: String
    var placeholder: String = ""
    let value: String
    var font: Font = Theme.ui(Theme.Size.body)
    let onChange: (String) -> Void

    @State private var text: String = ""
    @State private var primedContext: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .focused($focused)
            .onAppear { adopt() }
            .onChange(of: contextID) { _, _ in
                // 记录被换掉了：无条件重置，即使正在输入。
                // 宁可丢掉未提交的半句，也不能把它写进另一条记录。
                adopt()
            }
            .onChange(of: value) { _, newValue in
                // 外部改动（切换日期、从监控填充）只在未获得焦点时回灌
                if !focused, newValue != text { text = newValue }
            }
            .onChange(of: text) { _, newValue in
                commit(newValue, requireFocus: true)
            }
            .onChange(of: focused) { _, isFocused in
                // 失焦时补一次提交，覆盖「粘贴后立即失焦」这类路径
                if !isFocused { commit(text, requireFocus: false) }
            }
            // context 变化时强制重建底层 NSTextField —— 只重置 @State 不够：
            // AppKit 文本控件自带 undo 栈，切日后按 ⌘Z 可能把**前一天的文本**
            // 恢复进当前 binding，而那时 primedContext 已经匹配新日，guard 拦不住。
            // 重建控件会连同 undo 栈一起丢弃。primedContext 保留作第二道防线。
            .id(contextID)
    }

    private func adopt() {
        text = value
        primedContext = contextID
    }

    private func commit(_ newValue: String, requireFocus: Bool) {
        // 只接受与当前 context 匹配的提交；过期提交直接丢弃。
        guard primedContext == contextID else { return }
        guard !requireFocus || focused else { return }
        guard newValue != value else { return }
        onChange(newValue)
    }
}

/// 多行版本。理由同上：「触动 / 备注」是长文本，中文 IME 组合输入时
/// 每个中间态都会替换整个 DayRecord，直接绑定模型容易光标跳动和输入抖动。
struct BufferedTextEditor: View {
    let contextID: String
    let value: String
    var hint: String = ""
    var minHeight: CGFloat = 56
    /// 手记区用衬线；仪表区用无衬线。由调用方决定。
    var font: Font = Theme.ui(Theme.Size.body)
    var lineSpacing: CGFloat = 2
    let onChange: (String) -> Void

    @State private var text: String = ""
    @State private var primedContext: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .font(font)
            .lineSpacing(lineSpacing)
            .foregroundStyle(Theme.ink2)
            .frame(minHeight: minHeight)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(8)
            .background(Theme.inset)
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall)
                        .strokeBorder(focused ? Theme.plan.opacity(0.5) : Theme.rule))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(hint).font(font).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 13).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .onAppear { adopt() }
            .onChange(of: contextID) { _, _ in adopt() }
            .onChange(of: value) { _, newValue in
                if !focused, newValue != text { text = newValue }
            }
            .onChange(of: text) { _, newValue in
                commit(newValue, requireFocus: true)
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(text, requireFocus: false) }
            }
            // 同上：重建底层 NSTextView 以丢弃 undo 栈
            .id(contextID)
    }

    private func adopt() {
        text = value
        primedContext = contextID
    }

    private func commit(_ newValue: String, requireFocus: Bool) {
        guard primedContext == contextID else { return }
        guard !requireFocus || focused else { return }
        guard newValue != value else { return }
        onChange(newValue)
    }
}
