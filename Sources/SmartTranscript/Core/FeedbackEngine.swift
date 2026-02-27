import Foundation

struct FeedbackProposal {
    let diffResult: RulesDiffResult
    let updatedRules: String
}

final class FeedbackEngine {
    private let polishPipeline: PolishPipeline
    private let rulesStore: RulesStore

    init(polishPipeline: PolishPipeline, rulesStore: RulesStore) {
        self.polishPipeline = polishPipeline
        self.rulesStore = rulesStore
    }

    @MainActor
    func propose(
        rawText: String,
        polishedText: String,
        feedback: String,
        settings: AppSettings
    ) async throws -> FeedbackProposal {
        let currentRules = try rulesStore.load()
        let diffResult = try await polishPipeline.proposeDiff(
            rawText: rawText,
            polishedText: polishedText,
            feedback: feedback,
            currentRules: currentRules,
            settings: settings
        )

        let patch = try UnifiedDiff.parse(diffResult.unifiedDiff)
        try UnifiedDiff.validateSingleRulesFile(patch)
        let updated = try UnifiedDiff.apply(patch: patch, to: currentRules)

        return FeedbackProposal(diffResult: diffResult, updatedRules: updated)
    }

    @MainActor
    func applyApproved(proposal: FeedbackProposal) throws {
        try rulesStore.save(proposal.updatedRules)
        rulesStore.appendHistory(summary: proposal.diffResult.summary, diff: proposal.diffResult.unifiedDiff, approved: true)
    }

    @MainActor
    func reject(_ proposal: FeedbackProposal) {
        rulesStore.appendHistory(summary: proposal.diffResult.summary, diff: proposal.diffResult.unifiedDiff, approved: false)
    }
}
