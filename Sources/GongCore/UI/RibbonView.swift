import SwiftUI

/// 横排时间轴。**只读**，是 `DayTimelineProjection` 的纯消费者——
/// 所有 DST / 跨时区 / 跨零点的正确性都在投影里解决并有测试覆盖。
///
/// 视觉语义与两列一致：**计划＝虚线描边**（意图，还没发生），
/// **实际＝实心填充**（事实，已经发生）。这比再找一个色相更能一眼分清。
struct RibbonView: View {
    let projection: DayProjection

    private let trackHeight: CGFloat = 30
    private let labelWidth: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            axis
            Rectangle().fill(Theme.rule).frame(height: 1)
            track(segments: projection.planned, title: L(.colPlan),
                  color: Theme.plan, fill: Theme.planBG, solid: false)
            Rectangle().fill(Theme.rule).frame(height: 1)
            track(segments: projection.actual, title: L(.colActual),
                  color: Theme.actual, fill: Theme.actualBG, solid: true)
        }
        .background(Theme.inset)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall).strokeBorder(Theme.rule))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.radiusSmall))
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
                            .font(Theme.mono(Theme.Size.label))
                            .monospacedDigit()
                            .foregroundStyle(Theme.faint)
                            .position(x: labelWidth + x(tick.offset, w) + 9, y: 9)
                    }
                }
            }
        }
        .frame(height: 18)
    }

    private func track(segments: [TimelineSegment], title: String,
                       color: Color, fill: Color, solid: Bool) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Theme.ui(Theme.Size.label, .semibold))
                .foregroundStyle(color.opacity(0.9))
                .frame(width: labelWidth, alignment: .leading)
                .padding(.leading, 8)

            GeometryReader { geo in
                let w = max(1, geo.size.width)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        for seg in segments {
                            let x0 = x(seg.startOffset, size.width)
                            let x1 = max(x0 + 2, x(seg.endOffset, size.width))
                            let rect = CGRect(x: x0, y: 5, width: x1 - x0, height: size.height - 10)
                            let path = Path(roundedRect: rect, cornerRadius: 3)

                            if solid {
                                // 事实：实心
                                ctx.fill(path, with: .color(color))
                            } else {
                                // 意图：淡填充 + 虚线描边
                                ctx.fill(path, with: .color(fill))
                                ctx.stroke(path, with: .color(color),
                                           style: StrokeStyle(lineWidth: 1.2, dash: [3.5, 2.5]))
                            }
                            // 春令时不存在的墙钟时刻另有标记：加粗虚线描边
                            if seg.wallClockNonexistent {
                                ctx.stroke(path, with: .color(Theme.stop),
                                           style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                            }
                            if rect.width > 40, !seg.title.isEmpty {
                                var text = ctx.resolve(Text(seg.title)
                                    .font(Theme.ui(Theme.Size.label)))
                                text.shading = .color(solid ? Theme.surface : color)
                                ctx.draw(text, in: rect.insetBy(dx: 5, dy: 4))
                            }
                        }
                        if let now = projection.nowOffset {
                            let nx = x(now, size.width)
                            ctx.stroke(Path { p in
                                p.move(to: CGPoint(x: nx, y: 0))
                                p.addLine(to: CGPoint(x: nx, y: size.height))
                            }, with: .color(Theme.stop), lineWidth: 1.5)
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
