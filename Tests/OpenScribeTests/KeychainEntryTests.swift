import XCTest
@testable import OpenScribe

final class KeychainEntryTests: XCTestCase {
    func testEnvironmentVariableMappings() {
        XCTAssertEqual(KeychainEntry.openAI.environmentVariableNames, ["OPENAI_API_KEY"])
        XCTAssertEqual(KeychainEntry.groq.environmentVariableNames, ["GROQ_API_KEY"])
        XCTAssertEqual(
            KeychainEntry.openRouter.environmentVariableNames,
            ["SCRIBE_OPENROUTER_API_KEY", "OPENROUTER_API_KEY"]
        )
        XCTAssertEqual(KeychainEntry.gemini.environmentVariableNames, ["GEMINI_API_KEY"])
    }

    func testProviderDisplayNames() {
        XCTAssertEqual(KeychainEntry.openAI.providerDisplayName, "OpenAI")
        XCTAssertEqual(KeychainEntry.groq.providerDisplayName, "Groq")
        XCTAssertEqual(KeychainEntry.openRouter.providerDisplayName, "OpenRouter")
        XCTAssertEqual(KeychainEntry.gemini.providerDisplayName, "Gemini")
    }
}
