import SwiftUI

/// 带本地缓冲的文本框。
///
/// 为什么需要：所有编辑都走 `DayStore.mutate`，每次按键都会替换整个 `DayRecord`
/// 并触发视图重建。如果 TextField 直接绑定到模型派生值，每次重建都会拿到一个新的
/// Binding，光标位置有可能被重置。让每行自己持有文本状态，把「显示」与「持久化」
/// 解耦：显示永远来自本地缓冲，模型变化只在**未获得焦点**时回灌。
struct BufferedTextField: View {
    var placeholder: String = ""
    let value: String
    var font: Font = .system(size: 12)
    let onChange: (String) -> Void

    @State private var text: String = ""
    @State private var primed = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .focused($focused)
            .onAppear {
                text = value
                primed = true
            }
            .onChange(of: value) { _, newValue in
                // 外部（例如切换日期、从监控填充）改动时才回灌，避免打断正在输入的人
                if !focused, newValue != text { text = newValue }
            }
            .onChange(of: text) { _, newValue in
                guard primed, focused, newValue != value else { return }
                onChange(newValue)
            }
            .onChange(of: focused) { _, isFocused in
                // 失焦时补一次提交，覆盖「粘贴后立即失焦」这类路径
                if !isFocused, text != value { onChange(text) }
            }
    }
}
