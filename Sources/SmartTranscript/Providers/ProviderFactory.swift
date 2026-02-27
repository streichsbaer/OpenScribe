import Foundation

@MainActor
final class ProviderFactory {
    private let keychain: KeychainStore
    private let modelManager: ModelDownloadManager

    init(keychain: KeychainStore, modelManager: ModelDownloadManager) {
        self.keychain = keychain
        self.modelManager = modelManager
    }

    func transcriptionProvider(id: String) throws -> any TranscriptionProvider {
        switch id {
        case "whispercpp":
            let binary = try resolveWhisperBinary()
            return WhisperCppProvider(binaryURL: binary, modelManager: modelManager)
        case "openai_whisper":
            guard let key = keychain.load(.openAI), !key.isEmpty else {
                throw ProviderError.missingAPIKey("OpenAI")
            }
            return OpenAIWhisperProvider(apiKey: key)
        case "groq_whisper":
            guard let key = keychain.load(.groq), !key.isEmpty else {
                throw ProviderError.missingAPIKey("Groq")
            }
            return GroqWhisperProvider(apiKey: key)
        default:
            throw ProviderError.unsupported("Unknown transcription provider: \(id)")
        }
    }

    func polishProvider(id: String) throws -> any PolishProvider {
        switch id {
        case "openai_polish":
            guard let key = keychain.load(.openAI), !key.isEmpty else {
                throw ProviderError.missingAPIKey("OpenAI")
            }
            return OpenAIPolishProvider(apiKey: key)
        case "groq_polish":
            guard let key = keychain.load(.groq), !key.isEmpty else {
                throw ProviderError.missingAPIKey("Groq")
            }
            return GroqPolishProvider(apiKey: key)
        default:
            throw ProviderError.unsupported("Unknown polish provider: \(id)")
        }
    }

    private func resolveWhisperBinary() throws -> URL {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cpp",
            Bundle.main.resourceURL?.appendingPathComponent("bin/whisper-cli").path
        ].compactMap { $0 }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw ProviderError.unsupported(
            "whisper.cpp binary not found. Install whisper-cli or use an app build that bundles it."
        )
    }
}
