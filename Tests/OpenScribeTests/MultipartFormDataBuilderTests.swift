import Foundation
import XCTest
@testable import OpenScribe

final class MultipartFormDataBuilderTests: XCTestCase {
    func testWritesDeterministicMultipartBodyToFile() throws {
        let sourceURL = temporaryURL(extension: "wav")
        let destinationURL = temporaryURL(extension: "body")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }
        let audioBytes = Data([0x00, 0x01, 0x02, 0x03, 0xFF])
        try audioBytes.write(to: sourceURL)

        let builder = MultipartFormDataBuilder(boundary: "TestBoundary")
        try builder.writeBody(
            fields: ["model": "whisper", "language": "en"],
            fileFieldName: "file",
            fileURL: sourceURL,
            mimeType: "audio/wav",
            destinationURL: destinationURL
        )

        let body = try Data(contentsOf: destinationURL)
        let text = try XCTUnwrap(String(data: body, encoding: .isoLatin1))
        let languagePosition = try XCTUnwrap(text.range(of: "name=\"language\""))
        let modelPosition = try XCTUnwrap(text.range(of: "name=\"model\""))
        XCTAssertLessThan(languagePosition.lowerBound, modelPosition.lowerBound)
        XCTAssertTrue(text.contains("filename=\"\(sourceURL.lastPathComponent)\""))
        XCTAssertTrue(text.contains("Content-Type: audio/wav"))
        XCTAssertNotNil(body.range(of: audioBytes))
        XCTAssertTrue(text.hasSuffix("\r\n--TestBoundary--\r\n"))
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("openscribe-multipart-test-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}
