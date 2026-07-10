@preconcurrency import AVFoundation
import Foundation
import XCTest
@testable import OpenScribe

final class TranscriptionAudioPreprocessorTests: XCTestCase {
    func testPrepareTrimsBothEndsAndKeepsConfiguredPadding() throws {
        let sourceURL = temporaryURL(extension: "wav")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeTestWAV(to: sourceURL, durationSeconds: 3)

        let prepared = try TranscriptionAudioPreprocessor.prepare(
            sourceURL: sourceURL,
            assessment: assessment(totalDurationMs: 3_000, speechStartMs: 1_000, speechEndMs: 1_500)
        )
        defer { prepared.cleanup() }

        XCTAssertNotEqual(prepared.fileURL, sourceURL)
        let outputFile = try AVAudioFile(forReading: prepared.fileURL)
        XCTAssertEqual(outputFile.length, 20_000, accuracy: 1)
    }

    func testPrepareUsesOriginalWhenSpeechRangeNeedsNoTrim() throws {
        let sourceURL = temporaryURL(extension: "wav")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try writeTestWAV(to: sourceURL, durationSeconds: 1)

        let prepared = try TranscriptionAudioPreprocessor.prepare(
            sourceURL: sourceURL,
            assessment: assessment(totalDurationMs: 1_000, speechStartMs: 100, speechEndMs: 700)
        )

        XCTAssertEqual(prepared.fileURL, sourceURL)
        XCTAssertNil(prepared.cleanupURL)
    }

    private func assessment(
        totalDurationMs: Int,
        speechStartMs: Int,
        speechEndMs: Int
    ) -> AudioActivityAssessment {
        AudioActivityAssessment(
            verdict: .usableSpeech,
            reason: "Usable speech activity detected.",
            totalDurationMs: totalDurationMs,
            activeDurationMs: speechEndMs - speechStartMs,
            longestActiveBurstMs: speechEndMs - speechStartMs,
            activeRatio: Double(speechEndMs - speechStartMs) / Double(totalDurationMs),
            peakLevel: 0.1,
            averageLevel: 0.05,
            noiseFloor: 0.001,
            threshold: 0.002,
            speechStartMs: speechStartMs,
            speechEndMs: speechEndMs
        )
    }

    private func writeTestWAV(to url: URL, durationSeconds: Double) throws {
        let sampleRate = 16_000.0
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        buffer.frameLength = frameCount
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frameCount) {
            samples[index] = sin(Float(index) * 0.05) * 0.1
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try file.write(from: buffer)
    }

    private func temporaryURL(extension pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("openscribe-audio-preprocessor-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}
