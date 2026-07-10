import Foundation

protocol TranscriptionProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func transcribe(audioFileURL: URL, language: String?, model: String, instruction: String?) async throws -> TranscriptResult
}

protocol PolishProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func polish(rawText: String, rulesMarkdown: String, model: String, instruction: String?) async throws -> PolishResult
}
