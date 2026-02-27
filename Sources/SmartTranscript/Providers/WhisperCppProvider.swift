import Foundation

final class WhisperCppProvider: TranscriptionProvider {
    let id = "whispercpp"
    let displayName = "Local whisper.cpp"

    private let binaryURL: URL
    private let modelManager: ModelDownloadManager

    init(binaryURL: URL, modelManager: ModelDownloadManager) {
        self.binaryURL = binaryURL
        self.modelManager = modelManager
    }

    func transcribe(audioFileURL: URL, language: String?, model: String) async throws -> TranscriptResult {
        let start = Date()

        if !modelManager.isInstalled(modelID: model) {
            throw ProviderError.missingModel(model)
        }
        let modelURL = modelManager.localPath(for: model)

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-\(UUID().uuidString)")

        var args = [
            "-m", modelURL.path,
            "-f", audioFileURL.path,
            "-otxt",
            "-of", outputBase.path,
            "-nt"
        ]

        if let language, !language.isEmpty, language.lowercased() != "auto" {
            args.append(contentsOf: ["-l", language])
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        let outputFile = outputBase.appendingPathExtension("txt")
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProviderError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let text = try? String(contentsOf: outputFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ProviderError.invalidResponse
        }

        try? FileManager.default.removeItem(at: outputFile)

        let latency = Int(Date().timeIntervalSince(start) * 1_000)
        return TranscriptResult(text: text, providerId: id, model: model, latencyMs: latency)
    }
}
