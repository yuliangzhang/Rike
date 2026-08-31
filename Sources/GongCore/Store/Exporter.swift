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
/// ## 关于 TOCTOU（诚实说明，不宣称已消除）
///
/// **这个竞态无法被彻底消除。** POSIX 没有提供「校验内容与替换文件」的原子操作，
/// `flock` 只是劝告锁——只能约束同样加锁的进程（例如第二个 Gong 实例），
/// 约束不了任意外部编辑器或云同步进程。因此本实现不宣称消除竞态，
/// 而是把暴露压到最小并明确其边界：
///
/// 1. 目标不存在 → `O_CREAT|O_EXCL` 独占创建，**不存在竞态**。
/// 2. 目标存在但不是我们写的（无标记）或内容 hash 与上次导出不符
///    → **完全不碰原文件**，另存 `*.gong-conflict[-N].md`（同样 O_EXCL，
///    不覆盖旧冲突文件）。
/// 3. 只有当标记与 hash **都**证明「这就是我们上次写的、且没人动过」时才原子替换，
///    并且整段校验放在同目录 `flock` 内。内容先写进临时文件，
///    **锁内只做「复核 hash + rename」**，残余窗口是这两步之间的几十微秒
///    （而不是包含写盘 + fsync 的毫秒级窗口），且此时目标内容本就是我们的产物。
/// 4. 自动导出默认关闭（`AppSettings.autoExport`），把写入次数从「每次编辑」
///    降到「手动/收工」，把「有机会撞上」的次数也压到最低。
///
/// 如果你要的是**绝对**不覆盖，把 autoExport 关着并只用冲突文件流程即可 ——
/// 但那样每天会堆出很多文件，可用性代价很大。当前取舍是刻意的。
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

        // 2) 目标已存在 → 在目录锁内校验 + 写入，并在 rename 前再复核一次
        let expected = record.exportState
        do {
            let outcome: ExportOutcome? = try await store.withDirectoryLock(dir) { () -> ExportOutcome? in
                guard let (current, currentHash) = try FileStore.readSyncWithHash(target) else {
                    return nil                      // 期间被删了 → 退回创建流程
                }
                let isOurs = MarkdownRenderer.hasMarker(current)
                let matches = expected.map { $0.path == target.path && $0.contentHash == currentHash } ?? false
                guard isOurs && matches else { return .conflict(target) }   // 标记：需走冲突分支

                // 3) 内容没变就不写盘 —— 少写一次就少一次暴露
                if currentHash == newHash { return .unchanged(target) }

                // 4) 内容先写进临时文件（耗时部分），锁内最后只做「复核 + rename」，
                //    把窗口从「整个写盘过程」压缩到两个几乎瞬时的操作。
                let tmp = try FileStore.prepareTempSync(Data(text.utf8), for: target)
                // 任何提前退出（包括复核抛错）都必须清掉临时文件，否则导出目录会积垃圾。
                var committed = false
                defer { if !committed { FileStore.discardTempSync(tmp) } }

                guard let (_, recheck) = try FileStore.readSyncWithHash(target),
                      recheck == currentHash else { return .conflict(target) }

                try FileStore.commitTempSync(tmp, to: target)
                committed = true
                return .updated(target)
            }

            switch outcome {
            case .none:
                // 校验期间目标消失，重新独占创建
                if try await store.createExclusive(text, at: target) {
                    return (.created(target),
                            ExportState(path: target.path, contentHash: newHash, exportedAt: Date()))
                }
                return await writeConflict(text: text, dir: dir, dayKey: record.date, newHash: newHash)
            case .conflict:
                return await writeConflict(text: text, dir: dir, dayKey: record.date, newHash: newHash)
            case .unchanged(let u):
                return (.unchanged(u),
                        ExportState(path: u.path, contentHash: newHash, exportedAt: Date()))
            case .updated(let u):
                return (.updated(u),
                        ExportState(path: u.path, contentHash: newHash, exportedAt: Date()))
            default:
                return (.failed("导出状态异常"), nil)
            }
        } catch {
            return (.failed("导出失败：\(error.localizedDescription)"), nil)
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
