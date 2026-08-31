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

    var settingsProvider: () -> AppSettings = { AppSettings() }

    init(dayKey: DayKey = DayKey(Date())) {
        self.record = DayRecord(key: dayKey)
    }

    // MARK: - 载入

    func load(dayKey: DayKey) async {
        await flushPendingSave()
        do {
            try await store.ensureDirectories()
            if var loaded = try await store.read(DayRecord.self, from: GongPaths.dayFile(dayKey.date)) {
                loaded.normalize()
                record = loaded
            } else {
                record = DayRecord(key: dayKey)
            }
        } catch {
            record = DayRecord(key: dayKey)
            notice = Notice(level: .warning, text: "读取当日记录失败：\(error.localizedDescription)")
        }
        isDirty = false
        await refreshUsage()
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

    /// 强制立即落盘（退出 / 失焦 / 切日期时调用）。
    func saveNow() async {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = record          // 在 MainActor 上取，必然是最新的
        do {
            try await store.write(snapshot, to: GongPaths.dayFile(snapshot.date))
            isDirty = false
        } catch {
            notice = Notice(level: .warning, text: "保存失败：\(error.localizedDescription)")
            return
        }
        if settingsProvider().autoExport {
            await exportNow(silentWhenUnchanged: true)
        }
    }

    private func flushPendingSave() async {
        if isDirty { await saveNow() }
        saveTask?.cancel()
        saveTask = nil
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
            try? await store.write(record, to: GongPaths.dayFile(record.date))
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
}
