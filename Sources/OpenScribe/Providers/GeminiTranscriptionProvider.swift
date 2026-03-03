import Foundation

final class GeminiTranscriptionProvider: TranscriptionProvider {
    let id = "gemini_transcribe"
    let displayName = "Gemini Transcription"

    private let apiKey: String
    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioFileURL: URL, language: String?, model: String) async throws -> TranscriptResult {
        let start = Date()
        let response = try await performAudioTranscriptionViaChatRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            audioFileURL: audioFileURL,
            language: language
        )

        return TranscriptResult(
            text: response.text,
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000),
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens
        )
    }
}
