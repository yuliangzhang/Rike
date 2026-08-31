import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { scheduleSave() }
    }

    private let store = FileStore.shared
    private var saveTask: Task<Void, Never>?

    init() { self.settings = AppSettings() }

    func load() async {
        do {
            try await store.ensureDirectories()
            if let s = try await store.read(AppSettings.self, from: GongPaths.settingsFile) {
                settings = s
            }
        } catch {
            // 读取失败就用默认值，不阻塞启动
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.settings
            try? await self.store.write(snapshot, to: GongPaths.settingsFile)
        }
    }

    func saveNow() async {
        saveTask?.cancel()
        let snapshot = settings
        try? await store.write(snapshot, to: GongPaths.settingsFile)
    }
}
