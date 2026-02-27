import Foundation

struct PolishPipeline {
    let providerFactory: ProviderFactory

    @MainActor
    func run(rawText: String, rulesMarkdown: String, settings: AppSettings) async throws -> PolishResult {
        let provider = try providerFactory.polishProvider(id: settings.polishProviderID)
        return try await provider.polish(rawText: rawText, rulesMarkdown: rulesMarkdown, model: settings.polishModel)
    }
}
