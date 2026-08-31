import Foundation

enum ExportOutcome: Sendable, Equatable {
    case created(URL)          // 目标不存在，独占创建
    case updated(URL)          // 目标是我们自己写的且未被改动，安全替换
    case unchanged(URL)        // 内容无变化，未写盘
    case conflict(URL)         // 目标被外部修改/非本应用生成 → 另存冲突文件，原文件未动
    case failed(String)

    var url: URL? {
        switch self {
        case .created(let u), .updated(let u), .unchanged(let u), .conflict(let u): return u
        case .failed: return nil
        }
    }
}

/// Markdown 导出。**原则：宁可不导出，绝不覆盖。**
///
/// ## 关于 TOCTOU（诚实说明）
///
/// 无法对「不合作的外部进程」做到真正的原子 check-and-write：任何进程都可能在我们
/// 读取校验之后、rename 之前写入目标文件。因此本实现不宣称消除竞态，而是把暴露
/// 压到最小并明确其边界：
///
/// 1. 目标不存在 → `O_CREAT|O_EXCL` 独占创建，**不存在竞态**。
/// 2. 目标存在但不是我们写的（无标记）或内容 hash 与上次导出不符
///    → **完全不碰原文件**，另存 `*.gong-conflict[-N].md`（同样 O_EXCL，
///    不覆盖旧冲突文件）。
/// 3. 只有当标记与 hash **都**证明「这就是我们上次写的、且没人动过」时才原子替换。
///    残余窗口 = 读取校验到 rename 之间的几百微秒；且此时文件内容本就是我们的产物。
/// 4. 自动导出默认关闭（`AppSettings.autoExport`），把写入次数从「每次编辑」
///    降到「手动/收工」，进一步压缩暴露次数。
actor Exporter {
    static let shared = Exporter()

    private let store = FileStore.shared

    func export(record: DayRecord,
                usage: UsageDay?,
                settings: AppSettings) async -> (outcome: ExportOutcome, state: ExportState?) {

        let text = MarkdownRenderer.render(record: record, usage: usage, settings: settings)
        let newHash = FileStore.sha256(text)
        let dir = settings.exportDirectory
        let target = GongPaths.exportFile(in: dir, dayKey: record.date)

        do {
            try await store.ensureDirectory(dir)
        } catch {
            return (.failed("无法创建导出目录：\(dir.path)——\(error.localizedDescription)"), nil)
        }

        // 1) 目标不存在 → 独占创建
        do {
            if try await store.createExclusive(text, at: target) {
                return (.created(target),
                        ExportState(path: target.path, contentHash: newHash, exportedAt: Date()))
            }
        } catch {
            return (.failed("创建失败：\(error.localizedDescription)"), nil)
        }

        // 2) 目标已存在 → 校验它是否确实是我们上次写的且未被改动
        let current: String
        do {
            current = try await store.readString(target) ?? ""
        } catch {
            return (.failed("无法读取目标文件：\(error.localizedDescription)"), nil)
        }

        let currentHash = FileStore.sha256(current)
        let isOurs = MarkdownRenderer.hasMarker(current)
        let matchesLastExport = record.exportState.map {
            $0.path == target.path && $0.contentHash == currentHash
        } ?? false

        guard isOurs && matchesLastExport else {
            return await writeConflict(text: text, dir: dir, dayKey: record.date, newHash: newHash)
        }

        // 3) 内容没变就不写盘 —— 少写一次就少一次暴露
        if currentHash == newHash {
            return (.unchanged(target),
                    ExportState(path: target.path, contentHash: newHash, exportedAt: Date()))
        }

        do {
            try await store.writeAtomic(Data(text.utf8), to: target)
            return (.updated(target),
                    ExportState(path: target.path, contentHash: newHash, exportedAt: Date()))
        } catch {
            return (.failed("写入失败：\(error.localizedDescription)"), nil)
        }
    }

    /// 冲突文件也用 O_EXCL，并依次加后缀，绝不覆盖旧的冲突文件。
    private func writeConflict(text: String, dir: URL, dayKey: String, newHash: String)
        async -> (ExportOutcome, ExportState?) {
        let base = GongPaths.conflictFile(in: dir, dayKey: dayKey)
        for n in 0..<100 {
            let url: URL = n == 0
                ? base
                : dir.appendingPathComponent("\(GongTime.compactKey(dayKey)).gong-conflict-\(n).md")
            do {
                if try await store.createExclusive(text, at: url) {
                    // 注意：不更新 exportState —— 我们并没有写成目标文件。
                    return (.conflict(url), nil)
                }
            } catch {
                return (.failed("冲突文件写入失败：\(error.localizedDescription)"), nil)
            }
        }
        return (.failed("冲突文件过多（已有 100 个），请先清理导出目录"), nil)
    }
}
