import SwiftUI

/// 横排时间轴。**只读**，是 `DayTimelineProjection` 的纯消费者——
/// 所有 DST / 跨时区 / 跨零点的正确性都在投影里解决并有测试覆盖。
struct RibbonView: View {
    let projection: DayProjection

    private let trackHeight: CGFloat = 26
    private let labelWidth: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            axis
            Divider().overlay(Theme.hairline)
            track(segments: projection.planned, title: "计划",
                  color: Theme.plan, fill: Theme.planBG)
            Divider().overlay(Theme.hairline)
            track(segments: projection.actual, title: "实际",
                  color: Theme.actual, fill: Theme.actualBG)
        }
        .background(Color.primary.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var axis: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - labelWidth)
            ZStack(alignment: .topLeading) {
                ForEach(Array(projection.ticks.enumerated()), id: \.offset) { idx, tick in
                    // 每 2 个刻度标一次，避免拥挤；秋令时重复的 01 会出现两次，这是事实。
                    // 注意：不能用 `Int(tick.label) ?? 0 % 2 == 0` —— `%` 优先级高于 `??`，
                    // 那会被解析成 `(Int(label) ?? 0) == 0`，结果只有 00 点会显示。
                    if idx % 2 == 0 {
                        Text(tick.label)
                            .font(Theme.monoSized(9))
                            .foregroundStyle(.tertiary)
                            .position(x: labelWidth + x(tick.offset, w) + 8, y: 8)
                    }
                }
            }
        }
        .frame(height: 16)
    }

    private func track(segments: [TimelineSegment], title: String,
                       color: Color, fill: Color) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Theme.monoSized(9))
                .foregroundStyle(.tertiary)
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 6)

            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        for seg in segments {
                            let x0 = x(seg.startOffset, size.width)
                            let x1 = max(x0 + 2, x(seg.endOffset, size.width))
                            let rect = CGRect(x: x0, y: 4, width: x1 - x0, height: size.height - 8)
                            let path = Path(roundedRect: rect, cornerRadius: 2.5)
                            ctx.fill(path, with: .color(fill))
                            ctx.stroke(path, with: .color(color),
                                       style: StrokeStyle(lineWidth: 1,
                                                          dash: seg.wallClockNonexistent ? [3, 2] : []))
                            if rect.width > 34, !seg.title.isEmpty {
                                var text = ctx.resolve(Text(seg.title)
                                    .font(.system(size: 9))
                                    .foregroundStyle(color))
                                text.shading = .color(color)
                                ctx.draw(text, in: rect.insetBy(dx: 4, dy: 4))
                            }
                        }
                        if let now = projection.nowOffset {
                            let nx = x(now, size.width)
                            ctx.stroke(Path { p in
                                p.move(to: CGPoint(x: nx, y: 0))
                                p.addLine(to: CGPoint(x: nx, y: size.height))
                            }, with: .color(Theme.stop), lineWidth: 1)
                        }
                    }
                    .frame(width: w)
                }
            }
        }
        .frame(height: trackHeight)
    }

    private func x(_ offset: Double, _ width: CGFloat) -> CGFloat {
        guard projection.axisLength > 0 else { return 0 }
        return CGFloat(offset / projection.axisLength) * width
    }
}
