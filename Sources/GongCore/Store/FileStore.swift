import Foundation
import CryptoKit

enum FileStoreError: LocalizedError {
    case writeFailed(String)
    case renameFailed(String, errno: Int32)
    case openFailed(String, errno: Int32)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let p):            return "写入失败：\(p)"
        case .renameFailed(let p, let e):     return "原子替换失败：\(p)（errno \(e)）"
        case .openFailed(let p, let e):       return "打开失败：\(p)（errno \(e)）"
        }
    }
}

/// 所有磁盘读写的唯一入口，`actor` 串行化，杜绝并发写竞态（DESIGN.md §7.2）。
actor FileStore {
    static let shared = FileStore()

    private let fm = FileManager.default

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// NDJSON 每行一个事件，紧凑无换行。
    private let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: - 目录

    func ensureDirectories() throws {
        for dir in GongPaths.allDirectories {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func ensureDirectory(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    // MARK: - 原子写（DESIGN.md §4.4）

    /// 同目录临时文件 → fsync → rename(2) 原子替换 → fsync 目录。
    /// 临时文件必须与目标同目录，否则跨 volume 的 rename 不保证原子。
    func writeAtomic(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")

        // 1. 写入临时文件并 fsync
        guard fm.createFile(atPath: tmp.path, contents: nil) else {
            throw FileStoreError.writeFailed(tmp.path)
        }
        do {
            let fh = try FileHandle(forWritingTo: tmp)
            defer { try? fh.close() }
            try fh.write(contentsOf: data)
            try fh.synchronize()          // fsync：内容真正落盘
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }

        // 2. 原子替换。rename(2) 无论目标是否存在都可用，且同 volume 下原子。
        if rename(tmp.path, url.path) != 0 {
            let e = errno
            try? fm.removeItem(at: tmp)
            throw FileStoreError.renameFailed(url.path, errno: e)
        }

        // 3. 同步目录项，防止断电后「已替换但目录项未落盘」
        syncDirectory(dir)
    }

    private func syncDirectory(_ dir: URL) {
        let fd = open(dir.path, O_RDONLY)
        guard fd >= 0 else { return }
        _ = fsync(fd)
        close(fd)
    }

    // MARK: - JSON

    func write<T: Encodable>(_ value: T, to url: URL) throws {
        try writeAtomic(try encoder.encode(value), to: url)
    }

    func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        return try decoder.decode(type, from: data)
    }

    func readData(_ url: URL) throws -> Data? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func readString(_ url: URL) throws -> String? {
        guard let d = try readData(url) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    // MARK: - append-only 事件日志（DESIGN.md §5.1）

    /// O_APPEND 追加一行。append-only，永不改写既有内容。
    func appendEvent(_ event: UsageEvent, to url: URL) throws {
        let data = try lineEncoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        try appendLine(line, to: url)
    }

    func appendLine(_ line: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw FileStoreError.openFailed(url.path, errno: errno) }
        defer { close(fd) }

        try line.withCString { cstr in
            let len = strlen(cstr)
            var written = 0
            while written < len {
                let n = Darwin.write(fd, cstr + written, len - written)
                if n <= 0 { throw FileStoreError.writeFailed(url.path) }
                written += n
            }
        }
        _ = fsync(fd)
    }

    /// 读取 NDJSON 事件日志。跳过损坏行而不是整体失败——崩溃时最后一行可能是半行。
    func readEvents(from url: URL) throws -> [UsageEvent] {
        guard let text = try readString(url) else { return [] }
        var events: [UsageEvent] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = raw.data(using: .utf8) else { continue }
            if let ev = try? decoder.decode(UsageEvent.self, from: data) { events.append(ev) }
        }
        return events.sorted { $0.t < $1.t }
    }

    // MARK: - 导出支持

    /// 内容 hash，用于 Markdown 导出的防覆盖校验（DESIGN.md §4.5）。
    nonisolated static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// `O_CREAT|O_EXCL` 独占创建。文件已存在则返回 false，绝不覆盖。
    func createExclusive(_ text: String, at url: URL) throws -> Bool {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        if fd < 0 {
            if errno == EEXIST { return false }
            throw FileStoreError.openFailed(url.path, errno: errno)
        }
        defer { close(fd) }

        let data = Array(text.utf8)
        var written = 0
        try data.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            while written < data.count {
                let n = Darwin.write(fd, base + written, data.count - written)
                if n <= 0 { throw FileStoreError.writeFailed(url.path) }
                written += n
            }
        }
        _ = fsync(fd)
        syncDirectory(dir)
        return true
    }

    func removeItem(at url: URL) throws {
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }

    func listDayKeys() -> [String] {
        guard let files = try? fm.contentsOfDirectory(atPath: GongPaths.daysDir.path) else { return [] }
        return files.filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(5)) }
            .sorted()
    }
}
