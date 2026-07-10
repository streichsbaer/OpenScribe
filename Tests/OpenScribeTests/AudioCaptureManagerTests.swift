import Foundation
import XCTest
@testable import OpenScribe

final class AudioCaptureManagerTests: XCTestCase {
    func testStartRecordingThrowsWhenSelectedDeviceIsUnavailable() throws {
        let manager = AudioCaptureManager()
        let tempURL = temporaryFileURL()

        XCTAssertThrowsError(
            try manager.startRecording(to: tempURL, inputDeviceID: "__nonexistent_microphone_device__")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func testStopWithoutActiveCaptureReturnsNoData() throws {
        let manager = AudioCaptureManager()

        let result = try manager.stopRecording()

        XCTAssertEqual(result.assessment, .noData)
        XCTAssertEqual(result.outputFrameCount, 0)
    }

    func testCaptureErrorsProvideActionableDescriptions() {
        XCTAssertEqual(
            AudioCaptureError.noOutputFrames.localizedDescription,
            "The microphone was active, but no audio frames were saved."
        )
        XCTAssertEqual(
            AudioCaptureError.writeFailed("Disk full").localizedDescription,
            "Audio capture could not be saved: Disk full"
        )
    }

    private func temporaryFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
        let fileName = "openscribe-audio-capture-test-\(UUID().uuidString).wav"
        return directory.appendingPathComponent(fileName)
    }
}
