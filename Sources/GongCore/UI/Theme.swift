import SwiftUI
import AppKit

// MARK: - 外观偏好

public enum AppearancePreference: String, Codable, Sendable, CaseIterable, Hashable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil                       // nil = 跟随系统
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 设计令牌
//
// 方向 C「承重」。立意：「工」字的形状就是工字钢的横截面——材料只放在受力的地方，
// 上下翼缘抗弯、中间腹板抗剪，掏空的部分本来就不承力。这正是《认知觉醒》
// 「靠设计结构而不是硬扛」和 Jim Rohn「每天几件简单的事」在工程上的同一句话。
//
// 由此定下三条硬约束：
// ① 横梁必须看得见 —— 上下横梁 3pt 实线，中段明确内缩，工字剪影要真的立起来。
// ② 不加装饰 —— 工字梁上没有一克多余的钢。不加图标点缀、渐变卡片、连续天数徽章。
// ③ 颜色只用来分「意图」与「事实」—— 计划＝虚线描边（还没发生），
//    实际＝实心填充（已经发生）。其余一律中性。
//
// 每个色都给明暗两套值，由 NSColor 的动态 provider 在运行时解析；
// 用户在设置里选「浅色／深色」时改 NSApp.appearance，这些色会跟着一起变。

enum Theme {

    // MARK: 颜色

    /// 明暗双值。**绝不写死单值**——写死的常量在深色下必然崩掉对比度。
    private static func dyn(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    private static func hex(_ v: UInt32) -> (Double, Double, Double) {
        (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    // 面
    /// 内容面：TODO 行、计划/实际两列、看板卡片坐在它上面。
    static let surface   = dyn(light: hex(0xFFFFFF), dark: hex(0x1A1D23))
    /// 横梁带底色。工字的上下两横用它，与 surface 拉开层级。
    static let band      = dyn(light: hex(0xF2F4F7), dark: hex(0x22262E))
    /// 更深一档的凹陷面（时间轴槽、模糊清单卡）。
    static let inset     = dyn(light: hex(0xEDF0F4), dark: hex(0x15181D))

    // 字
    static let ink       = dyn(light: hex(0x11151B), dark: hex(0xE7EAEF))
    static let ink2      = dyn(light: hex(0x39414D), dark: hex(0xC2C9D3))
    static let muted     = dyn(light: hex(0x6B7480), dark: hex(0x98A1AE))
    static let faint     = dyn(light: hex(0x9AA3AF), dark: hex(0x6E7681))

    // 线
    static let rule      = dyn(light: hex(0xDCE1E7), dark: hex(0x30363F))
    /// 工字的横梁。比普通分隔线重得多——结构要看得见。
    static let beam      = dyn(light: hex(0xC3CAD3), dark: hex(0x4A525D))

    // 语义：意图 vs 事实
    /// 计划＝意图，尚未发生。配虚线描边。
    static let plan      = dyn(light: hex(0x2C5F8C), dark: hex(0x79ADE0))
    static let planBG    = dyn(light: hex(0xE6EEF7), dark: hex(0x1C2E3F))
    /// 实际＝事实，已经发生。配实心填充。
    static let actual    = dyn(light: hex(0x1B6A57), dark: hex(0x5CC5A5))
    static let actualBG  = dyn(light: hex(0xE1F0EA), dark: hex(0x153029))

    /// 标记色。用于「最重要」、越界提示、其他类应用。**不表示评价**。
    static let mark      = dyn(light: hex(0x8A6420), dark: hex(0xD2A657))
    static let markBG    = dyn(light: hex(0xF6EFDF), dark: hex(0x2C2417))
    /// 唯一的硬规则、当前时刻游标。用得极少才有分量。
    static let stop      = dyn(light: hex(0x9A3B2E), dark: hex(0xE08A76))

    // 兼容旧名（逐步收敛）
    static var warn: Color   { mark }
    static var warnBG: Color { markBG }
    static var bandBG: Color { band }
    static var hairline: Color { rule }

    static func categoryColor(_ c: AppCategory) -> Color {
        switch c {
        case .focus:   return actual
        case .neutral: return plan
        case .other:   return mark
        }
    }

    // MARK: 尺度
    //
    // 旧版把标签压到 9–10pt、正文停在 13pt（macOS 控件默认值，不是阅读尺寸），
    // 一整天盯着写字会累。整体上移一档。

    enum Size {
        static let bandTitle: CGFloat = 15   // 横梁标题
        static let panelTitle: CGFloat = 14  // 面板标题
        static let body: CGFloat = 14        // 正文：TODO、块内容
        static let bodyLarge: CGFloat = 15   // 手记正文
        static let time: CGFloat = 13        // 等宽时间
        static let meta: CGFloat = 12        // 次要信息、说明段
        static let label: CGFloat = 11       // 小标签（已是下限，不再往下）
        static let gauge: CGFloat = 26       // 仪表大数
    }

    // MARK: 字体

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// 等宽。时间、数字、代码类信息一律走它，并配 tabular 数字。
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// 手记衬线。只用于「今日总结」那一横——那里是写作，不是数据。
    ///
    /// 不能直接用 `.system(design: .serif)`：它在中文下会回退到黑体，
    /// 拿不到想要的手记质感。所以中文显式指名宋体，英文用 New York。
    @MainActor
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        UILang.current == .zh
            ? .custom("Songti SC", size: size).weight(weight)
            : .system(size: size, weight: weight, design: .serif)
    }

    // 兼容旧名
    static let monoBody = Font.system(.body, design: .monospaced)
    static func monoSized(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        mono(size, weight)
    }

    // MARK: 度量

    enum Metric {
        /// 横梁厚度。工字剪影靠它立起来。
        static let beamWidth: CGFloat = 3
        /// 中段内缩量 —— 工字的腰。
        static let stemInset: CGFloat = 56
        static let bandPadH: CGFloat = 28
        static let bandPadV: CGFloat = 18
        static let radius: CGFloat = 7
        static let radiusSmall: CGFloat = 5
    }
}

// MARK: - 小标签

/// 小节标签。旧版用 9pt 等宽，太小；11pt + 字距既清楚又不抢戏。
///
/// **用 UI 字体而不是等宽**：等宽只留给数据（时刻、时长、日期、计数）。
/// 中文下等宽会回退到同一套 CJK 字形看不出差别，英文下却会让满屏标签
/// 读成终端界面——一条规则要在两种语言下都成立才算规则。
struct MicroLabel: View {
    let text: String
    var color: Color = Theme.faint
    var body: some View {
        Text(text)
            .font(Theme.ui(Theme.Size.label, .semibold))
            .tracking(0.9)
            .foregroundStyle(color)
    }
}

// MARK: - 工字的一横

/// 「工」字的上下两横：通栏、带底色、朝中段的一侧有一条 3pt 横梁。
///
/// 旧版靠 4.5% 不透明度的底色暗示结构，几乎看不见——核心形状没被表达出来，
/// 所以整体像一张没做完的表单。现在横梁是实的。
struct GongBand<Content: View>: View {
    enum Edge { case bottom, top }   // 横梁长在哪一侧

    var title: String
    var beamEdge: Edge
    var trailing: AnyView?
    /// 下横是手记，用衬线与更大的行距；上横是仪表。
    var journal: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.ui(Theme.Size.bandTitle, .bold))
                    .tracking(0.3)
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let t = trailing { t }
            }
            content
        }
        .padding(.horizontal, Theme.Metric.bandPadH)
        .padding(.vertical, journal ? Theme.Metric.bandPadV + 8 : Theme.Metric.bandPadV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(journal ? Theme.surface : Theme.band)
        .overlay(alignment: beamEdge == .bottom ? .bottom : .top) {
            Rectangle().fill(Theme.beam).frame(height: Theme.Metric.beamWidth)
        }
    }
}

// MARK: - 面板

/// 看板／阻断器／设置里的卡片。
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(Theme.ui(Theme.Size.panelTitle, .bold))
                .foregroundStyle(Theme.ink)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radius))
    }
}

/// 说明段落。全应用统一：12pt、次要色、可换行。
struct Explain: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(Theme.ui(Theme.Size.meta))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 品牌标记

/// 「工」字标 —— 双梁版：上横用计划色、下横用实际色、中间腹板中性。
/// 与应用图标同形。图标本身就说明这个 app 干什么：把意图和事实两条横梁架起来。
///
/// 比例取自图标源文件（128 见方里 x 28…100、y 30…98），
/// 这样菜单栏、挂件、图标三处是同一个形，不是三个近似的形。
struct GongMark: View {
    var size: CGFloat = 14
    /// 单色模式：菜单栏模板图这类场合用。
    var monochrome: Color?

    private let barX = 0.219, barW = 0.562
    private let topY = 0.234, barH = 0.117
    private let webX = 0.422, webW = 0.156
    private let botY = 0.648

    var body: some View {
        Canvas { ctx, s in
            let u = min(s.width, s.height)
            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
                Path(CGRect(x: x * u, y: y * u, width: w * u, height: h * u))
            }
            let top = monochrome ?? Theme.plan
            let bot = monochrome ?? Theme.actual
            let web = monochrome ?? Theme.muted
            ctx.fill(rect(barX, topY, barW, barH), with: .color(top))
            ctx.fill(rect(webX, topY + barH, webW, botY - topY - barH), with: .color(web))
            ctx.fill(rect(barX, botY, barW, barH), with: .color(bot))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
