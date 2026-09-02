import Foundation

/// DayRecord → Markdown。**纯函数，可测。**
///
/// 语言跟随界面设置（用户明确要求）。代价已经告知过：切一次语言之后，
/// **新导出的文件**与旧文件的小节名不一致；已导出的文件不会被改动。
enum MarkdownRenderer {
    static let marker = "<!-- gong:generated v1 -->"

    static func render(record: DayRecord,
                       usage: UsageDay? = nil,
                       settings: AppSettings) -> String {
        render(record: record, usage: usage, settings: settings,
               lang: settings.language.resolved)
    }

    static func render(record: DayRecord,
                       usage: UsageDay?,
                       settings: AppSettings,
                       lang: Lang) -> String {
        func t(_ k: S) -> String { k.text(lang) }
        func f(_ k: S, _ a: CVarArg...) -> String {
            String(format: k.text(lang), arguments: a)
        }
        let notRecorded = t(.mdNotRecorded)
        let colon = t(.punctColon)

        var out: [String] = [marker]
        let compact = GongTime.compactKey(record.date)
        out.append("# \(compact) \(GongTime.weekdayLabel(dayKey: record.date, lang: lang))")
        out.append("")

        // MARK: 下限（独立一节，它不一定是工作事项）
        out.append("## \(t(.mdFloor))")
        if record.floor.text.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append("- \(notRecorded)")
        } else {
            let box = record.floor.status == .done ? "[x]" : "[ ]"
            out.append("- \(box) \(record.floor.text)")
        }
        out.append("")

        // MARK: TODO（顺序即优先级，导出时编号，第一条是最重要）
        out.append("## \(t(.mdTodo))")
        let todos = record.orderedTodos
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if todos.isEmpty {
            out.append("- \(notRecorded)")
        } else {
            for (i, todo) in todos.enumerated() {
                let box = todo.status == .done ? "[x]" : "[ ]"
                let mark = i == 0 ? t(.mdMitPrefix) : ""
                out.append("\(i + 1). \(box) \(mark)\(todo.text)")
            }
        }
        out.append("")

        // MARK: 计划
        out.append("## \(t(.mdPlan))")
        if record.planned.isEmpty {
            out.append("- \(notRecorded)")
        } else {
            for b in record.planned.sorted(by: { $0.startMinute < $1.startMinute }) {
                out.append("- \(b.rangeLabel(lang))\(colon)\(b.title)")
            }
        }
        out.append("")

        // MARK: 实际
        out.append("## \(t(.mdActual))")
        if record.actual.isEmpty {
            out.append("- \(notRecorded)")
        } else {
            for b in record.actual.sorted(by: { $0.start < $1.start }) {
                // 按块自身时区渲染，跨时区时带上时区标识 —— 否则导出的墙钟时间是错的
                let label = b.rangeLabel(recordTimeZoneIdentifier: record.key.timeZoneIdentifier,
                                         lang: lang)
                out.append("- \(label)\(colon)\(b.title)")
            }
        }
        out.append("")

        // MARK: 总结
        out.append("## \(t(.mdSummary))")
        out.append("### \(t(.mdTouched))")
        out.append(record.summary.touched.isEmpty ? notRecorded : record.summary.touched)
        out.append("")
        out.append("### \(t(.mdWins))")
        let wins = record.summary.wins
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if wins.isEmpty {
            out.append(notRecorded)
        } else {
            for (i, w) in wins.enumerated() { out.append("\(i + 1). \(w.text)") }
        }
        out.append("")

        out.append("### \(t(.mdTomorrow))")
        out.append(record.summary.tomorrow.isEmpty ? notRecorded : record.summary.tomorrow)
        out.append("")

        out.append("### \(t(.mdClarity))")
        if record.summary.clarity.isEmpty {
            out.append(notRecorded)
        } else {
            let empty = t(.emptyBrackets)
            func blank(_ s: String) -> String {
                s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? empty : s
            }
            for c in record.summary.clarity {
                out.append("- \(t(.mdStuckOn))\(colon)\(blank(c.stuckOn))")
                out.append("  - \(t(.mdEscapingFrom))\(colon)\(blank(c.escapingFrom))")
                out.append("  - \(t(.mdWorstCase))\(colon)\(blank(c.worstCase))")
                out.append("  - → \(t(.mdFirstStep))\(colon)\(blank(c.firstStep))")
            }
        }
        if !record.summary.freeText.isEmpty {
            out.append("")
            out.append("### \(t(.mdNote))")
            out.append(record.summary.freeText)
        }
        out.append("")

        // MARK: 状态（中性措辞，无 ✓ 无评价）
        out.append("### \(t(.mdStatus))")
        out.append("- \(t(.mdFloorLine))\(colon)\(record.floorStatus.label(lang))")
        out.append("- \(t(.mdMitLine))\(colon)\(record.mitStatus.label(lang))")
        out.append("")

        // MARK: 注意力（默认不导出明细）
        if settings.exportInterruptionDetail && !record.breaker.interruptions.isEmpty {
            out.append("## \(t(.mdAttention))")
            for i in record.breaker.interruptions {
                var line = "- " + f(.mdInterruption, i.minutes, i.trigger.code)
                if !i.escapingFrom.isEmpty { line += f(.mdEscaping, i.escapingFrom) }
                out.append(line)
            }
            out.append("")
        }

        // MARK: 使用时长（默认不导出明细）
        if settings.exportUsageDetail, let u = usage, !u.intervals.isEmpty {
            out.append("## \(t(.mdUsageTop5))")
            let top = u.totals().prefix(5)
                .map { "\($0.name) \(GongTime.formatDuration($0.seconds))" }
                .joined(separator: t(.punctPipe))
            out.append("- \(top)")
            out.append("")
        }

        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    static func hasMarker(_ text: String) -> Bool {
        text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?.trimmingCharacters(in: .whitespaces) == marker
    }
}
