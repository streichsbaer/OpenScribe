import XCTest
@testable import SmartTranscript

final class HotkeyDisplayTests: XCTestCase {
    func testStartStopDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .startStopDefault), "Fn+Space")
    }

    func testCopyOnlyDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .copyOnlyDefault), "Ctrl+Option+C")
    }

    func testPasteDefaultDisplayString() {
        XCTAssertEqual(HotkeyDisplay.string(for: .pasteDefault), "Ctrl+Option+V")
    }
}
