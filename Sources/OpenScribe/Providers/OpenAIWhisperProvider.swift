import Foundation

final class OpenAIWhisperProvider: TranscriptionProvider {
    let id = "openai_whisper"
    let displayName = "OpenAI Whisper"

    private let apiKey: String
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribe(audioFileURL: URL, language: String?, model: String) async throws -> TranscriptResult {
        let start = Date()
        let response = try await performWhisperRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            audioFileURL: audioFileURL,
            language: language,
            extraFields: [
                "temperature": "0",
                "response_format": "json"
            ]
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
