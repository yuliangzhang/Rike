import Foundation
import SwiftUI

/// 一天数据的**唯一权威持有者**。所有编辑都经这里，杜绝 lost update。
///
/// 防「过期快照覆盖新数据」的做法：防抖任务**不捕获快照**，
/// 而是在 MainActor 上执行时才读取 `self.record`（永远是最新的），
/// 并在调度新任务前取消旧任务。`revision` 作为 FileStore 侧的防御性校验。
@MainActor
final class DayStore: ObservableObject {

    @Published private(set) var record: DayRecord
    @Published private(set) var usage: UsageDay?
    @Published private(set) var notice: Notice?
    @Published private(set) var isDirty = false
    /// 手动导出的结果。见 `ExportReport` 的注释。
    @Published private(set) var exportReport: ExportReport?

    struct Notice: Identifiable, Equatable {
        enum Level { case info, warning }
        let id = UUID()
        var level: Level
        var text: String
    }

    /// 手动点「导出」之后要当面说清楚的那件事。
    ///
    /// 为什么不复用顶部那条 `Notice`：导出是**用户主动按下去的一次动作**，
    /// 他在等一个回执。横幅出现在视线之外、几秒后自己消失，等于没回。
    /// 自动导出、监控提醒这类**系统自己发起**的消息仍然走横幅——
    /// 那些没人在等，弹窗只会打断正在写字的人。
    ///
    /// 带上完整目录，是因为「导出到哪儿了」本身就是人点完之后最想知道的事。
    struct ExportReport: Identifiable, Equatable {
        enum Kind { case ok, warning }
        let id = UUID()
        var kind: Kind
        var title: String
        var message: String
        /// 落盘的文件。有值时弹窗多给一个「在访达中显示」。
        var file: URL?
    }

    private let store = FileStore.shared
    private var saveTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 1_500_000_000
    /// 最后一次**成功落盘**的 revision，以及它属于哪一天。
    /// 必须绑定日期：`revision` 只在同一条记录的生命周期内单调，
    /// 旧日期的异步保存若在切日后才返回，跨记录比较会把新日期的 dirty 误清。
    private var savedRevision: Int = 0
    private var savedDate: String = ""

    var settingsProvider: () -> AppSettings = { AppSettings() }

    init(dayKey: DayKey = DayKey(Date())) {
        self.record = DayRecord(key: dayKey)
    }

    // MARK: - 载入

    /// 切换日期。**若当前未保存的内容落盘失败，中止切换**——
    /// 否则内存里的编辑会被新日期的数据直接替换掉，用户看不到任何东西就没了。
    @discardableResult
    func load(dayKey: DayKey) async -> Bool {
        if isDirty {
            let ok = await saveNow()
            // 不只看返回值：保存的 await 期间用户可能又改了（saveNow 会把 isDirty 重新置真）。
            // 只要还有未落盘的内容，就不能替换 record。
            guard ok, !isDirty else {
                notice = Notice(level: .warning,
                                text: L(.noticeSwitchBlocked))
                return false
            }
        }
        saveTask?.cancel(); saveTask = nil

        do {
            try await store.ensureDirectories()
            if var loaded = try await store.read(DayRecord.self, from: GongPaths.dayFile(dayKey.date)) {
                loaded.normalize()
                // 采用**存盘记录自带的时区**：那一天是在哪个时区记录的，
                // 回看时就该用那个时区投影。旅行后不应该用当前时区去重算历史。
                record = loaded
            } else {
                record = DayRecord(key: dayKey)
            }
        } catch {
            record = DayRecord(key: dayKey)
            notice = Notice(level: .warning, text: L(.noticeReadFailed, error.localizedDescription))
        }
        isDirty = false
        savedRevision = record.revision
        savedDate = record.key.date
        // 载入的记录若带着别的时区，说明这一天是在别处记的 —— 明确告诉用户，
        // 而不是悄悄用当前时区重算它。
        if record.key.timeZoneIdentifier != dayKey.timeZoneIdentifier {
            notice = Notice(level: .info,
                            text: L(.noticeRecordTZ, record.key.timeZoneIdentifier))
        }
        await refreshUsage()
        return true
    }

    func reloadUsage() { Task { await refreshUsage() } }

    private func refreshUsage() async {
        let key = record.key
        var all: [UsageEvent] = []
        for dk in UsageReducer.requiredDayKeys(for: key) {
            if let evs = try? await store.readEvents(from: GongPaths.eventsFile(dk)) {
                all.append(contentsOf: evs)
            }
        }
        guard !all.isEmpty else { usage = nil; return }
        let isToday = key.date == GongTime.dayKey(Date())
        usage = UsageReducer.reduce(events: all, for: key, liveNow: isToday ? Date() : nil)
    }

    // MARK: - 编辑

    /// 唯一的修改入口。自动 normalize、递增 revision、调度防抖保存。
    func mutate(_ block: (inout DayRecord) -> Void) {
        var copy = record
        block(&copy)
        copy.normalize()
        copy.revision = record.revision &+ 1
        copy.updatedAt = Date()
        record = copy
        isDirty = true
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanos ?? 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// 强制立即落盘。返回是否成功——调用方（如切日期）必须据此决定要不要继续。
    @discardableResult
    func saveNow() async -> Bool {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = record                 // 在 MainActor 上取，必然是最新的
        do {
            try await store.write(snapshot, to: GongPaths.dayFile(snapshot.date))
        } catch {
            notice = Notice(level: .warning, text: L(.noticeSaveFailed, error.localizedDescription))
            return false
        }
        // 只有当「当前仍是同一条记录」时才更新已保存水位。
        // 否则这是一次跨日期的陈旧保存，不能用它影响当前记录的 dirty 判定。
        if record.key.date == snapshot.key.date {
            savedDate = snapshot.key.date
            savedRevision = max(savedRevision, snapshot.revision)
            // 保存期间若又发生了编辑（revision 变大），仍然是 dirty，不能清标志
            isDirty = record.revision > savedRevision
            if isDirty { scheduleSave() }
        }

        if settingsProvider().autoExport {
            await exportNow(silentWhenUnchanged: true)
        }
        return true
    }

    // MARK: - 导出

    /// - Parameter announcing: 人主动点了导出按钮，结果要用弹窗当面回执；
    ///   自动导出走 false，只留一条横幅。
    func exportNow(silentWhenUnchanged: Bool = false, announcing: Bool = false) async {
        let settings = settingsProvider()
        // 导出期间用户可能继续编辑或切日期 —— 记下身份，返回后核对。
        let exportedDate = record.key.date
        let exportedRevision = record.revision

        let (outcome, newState) = await Exporter.shared.export(
            record: record, usage: usage, settings: settings)

        // 只有仍是同一条记录、且期间没有新编辑时，才把导出状态写回。
        // 否则这个 contentHash 描述的是旧内容，挂上去会让下次导出误判为「未被改动」。
        let stillSameRecord = record.key.date == exportedDate && record.revision == exportedRevision
        if let s = newState, stillSameRecord, s != record.exportState {
            record.exportState = s
            record.revision &+= 1
            isDirty = true                        // 先标脏，写成功后再由水位决定
            let snapshot = record
            do {
                try await store.write(snapshot, to: GongPaths.dayFile(snapshot.date))
                if record.key.date == snapshot.key.date {
                    savedDate = snapshot.key.date
                    savedRevision = max(savedRevision, snapshot.revision)
                    isDirty = record.revision > savedRevision
                }
            } catch {
                notice = Notice(level: .warning, text: L(.noticeExportStateFailed, error.localizedDescription))
                scheduleSave()
            }
        }

        // 先把结论算出来，再决定是当面回执还是挂一条横幅 —— 同一套文案，两种送达方式。
        let result: (level: Notice.Level, title: S, text: String, file: URL?)
        switch outcome {
        case .created(let u):
            result = (.info, .exportTitleDone, L(.noticeExported, u.lastPathComponent), u)
        case .updated(let u):
            result = (.info, .exportTitleDone, L(.noticeUpdated, u.lastPathComponent), u)
        case .updatedUnsynced(let u, let detail):
            result = (.warning, .exportTitleAttention,
                      L(.noticeUnsynced, u.lastPathComponent, detail), u)
        case .unchanged(let u):
            // 自动导出时「没变化」是噪音；人手动点的时候它是回答，必须说。
            guard !silentWhenUnchanged || announcing else { return }
            result = (.info, .exportTitleNoChange, L(.noticeNoChange, u.lastPathComponent), u)
        case .conflict(let u):
            result = (.warning, .exportTitleAttention, L(.noticeConflict, u.lastPathComponent), u)
        case .failed(let msg):
            result = (.warning, .exportTitleFailed, msg, nil)
        }

        if announcing {
            exportReport = ExportReport(kind: result.level == .warning ? .warning : .ok,
                                        title: L(result.title),
                                        message: result.file.map {
                                            "\(result.text)\n\n\(L(.exportLocation, $0.deletingLastPathComponent().path))"
                                        } ?? result.text,
                                        file: result.file)
        } else {
            notice = Notice(level: result.level, text: result.text)
        }
    }

    func dismissNotice() { notice = nil }

    func dismissExportReport() { exportReport = nil }

    func note(_ level: Notice.Level, _ text: String) {
        notice = Notice(level: level, text: text)
    }

    /// 退出时的同步落盘。**不能用 await** —— `applicationWillTerminate` 运行在主线程，
    /// 若在此阻塞等待 @MainActor Task，Task 永远拿不到主线程，必然死锁。
    func saveSynchronouslyForTermination() {
        saveTask?.cancel()
        saveTask = nil
        guard isDirty else { return }
        do {
            let data = try FileStore.encodeSync(record)
            try FileStore.writeAtomicSync(data, to: GongPaths.dayFile(record.date))
            savedRevision = record.revision
            isDirty = false
        } catch {
            NSLog("Rike: save on quit failed %@", String(describing: error))
        }
    }
}
