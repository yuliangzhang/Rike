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

    struct Notice: Identifiable, Equatable {
        enum Level { case info, warning }
        let id = UUID()
        var level: Level
        var text: String
    }

    private let store = FileStore.shared
    private var saveTask: Task<Void, Never>?
    private let debounceNanos: UInt64 = 1_500_000_000
    /// 最后一次**成功落盘**的 revision。用它判断 dirty，而不是无条件清标志：
    /// 保存 I/O 期间用户可能又改了，旧保存返回后不能把新改动标成 clean。
    private var savedRevision: Int = 0

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
                                text: "当前内容尚未全部保存，已取消切换日期。稍后再试或先解决保存失败的原因。")
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
            notice = Notice(level: .warning, text: "读取当日记录失败：\(error.localizedDescription)")
        }
        isDirty = false
        savedRevision = record.revision
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
            notice = Notice(level: .warning, text: "保存失败：\(error.localizedDescription)")
            return false
        }
        savedRevision = max(savedRevision, snapshot.revision)
        // 保存期间若又发生了编辑（revision 变大），仍然是 dirty，不能清标志
        isDirty = record.revision > savedRevision
        if isDirty { scheduleSave() }

        if settingsProvider().autoExport {
            await exportNow(silentWhenUnchanged: true)
        }
        return true
    }

    // MARK: - 导出

    func exportNow(silentWhenUnchanged: Bool = false) async {
        let settings = settingsProvider()
        let (outcome, newState) = await Exporter.shared.export(
            record: record, usage: usage, settings: settings)

        if let s = newState, s != record.exportState {
            // exportState 与 DayRecord 一起走同一条串行保存路径，避免两处各写一半
            record.exportState = s
            record.revision &+= 1
            let snapshot = record
            do {
                try await store.write(snapshot, to: GongPaths.dayFile(snapshot.date))
                savedRevision = max(savedRevision, snapshot.revision)
                isDirty = record.revision > savedRevision
            } catch {
                notice = Notice(level: .warning, text: "导出状态保存失败：\(error.localizedDescription)")
            }
        }

        switch outcome {
        case .created(let u):
            notice = Notice(level: .info, text: "已导出：\(u.lastPathComponent)")
        case .updated(let u):
            notice = Notice(level: .info, text: "已更新：\(u.lastPathComponent)")
        case .unchanged(let u):
            if !silentWhenUnchanged {
                notice = Notice(level: .info, text: "内容无变化，未写入：\(u.lastPathComponent)")
            }
        case .conflict(let u):
            notice = Notice(level: .warning,
                            text: "目标文件被外部修改或非本应用生成，已另存为 \(u.lastPathComponent)，原文件未改动")
        case .failed(let msg):
            notice = Notice(level: .warning, text: msg)
        }
    }

    func dismissNotice() { notice = nil }

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
            NSLog("Gong: 退出前保存失败 %@", String(describing: error))
        }
    }
}
