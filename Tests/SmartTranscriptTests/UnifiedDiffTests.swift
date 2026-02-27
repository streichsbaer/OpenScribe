import XCTest
@testable import SmartTranscript

final class UnifiedDiffTests: XCTestCase {
    func testApplySimplePatch() throws {
        let original = """
        # Rules
        - one
        - two
        """

        let diff = """
        --- Rules/rules.md
        +++ Rules/rules.md
        @@ -1,3 +1,4 @@
         # Rules
         - one
         - two
        +- three
        """

        let patch = try UnifiedDiff.parse(diff)
        try UnifiedDiff.validateSingleRulesFile(patch)
        let updated = try UnifiedDiff.apply(patch: patch, to: original)

        XCTAssertTrue(updated.contains("- three"))
    }

    func testRejectsUnexpectedPaths() throws {
        let diff = """
        --- other.txt
        +++ other.txt
        @@ -1,1 +1,1 @@
        -a
        +b
        """

        let patch = try UnifiedDiff.parse(diff)
        XCTAssertThrowsError(try UnifiedDiff.validateSingleRulesFile(patch))
    }
}
