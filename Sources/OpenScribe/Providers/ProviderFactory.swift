import Foundation

@MainActor
final class ProviderFactory {
    private let apiKeyResolver: APIKeyResolver
    private let modelManager: ModelDownloadManager

    init(keychain: KeychainStore, modelManager: ModelDownloadManager) {
        self.apiKeyResolver = APIKeyResolver(keychain: keychain)
        self.modelManager = modelManager
    }

    func transcriptionProvider(id: String) throws -> any TranscriptionProvider {
        switch id {
        case "whispercpp":
            let binary = try resolveWhisperBinary()
            return WhisperCppProvider(binaryURL: binary, modelManager: modelManager)
        case "openai_whisper":
            guard let key = apiKeyResolver.resolve(.openAI).value else {
                throw ProviderError.missingAPIKey("OpenAI")
            }
            return OpenAIWhisperProvider(apiKey: key)
        case "groq_whisper":
            guard let key = apiKeyResolver.resolve(.groq).value else {
                throw ProviderError.missingAPIKey("Groq")
            }
            return GroqWhisperProvider(apiKey: key)
        case "openrouter_transcribe":
            guard let key = apiKeyResolver.resolve(.openRouter).value else {
                throw ProviderError.missingAPIKey("OpenRouter")
            }
            return OpenRouterTranscriptionProvider(apiKey: key)
        case "gemini_transcribe":
            guard let key = apiKeyResolver.resolve(.gemini).value else {
                throw ProviderError.missingAPIKey("Gemini")
            }
            return GeminiTranscriptionProvider(apiKey: key)
        default:
            throw ProviderError.unsupported("Unknown transcription provider: \(id)")
        }
    }

    func polishProvider(id: String) throws -> any PolishProvider {
        switch id {
        case "openai_polish":
            guard let key = apiKeyResolver.resolve(.openAI).value else {
                throw ProviderError.missingAPIKey("OpenAI")
            }
            return OpenAIPolishProvider(apiKey: key)
        case "groq_polish":
            guard let key = apiKeyResolver.resolve(.groq).value else {
                throw ProviderError.missingAPIKey("Groq")
            }
            return GroqPolishProvider(apiKey: key)
        case "openrouter_polish":
            guard let key = apiKeyResolver.resolve(.openRouter).value else {
                throw ProviderError.missingAPIKey("OpenRouter")
            }
            return OpenRouterPolishProvider(apiKey: key)
        case "gemini_polish":
            guard let key = apiKeyResolver.resolve(.gemini).value else {
                throw ProviderError.missingAPIKey("Gemini")
            }
            return GeminiPolishProvider(apiKey: key)
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
