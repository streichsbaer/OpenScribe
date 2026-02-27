import Foundation

final class GroqPolishProvider: PolishProvider {
    let id = "groq_polish"
    let displayName = "Groq Polish"

    private let apiKey: String
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func polish(rawText: String, rulesMarkdown: String, model: String) async throws -> PolishResult {
        let start = Date()
        let content = try await performChatRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            systemPrompt: "You convert speech transcripts into clean Markdown. Return Markdown only.",
            userPrompt: makePolishUserPrompt(rawText: rawText, rulesMarkdown: rulesMarkdown)
        )

        return PolishResult(
            markdown: unwrapCodeBlockIfNeeded(content),
            providerId: id,
            model: model,
            latencyMs: Int(Date().timeIntervalSince(start) * 1_000)
        )
    }

    func proposeRulesDiff(rawText: String, polishedText: String, feedback: String, currentRules: String, model: String) async throws -> RulesDiffResult {
        let content = try await performChatRequest(
            endpoint: endpoint,
            apiKey: apiKey,
            model: model,
            systemPrompt: "You update markdown rules files via minimal unified diffs.",
            userPrompt: makeDiffPrompt(rawText: rawText, polishedText: polishedText, feedback: feedback, currentRules: currentRules)
        )

        let diff = unwrapCodeBlockIfNeeded(content)
        return RulesDiffResult(unifiedDiff: diff, summary: "Proposed rule updates from feedback")
    }
}
