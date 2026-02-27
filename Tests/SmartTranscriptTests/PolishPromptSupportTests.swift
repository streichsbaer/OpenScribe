import XCTest
@testable import SmartTranscript

final class PolishPromptSupportTests: XCTestCase {
    func testSanitizePolishedOutputRemovesUnrequestedGlossarySection() {
        let raw = "This is a regular dictation with no extra sections."
        let polished = """
        This is the cleaned transcript.

        ## Glossary
        - `seismic -> Cysmiq`
        """

        let sanitized = sanitizePolishedOutput(polished, rawText: raw)
        XCTAssertEqual(sanitized, "This is the cleaned transcript.")
    }

    func testSanitizePolishedOutputKeepsGlossaryWhenSpoken() {
        let raw = "Please add a glossary section with custom tokens."
        let polished = """
        Main text.

        ## Glossary
        - `token -> value`
        """

        let sanitized = sanitizePolishedOutput(polished, rawText: raw)
        XCTAssertEqual(sanitized, polished)
    }
}
