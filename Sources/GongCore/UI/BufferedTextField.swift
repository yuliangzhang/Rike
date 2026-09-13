import SwiftUI
import AppKit

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

/// 多行版本：手记那一横的「触动 / 明天会更好 / 备注」。
///
/// **为什么不能用 SwiftUI 的 `TextEditor`：**
/// 拼音输入法在敲空格上屏之前，那串字母是以 **marked text**（未确认的组合文本）
/// 挂在底层 NSTextView 上的，还不是文字。`TextEditor` 会把每一个中间态都写回
/// binding，而这里的 binding 直通 `DayStore.mutate` —— 于是每敲一个字母就替换
/// 整个 `DayRecord`、重建整棵视图树，SwiftUI 随后把字符串重新灌回文本视图，
/// 组合中的 marked text 当场被清掉。表现就是**打着拼音，字自己退回去没了**。
///
/// 这也解释了为什么只有这三个字段犯病：全应用只有它们走 `TextEditor`，
/// 其余输入框都是单行 `TextField`，SwiftUI 在那条路上没有这个回灌动作。
///
/// 修法是在**两端**都把组合期挡住，任一端单独成立都能止血，两端都做才是结构上封死：
/// 1. `hasMarkedText()` 期间绝不往文本视图里写字符串；
/// 2. `hasMarkedText()` 期间绝不向 store 提交 —— 半个拼音不是内容，
///    它连一次视图重建都不值得触发。
struct BufferedTextEditor: View {
    let contextID: String
    let value: String
    var hint: String = ""
    var minHeight: CGFloat = 56
    /// 手记区用衬线、大一档、行距松；仪表区用无衬线。
    var serif: Bool = true
    let onChange: (String) -> Void

    /// 只跟踪「空不空」，不镜像全文：占位提示只在空↔非空翻转时才需要重画，
    /// 逐字镜像等于每敲一个字就多一次 SwiftUI 重算，白费。
    @State private var isEmpty: Bool = true
    @State private var primedContext: String = ""
    @State private var focused: Bool = false

    private var nsFont: NSFont {
        serif ? Theme.nsSerif(Theme.Size.bodyLarge) : Theme.nsUI(Theme.Size.body)
    }
    private var swiftUIFont: Font {
        serif ? Theme.serif(Theme.Size.bodyLarge) : Theme.ui(Theme.Size.body)
    }
    private var lineSpacing: CGFloat { serif ? 6 : 2 }

    var body: some View {
        IMESafeTextView(text: value,
                        minimumHeight: minHeight,
                        font: nsFont,
                        lineSpacing: lineSpacing,
                        textColor: Theme.nsInk2,
                        onEdit: { newValue in
                            isEmpty = newValue.isEmpty
                            commit(newValue)
                        },
                        onFocusChange: { focused = $0 })
            .frame(minHeight: minHeight)
            .padding(8)
            .background(Theme.inset)
            .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall)
                        .strokeBorder(focused ? Theme.plan.opacity(0.5) : Theme.rule))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
            .overlay(alignment: .topLeading) {
                if isEmpty {
                    Text(hint).font(swiftUIFont).foregroundStyle(Theme.faint)
                        .padding(.horizontal, 13).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                primedContext = contextID
                isEmpty = value.isEmpty
            }
            // 换日时整块重建：底层 NSTextView 连同它自带的 undo 栈一起丢掉，
            // 杜绝「在备注框里按 ⌘Z 把昨天的文字恢复进今天」。
            .id(contextID)
    }

    /// 只接受与当前 context 匹配的提交。
    ///
    /// 视图被 `.id` 换掉的瞬间，AppKit 可能还会给**旧的**文本视图补发一次
    /// 结束编辑通知；那一次回调带的是前一天的文字，而 `onChange` 闭包写的是
    /// store 的当前记录 —— 不拦就是把昨天的内容盖进今天。
    private func commit(_ newValue: String) {
        guard primedContext == contextID else { return }
        guard newValue != value else { return }
        onChange(newValue)
    }
}

// MARK: - 组合输入安全的 NSTextView

/// 会把焦点变化报出去的 NSTextView。
///
/// 不用 `textDidBeginEditing`：那个通知要等**第一次真正改动文本**才发，
/// 点进来还没打字的那段时间边框不会亮，人会以为没点中。
/// 第一响应者的进出才是「焦点」本身。
final class FocusReportingTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var minimumEditorHeight: CGFloat = 56

    /// Measure the laid-out text, including the empty line after a trailing Return.
    /// The outer page owns scrolling; this editor always exposes its full content.
    func contentHeight(for width: CGFloat) -> CGFloat {
        guard width > 0, let textStorage else { return 0 }
        // SwiftUI may measure several widths before choosing one. Use a separate
        // layout so measurement never resizes the live editor or disturbs its IME.
        let storage = NSTextStorage(attributedString: textStorage)
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(
            width: max(1, width - textContainerInset.width * 2),
            height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textContainer?.lineFragmentPadding ?? 5
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        var bottom = layout.usedRect(for: container).maxY
        if layout.extraLineFragmentTextContainer === container {
            bottom = max(bottom, layout.extraLineFragmentRect.maxY)
        }
        return ceil(bottom + textContainerInset.height * 2)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: max(minimumEditorHeight, contentHeight(for: bounds.width)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = newSize != frame.size
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
        if sizeChanged, window?.firstResponder === self {
            // Reveal the caret through the page's scroll view after its layout catches up.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.firstResponder === self else { return }
                let selection = self.selectedRange()
                let screenRect = self.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0),
                                                actualRange: nil)
                let caretRect = self.convert(window.convertFromScreen(screenRect), from: nil)
                self.scrollToVisible(caretRect.insetBy(dx: 0, dy: -8))
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        // 不能同步改 SwiftUI 状态：这里正处在 AppKit 的响应者切换里，
        // 同步回写会撞上「Modifying state during view update」。
        if ok { DispatchQueue.main.async { [weak self] in self?.onFocusChange?(true) } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { [weak self] in self?.onFocusChange?(false) } }
        return ok
    }
}

private struct IMESafeTextView: NSViewRepresentable {
    let text: String
    let minimumHeight: CGFloat
    let font: NSFont
    let lineSpacing: CGFloat
    let textColor: NSColor
    let onEdit: (String) -> Void
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> FocusReportingTextView {
        let tv = FocusReportingTextView()
        tv.minimumEditorHeight = minimumHeight
        tv.delegate = context.coordinator
        tv.isRichText = false                    // 纯文本：导出的是 markdown，不要富文本属性
        tv.allowsUndo = true
        tv.drawsBackground = false               // 底色由 SwiftUI 的 Theme.inset 画
        tv.textContainerInset = .zero
        // 智能标点会把 "--" 换成 "–"、直引号换成弯引号。写进 markdown 就和敲的不一样了。
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        // SwiftUI sizes the complete editor; NSTextView must not resize itself to a single line.
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: minimumHeight)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.textStorage?.setAttributedString(NSAttributedString(string: text,
                                                              attributes: attributes))
        tv.typingAttributes = attributes

        return tv
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FocusReportingTextView,
                      context: Context) -> NSSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return NSSize(width: width, height: max(minimumHeight, nsView.contentHeight(for: width)))
    }

    func updateNSView(_ tv: FocusReportingTextView, context: Context) {
        context.coordinator.parent = self
        tv.onFocusChange = onFocusChange

        // **第一道闸**：组合期一个字节都不要动。
        // 往带 marked text 的 NSTextView 里写字符串，未上屏的拼音会被直接丢掉。
        guard !tv.hasMarkedText() else { return }
        defer { tv.invalidateIntrinsicContentSize() }

        if tv.typingAttributes[.font] as? NSFont != font
            || tv.typingAttributes[.foregroundColor] as? NSColor != textColor {
            tv.typingAttributes = attributes
            tv.textStorage?.setAttributes(attributes,
                                          range: NSRange(location: 0,
                                                         length: tv.textStorage?.length ?? 0))
        }

        // 正在编辑时不回灌外部值 —— 否则会把人打到一半的内容冲掉。
        // 换日这类真正需要换内容的场合，外层 `.id(contextID)` 会整块重建，走的是
        // `makeNSView`，不依赖这条路。
        guard tv.window?.firstResponder !== tv, tv.string != text else { return }
        tv.textStorage?.setAttributedString(NSAttributedString(string: text,
                                                               attributes: attributes))
    }

    private var attributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        return [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeTextView
        init(_ parent: IMESafeTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            tv.invalidateIntrinsicContentSize()
            // **第二道闸**：组合期不提交。
            // 半个拼音不是内容，它不值得触发一次 store.mutate + 整树重建；
            // 而那次重建正是把 marked text 冲掉的东西。
            guard !tv.hasMarkedText() else { return }
            parent.onEdit(tv.string)
        }

        /// 失焦补一次。到这里 AppKit 已经结束了组合（上屏或丢弃），
        /// 覆盖「打完拼音直接点走」这条路径。
        func textDidEndEditing(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.onEdit(tv.string)
        }
    }
}
