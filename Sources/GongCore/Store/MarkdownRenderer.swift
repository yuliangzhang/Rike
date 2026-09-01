import Foundation

/// DayRecord → Markdown。**纯函数，可测。**
enum MarkdownRenderer {
    static let marker = "<!-- gong:generated v1 -->"

    static func render(record: DayRecord,
                       usage: UsageDay? = nil,
                       settings: AppSettings) -> String {
        var out: [String] = [marker]
        let compact = GongTime.compactKey(record.date)
        out.append("# \(compact) \(GongTime.weekdayLabel(dayKey: record.date))")
        out.append("")

        // MARK: TODO
        out.append("## 今日 TODO")
        if record.todos.isEmpty {
            out.append("- （未记录）")
        } else {
            for t in record.widgetTodos where !t.text.trimmingCharacters(in: .whitespaces).isEmpty {
                let box = t.status == .done ? "[x]" : "[ ]"
                let prefix: String
                switch t.kind {
                case .floor: prefix = "⌂ 下限："
                case .mit:   prefix = "★ 最重要："
                case .normal: prefix = ""
                }
                out.append("- \(box) \(prefix)\(t.text)")
            }
        }
        out.append("")

        // MARK: 计划
        out.append("## 计划")
        if record.planned.isEmpty {
            out.append("- （未记录）")
        } else {
            for b in record.planned.sorted(by: { $0.startMinute < $1.startMinute }) {
                out.append("- \(b.rangeLabel)：\(b.title)")
            }
        }
        out.append("")

        // MARK: 实际
        out.append("## 实际")
        if record.actual.isEmpty {
            out.append("- （未记录）")
        } else {
            for b in record.actual.sorted(by: { $0.start < $1.start }) {
                // 按块自身时区渲染，跨时区时带上时区标识 —— 否则导出的墙钟时间是错的
                let label = b.rangeLabel(recordTimeZoneIdentifier: record.key.timeZoneIdentifier)
                out.append("- \(label)：\(b.title)")
            }
        }
        out.append("")

        // MARK: 总结
        out.append("## 今日总结")
        out.append("### 触动")
        out.append(record.summary.touched.isEmpty ? "（未记录）" : record.summary.touched)
        out.append("")
        out.append("### 模糊清单")
        if record.summary.clarity.isEmpty {
            out.append("（未记录）")
        } else {
            for c in record.summary.clarity {
                out.append("- 卡住的具体位置：\(blank(c.stuckOn))")
                out.append("  - 真正想逃开的是：\(blank(c.escapingFrom))")
                out.append("  - 最坏情况：\(blank(c.worstCase))")
                out.append("  - → 明天 30 分钟内的第一步：\(blank(c.firstStep))")
            }
        }
        if !record.summary.freeText.isEmpty {
            out.append("")
            out.append("### 备注")
            out.append(record.summary.freeText)
        }
        out.append("")

        // MARK: 状态（中性措辞，无 ✓ 无评价）
        out.append("### 状态")
        out.append("- 下限：\(record.floorStatus.label)")
        out.append("- 最重要：\(record.mitStatus.label)")
        out.append("")

        // MARK: 注意力（默认不导出明细）
        if settings.exportInterruptionDetail && !record.breaker.interruptions.isEmpty {
            out.append("## 注意力")
            for i in record.breaker.interruptions {
                var line = "- 中断 \(i.minutes) 分钟 · 触发 \(i.trigger.code)"
                if !i.escapingFrom.isEmpty { line += " · 真正想逃开的：\(i.escapingFrom)" }
                out.append(line)
            }
            out.append("")
        }

        // MARK: 使用时长（默认不导出明细）
        if settings.exportUsageDetail, let u = usage, !u.intervals.isEmpty {
            out.append("## 使用时长（前 5）")
            let top = u.totals().prefix(5)
                .map { "\($0.name) \(GongTime.formatDuration($0.seconds))" }
                .joined(separator: " ｜ ")
            out.append("- \(top)")
            out.append("")
        }

        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func blank(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "（空）" : s
    }

    static func hasMarker(_ text: String) -> Bool {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?.trimmingCharacters(in: .whitespaces) == marker
    }
}
