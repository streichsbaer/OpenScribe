import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let fileURL: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.fileURL = layout.settingsFile
        self.fileManager = fileManager

        if let loaded = Self.load(from: fileURL) {
            self.settings = loaded
        } else {
            self.settings = .default
            try? persist()
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        var draft = settings
        mutate(&draft)
        settings = draft
        try? persist()
    }

    func resetToDefaults() {
        settings = .default
        try? persist()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try atomicWrite(data, to: fileURL)
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let tmpURL = url.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")
        try data.write(to: tmpURL, options: [.atomic])

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.moveItem(at: tmpURL, to: url)
    }
}
