import SwiftUI

/// 视觉语言：仪表盘式中性底 + 计划(冷)/实际(暖) 双色对照。
/// 与《注意力断路器》网页卡保持同一家族，使阻断器融进来时不像外挂。
enum Theme {
    // 计划 = 冷色（尚未发生的意图）
    static let plan      = Color(red: 0.25, green: 0.38, blue: 0.56)
    static let planBG    = Color(red: 0.25, green: 0.38, blue: 0.56).opacity(0.16)
    // 实际 = 暖绿（已经发生的事实）
    static let actual    = Color(red: 0.19, green: 0.45, blue: 0.33)
    static let actualBG  = Color(red: 0.19, green: 0.45, blue: 0.33).opacity(0.16)
    // 提示色（用于「其他」类应用与冲突提示），不用于评价
    static let warn      = Color(red: 0.66, green: 0.42, blue: 0.09)
    static let warnBG    = Color(red: 0.66, green: 0.42, blue: 0.09).opacity(0.16)
    static let stop      = Color(red: 0.66, green: 0.23, blue: 0.15)

    static let bandBG    = Color.primary.opacity(0.045)
    static let hairline  = Color.primary.opacity(0.12)

    static func categoryColor(_ c: AppCategory) -> Color {
        switch c {
        case .focus:   return actual
        case .neutral: return plan
        case .other:   return warn
        }
    }

    static let mono = Font.system(.body, design: .monospaced)
    static func monoSized(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// 「工」字剪影：上下横通栏，中段内缩。
struct GongBand<Content: View>: View {
    var title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                Spacer()
                if let t = trailing { t }
            }
            content
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bandBG)
    }
}
