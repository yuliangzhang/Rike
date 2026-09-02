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

// MARK: - 主题

/// 一套主题在某一种外观（浅/深）下的全部色值。
struct Tokens: Sendable {
    let surface, band, inset: UInt32
    let ink, ink2, muted, faint: UInt32
    let rule, beam: UInt32
    let plan, planBG, actual, actualBG, mark, markBG, stop: UInt32
}

struct Palette: Sendable {
    let light: Tokens
    let dark: Tokens
}

/// 可选主题。
///
/// **只改字与色，不动结构。** 工字表的布局、横梁、内缩、
/// 「计划＝虚线／实际＝实心」这条语义在所有主题里都一样——
/// 换主题是换材质，不是换房子。
enum ThemePalette: String, Codable, CaseIterable, Sendable, Hashable {
    case structural, paper, graphite, pine

    var palette: Palette {
        switch self {
        case .structural: return Palettes.structural
        case .paper:      return Palettes.paper
        case .graphite:   return Palettes.graphite
        case .pine:       return Palettes.pine
        }
    }

    var displayName: S {
        switch self {
        case .structural: return .themeStructural
        case .paper:      return .themePaper
        case .graphite:   return .themeGraphite
        case .pine:       return .themePine
        }
    }

    var note: S {
        switch self {
        case .structural: return .themeStructuralNote
        case .paper:      return .themePaperNote
        case .graphite:   return .themeGraphiteNote
        case .pine:       return .themePineNote
        }
    }
}

/// 调色板数据。每个色都用脚本核过对比度：
/// 所有正文/标签色对 surface / band / inset 三种底色均 ≥ 4.5:1（WCAG AA 小字标准），
/// 语义色压在自己的浅底上同样 ≥ 4.5:1，横梁对相邻面 ≥ 1.6:1（看得见）。
enum Palettes {

    /// 工务 Structural —— 钢蓝 + 墨绿，中性偏冷。工程图纸式的克制，默认。
    static let structural = Palette(
        light: Tokens(surface: 0xFFFFFF, band: 0xEDF1F5, inset: 0xE5EAF0, ink: 0x0E1319, ink2: 0x2F3944, muted: 0x545E6C, faint: 0x7C8797, rule: 0xCFD7E0, beam: 0x9BA7B6, plan: 0x1B5183, planBG: 0xDEEAF6, actual: 0x115C48, actualBG: 0xD8ECE4, mark: 0x74510C, markBG: 0xF4E9D4, stop: 0x8B3020),
        dark: Tokens(surface: 0x1A1D23, band: 0x232830, inset: 0x13161B, ink: 0xEEF1F5, ink2: 0xC8CFD9, muted: 0x9CA6B3, faint: 0x717A87, rule: 0x353C47, beam: 0x525C6A, plan: 0x85B9EC, planBG: 0x152738, actual: 0x63D0AD, actualBG: 0x0E2B22, mark: 0xE0B366, markBG: 0x2A2216, stop: 0xEA9280))

    /// 宣纸 Rice Paper —— 暖纸底、墨、朱砂、竹青。长时间书写不刺眼。
    static let paper = Palette(
        light: Tokens(surface: 0xFDFBF6, band: 0xF2ECE0, inset: 0xEAE3D4, ink: 0x1A1813, ink2: 0x3B372E, muted: 0x635C4F, faint: 0x8E8677, rule: 0xD9D0BF, beam: 0xB5AB97, plan: 0x255468, planBG: 0xE0EAEF, actual: 0x3F6132, actualBG: 0xE4EBDB, mark: 0x8A4E18, markBG: 0xF5E7D4, stop: 0x993125),
        dark: Tokens(surface: 0x201E19, band: 0x292520, inset: 0x171511, ink: 0xF2EDE2, ink2: 0xD3CBBB, muted: 0xA79E8D, faint: 0x7A7264, rule: 0x3C3830, beam: 0x5A5449, plan: 0x88B6CB, planBG: 0x18272E, actual: 0x97BE84, actualBG: 0x1A2416, mark: 0xDCA063, markBG: 0x2B2217, stop: 0xE28575))

    /// 石墨 Graphite —— 近乎单色，只留一点琥珀。计划与实际靠虚线/实心区分，不靠色相。
    static let graphite = Palette(
        light: Tokens(surface: 0xFFFFFF, band: 0xEFEFEF, inset: 0xE6E6E6, ink: 0x0D0D0D, ink2: 0x2E2E2E, muted: 0x555555, faint: 0x7E7E7E, rule: 0xD2D2D2, beam: 0x9E9E9E, plan: 0x454B52, planBG: 0xE9EBED, actual: 0x14161A, actualBG: 0xE0E2E4, mark: 0x7A5500, markBG: 0xF3EAD3, stop: 0x8A2E20),
        dark: Tokens(surface: 0x1B1B1D, band: 0x242426, inset: 0x141415, ink: 0xF2F2F3, ink2: 0xCBCBCD, muted: 0x9E9EA2, faint: 0x74747A, rule: 0x36363A, beam: 0x54545A, plan: 0xAEB6C0, planBG: 0x25272B, actual: 0xF4F6F8, actualBG: 0x2C2E32, mark: 0xDDAE4A, markBG: 0x2A2317, stop: 0xE18B76))

    /// 松墨 Pine Ink —— 深绿偏蓝，安静。夜里久看不累。
    static let pine = Palette(
        light: Tokens(surface: 0xFBFCFB, band: 0xEAF0EC, inset: 0xE1E9E4, ink: 0x0E1513, ink2: 0x2C3833, muted: 0x4F5A54, faint: 0x7B8781, rule: 0xCDD8D1, beam: 0x9AA8A0, plan: 0x14586D, planBG: 0xDEEBF0, actual: 0x1F6543, actualBG: 0xDCEDE3, mark: 0x6F5310, markBG: 0xF2EAD5, stop: 0x8A3324),
        dark: Tokens(surface: 0x171B19, band: 0x1F2523, inset: 0x111514, ink: 0xEAF1ED, ink2: 0xC4CFC9, muted: 0x97A39D, faint: 0x6D7973, rule: 0x313935, beam: 0x4D5852, plan: 0x77BCD4, planBG: 0x11252C, actual: 0x6BCC9C, actualBG: 0x102820, mark: 0xD7AB5E, markBG: 0x282116, stop: 0xE28D79))
}

/// 当前生效的主题。
///
/// 只在主线程写（设置里切换），只在绘制时读（也在主线程）。
/// 之所以不是 @MainActor：`NSColor` 的动态 provider 闭包是 nonisolated 的，
/// 而正是它在解析每一次绘制的颜色——把它做成 MainActor 隔离反而没法用。
nonisolated(unsafe) var activePalette: ThemePalette = .structural

// MARK: - 设计令牌
//
// 方向 C「承重」。立意：「工」字的形状就是工字钢的横截面——材料只放在受力的地方，
// 上下翼缘抗弯、中间腹板抗剪，掏空的部分本来就不承力。这正是《认知觉醒》
// 「靠设计结构而不是硬扛」和 Jim Rohn「每天几件简单的事」在工程上的同一句话。
//
// 由此定下三条硬约束，**换主题也不改**：
// ① 横梁必须看得见 —— 上下横梁 3pt 实线，中段明确内缩。
// ② 不加装饰 —— 工字梁上没有一克多余的钢。
// ③ 颜色只用来分「意图」与「事实」—— 计划＝虚线描边，实际＝实心填充。

enum Theme {

    // MARK: 颜色

    /// 按当前主题 + 当前外观解析。
    ///
    /// **必须是计算属性而不是 `static let`**：`let` 会把 NSColor 实例连同它当时
    /// 捕获的那套色值一起缓存，切主题就不生效了。
    private static func tok(_ pick: @escaping @Sendable (Tokens) -> UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let p = activePalette.palette
            return rgb(pick(isDark ? p.dark : p.light))
        }
    }

    private static func rgb(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: Double((v >> 16) & 0xFF) / 255,
                green: Double((v >> 8) & 0xFF) / 255,
                blue: Double(v & 0xFF) / 255, alpha: 1)
    }

    // 面
    /// 内容面：TODO 行、计划/实际两列、看板卡片坐在它上面。
    static var surface: Color { Color(nsColor: tok(\.surface)) }
    /// 横梁带底色。工字的上下两横用它，与 surface 拉开层级。
    static var band: Color    { Color(nsColor: tok(\.band)) }
    /// 更深一档的凹陷面（时间轴槽、模糊清单卡）。
    static var inset: Color   { Color(nsColor: tok(\.inset)) }

    // 字
    static var ink: Color   { Color(nsColor: tok(\.ink)) }
    static var ink2: Color  { Color(nsColor: tok(\.ink2)) }
    /// 小标签与说明文字用它。**对三种底色都 ≥ 4.5:1。**
    static var muted: Color { Color(nsColor: tok(\.muted)) }
    /// **只用于装饰**（分隔线上的符号、占位提示），不要拿它写需要读的文字——
    /// 旧版把小节标题设成 faint，对比度只有 2.3:1，就是「看不清」的来源。
    static var faint: Color { Color(nsColor: tok(\.faint)) }

    // 线
    static var rule: Color { Color(nsColor: tok(\.rule)) }
    /// 工字的横梁。比普通分隔线重得多——结构要看得见。
    static var beam: Color { Color(nsColor: tok(\.beam)) }

    // 语义：意图 vs 事实
    static var nsPlan: NSColor   { tok(\.plan) }
    static var nsActual: NSColor { tok(\.actual) }
    /// 计划＝意图，尚未发生。配虚线描边。
    static var plan: Color     { Color(nsColor: nsPlan) }
    static var planBG: Color   { Color(nsColor: tok(\.planBG)) }
    /// 实际＝事实，已经发生。配实心填充。
    static var actual: Color   { Color(nsColor: nsActual) }
    static var actualBG: Color { Color(nsColor: tok(\.actualBG)) }

    /// 标记色。用于「最重要」、越界提示、其他类应用。**不表示评价**。
    static var mark: Color   { Color(nsColor: tok(\.mark)) }
    static var markBG: Color { Color(nsColor: tok(\.markBG)) }
    /// 唯一的硬规则、当前时刻游标。用得极少才有分量。
    static var stop: Color   { Color(nsColor: tok(\.stop)) }

    // 兼容旧名
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
        static let label: CGFloat = 12       // 小节标签（原来 11pt + faint，太淡）
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
    var color: Color = Theme.muted
    var body: some View {
        Text(text)
            .font(Theme.ui(Theme.Size.label, .semibold))
            .tracking(0.6)
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
