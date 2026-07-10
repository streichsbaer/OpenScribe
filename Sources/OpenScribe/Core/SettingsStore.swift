import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var persistenceError: String?

    private let fileURL: URL

    init(layout: DirectoryLayout) {
        self.fileURL = layout.settingsFile
        self.persistenceError = nil

        if let loaded = Self.load(from: fileURL) {
            self.settings = loaded
        } else {
            self.settings = .default
            do {
                try persist(settings)
            } catch {
                persistenceError = error.localizedDescription
            }
        }
    }

    @discardableResult
    func update(_ mutate: (inout AppSettings) -> Void) -> Bool {
        var draft = settings
        mutate(&draft)
        do {
            try persist(draft)
            settings = draft
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func resetToDefaults() -> Bool {
        update { $0 = .default }
    }

    private func persist(_ value: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}
