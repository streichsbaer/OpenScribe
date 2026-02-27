import Foundation

struct DirectoryLayout {
    let appSupport: URL
    let recordings: URL
    let rules: URL
    let models: URL
    let config: URL

    let rulesFile: URL
    let rulesHistory: URL
    let settingsFile: URL

    static func resolve(fileManager: FileManager = .default) throws -> DirectoryLayout {
        let appSupportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appSupport = appSupportRoot.appendingPathComponent(AppDirectories.appSupportName, isDirectory: true)
        let recordings = appSupport.appendingPathComponent("Recordings", isDirectory: true)
        let rules = appSupport.appendingPathComponent("Rules", isDirectory: true)
        let models = appSupport.appendingPathComponent("Models/whisper", isDirectory: true)
        let config = appSupport.appendingPathComponent("Config", isDirectory: true)

        let layout = DirectoryLayout(
            appSupport: appSupport,
            recordings: recordings,
            rules: rules,
            models: models,
            config: config,
            rulesFile: rules.appendingPathComponent("rules.md"),
            rulesHistory: rules.appendingPathComponent("rules.history.jsonl"),
            settingsFile: config.appendingPathComponent("settings.json")
        )

        try layout.ensureExists(fileManager: fileManager)
        return layout
    }

    func ensureExists(fileManager: FileManager = .default) throws {
        try [appSupport, recordings, rules, models, config].forEach {
            try fileManager.createDirectory(at: $0, withIntermediateDirectories: true)
        }
    }
}
