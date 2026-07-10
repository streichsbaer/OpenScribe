import Foundation
import XCTest
@testable import OpenScribe

final class AudioActivityAnalyzerTests: XCTestCase {
    func testReportsNoUsableSpeechForSilentSample() {
        let analyzer = AudioActivityAnalyzer()

        for _ in 0..<64 {
            analyzer.ingest(rmsLevel: 0, frameCount: 512, sampleRate: 16_000)
        }

        let assessment = analyzer.assess()
        XCTAssertEqual(assessment.verdict, .noUsableSpeech)
        XCTAssertFalse(assessment.hasUsableSpeech)
        XCTAssertGreaterThanOrEqual(assessment.totalDurationMs, 2_000)
        XCTAssertEqual(assessment.activeDurationMs, 0)
    }

    func testReportsUsableSpeechForFixtureSpeechSample() throws {
        let analyzer = AudioActivityAnalyzer()
        let url = try fixtureAudioURL(named: "basic_en_smoke")
        try feedPCM16WAVSamples(from: url, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertTrue(assessment.hasUsableSpeech)
        XCTAssertGreaterThan(assessment.totalDurationMs, 300)
        XCTAssertGreaterThan(assessment.activeDurationMs, 150)
    }

    func testReportsUsableSpeechForQuietSpeechSurroundedBySilence() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.0004, chunks: 20, into: analyzer)
        ingest(level: 0.0030, chunks: 20, into: analyzer)
        ingest(level: 0.0004, chunks: 20, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertEqual(assessment.speechStartMs, 1_280)
        XCTAssertEqual(assessment.speechEndMs, 2_560)
        XCTAssertEqual(assessment.transcriptionRange(), 1_030..<3_060)
    }

    func testReportsUsableSpeechWhenQuietSpeechStartsImmediately() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.0030, chunks: 30, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertEqual(assessment.speechStartMs, 0)
        XCTAssertEqual(assessment.speechEndMs, 1_920)
    }

    func testReportsUsableSpeechWhenLoudSpeechStartsImmediately() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.050, chunks: 30, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertEqual(assessment.speechStartMs, 0)
        XCTAssertEqual(assessment.speechEndMs, 1_920)
    }

    func testReportsUsableSpeechForModulatedSpeech() {
        let analyzer = AudioActivityAnalyzer()

        for chunk in 0..<30 {
            let level: Float = chunk.isMultiple(of: 2) ? 0.003 : 0.006
            ingest(level: level, chunks: 1, into: analyzer)
        }

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertEqual(assessment.speechStartMs, 0)
        XCTAssertEqual(assessment.speechEndMs, 1_920)
    }

    func testReportsNoUsableSpeechForLowSteadyNoise() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.0012, chunks: 50, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .noUsableSpeech)
        XCTAssertNil(assessment.transcriptionRange())
    }

    func testAdaptsWhenSteadyAmbientNoiseStartsAboveMinimumThreshold() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.005, chunks: 50, into: analyzer)

        let assessment = analyzer.assess()
        XCTAssertEqual(assessment.verdict, .noUsableSpeech)
        XCTAssertLessThan(assessment.activeDurationMs, 150)
        XCTAssertGreaterThan(assessment.threshold, 0.005)
        XCTAssertNil(assessment.transcriptionRange())
    }

    func testAmbientCalibrationUsesDurationInsteadOfFrameCount() {
        let analyzer = AudioActivityAnalyzer()

        ingest(
            level: 0.005,
            chunks: 200,
            frameCount: 480,
            sampleRate: 48_000,
            into: analyzer
        )

        let assessment = analyzer.assess()
        XCTAssertEqual(assessment.verdict, .noUsableSpeech)
        XCTAssertLessThan(assessment.activeDurationMs, 150)
        XCTAssertGreaterThan(assessment.threshold, 0.005)
        XCTAssertNil(assessment.transcriptionRange())
    }

    func testDetectsSpeechAfterInitialAmbientCalibration() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.005, chunks: 20, into: analyzer)
        for chunk in 0..<20 {
            let level: Float = chunk.isMultiple(of: 2) ? 0.015 : 0.025
            ingest(level: level, chunks: 1, into: analyzer)
        }
        ingest(level: 0.005, chunks: 20, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertEqual(assessment.speechStartMs, 1_280)
        XCTAssertEqual(assessment.speechEndMs, 2_560)
        XCTAssertEqual(assessment.transcriptionRange(), 1_030..<3_060)
    }

    func testNoiseFloorCanFallAfterSpeechIsConfirmed() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.0015, chunks: 50, into: analyzer)
        let elevatedThreshold = analyzer.latestSnapshot.threshold
        for chunk in 0..<10 {
            let level: Float = chunk.isMultiple(of: 2) ? 0.006 : 0.012
            ingest(level: level, chunks: 1, into: analyzer)
        }
        ingest(level: 0.0004, chunks: 100, into: analyzer)

        XCTAssertLessThan(analyzer.latestSnapshot.threshold, elevatedThreshold)
        XCTAssertEqual(analyzer.assess().verdict, .usableSpeech)
    }

    func testTrailingSilenceDoesNotInvalidateDetectedSpeech() {
        let analyzer = AudioActivityAnalyzer()

        ingest(level: 0.004, chunks: 10, into: analyzer)
        ingest(level: 0.0004, chunks: 1_000, into: analyzer)

        let assessment = analyzer.assess()

        XCTAssertEqual(assessment.verdict, .usableSpeech, "Assessment reason: \(assessment.reason)")
        XCTAssertLessThan(assessment.activeRatio, 0.02)
        XCTAssertEqual(assessment.transcriptionRange(), 0..<1_140)
    }

    func testSnapshotUsesLogarithmicDBFSLevel() {
        let analyzer = AudioActivityAnalyzer()

        analyzer.ingest(rmsLevel: 0.01, frameCount: 1_024, sampleRate: 16_000)

        XCTAssertEqual(analyzer.latestSnapshot.levelDBFS, -40, accuracy: 0.01)
        XCTAssertTrue(analyzer.latestSnapshot.isActive)
    }

    func testRejectedAudioProvidesSpecificUserGuidance() {
        XCTAssertEqual(
            AudioActivityAssessment.noData.userGuidance,
            "No microphone audio was received. Check the selected input and try again."
        )

        let analyzer = AudioActivityAnalyzer()
        ingest(level: 0.0004, chunks: 20, into: analyzer)
        XCTAssertEqual(
            analyzer.assess().userGuidance,
            "Input was very quiet. Move closer to the microphone or choose a more sensitive input."
        )
    }

    private func ingest(
        level: Float,
        chunks: Int,
        frameCount: Int = 1_024,
        sampleRate: Double = 16_000,
        into analyzer: AudioActivityAnalyzer
    ) {
        for _ in 0..<chunks {
            analyzer.ingest(rmsLevel: level, frameCount: frameCount, sampleRate: sampleRate)
        }
    }

    private func feedPCM16WAVSamples(from url: URL, into analyzer: AudioActivityAnalyzer) throws {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)

        guard bytes.count >= 44 else {
            throw NSError(
                domain: "AudioActivityAnalyzerTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "WAV fixture is too small to parse."]
            )
        }
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            throw NSError(
                domain: "AudioActivityAnalyzerTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Fixture is not a RIFF/WAVE file."]
            )
        }

        var sampleRate: Double = 16_000
        var channels: Int = 1
        var bitsPerSample: Int = 16
        var dataOffset: Int?
        var dataSize: Int?

        var offset = 12
        while offset + 8 <= bytes.count {
            let chunkID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let chunkSize = Int(readUInt32LE(bytes, offset + 4))
            let chunkDataOffset = offset + 8
            let chunkEnd = chunkDataOffset + chunkSize

            if chunkEnd > bytes.count {
                break
            }

            if chunkID == "fmt " {
                guard chunkSize >= 16 else {
                    throw NSError(
                        domain: "AudioActivityAnalyzerTests",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "WAV fmt chunk is invalid."]
                    )
                }
                let audioFormat = readUInt16LE(bytes, chunkDataOffset)
                if audioFormat != 1 {
                    throw NSError(
                        domain: "AudioActivityAnalyzerTests",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "WAV fixture must use PCM encoding."]
                    )
                }
                channels = Int(readUInt16LE(bytes, chunkDataOffset + 2))
                sampleRate = Double(readUInt32LE(bytes, chunkDataOffset + 4))
                bitsPerSample = Int(readUInt16LE(bytes, chunkDataOffset + 14))
            } else if chunkID == "data" {
                dataOffset = chunkDataOffset
                dataSize = chunkSize
                break
            }

            let paddedSize = chunkSize + (chunkSize % 2)
            offset = chunkDataOffset + paddedSize
        }

        guard let dataOffset, let dataSize else {
            throw NSError(
                domain: "AudioActivityAnalyzerTests",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "WAV fixture is missing data chunk."]
            )
        }
        guard bitsPerSample == 16 else {
            throw NSError(
                domain: "AudioActivityAnalyzerTests",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "WAV fixture must use 16-bit PCM samples."]
            )
        }
        guard channels > 0 else {
            throw NSError(
                domain: "AudioActivityAnalyzerTests",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "WAV fixture has invalid channel count."]
            )
        }

        let bytesPerSample = bitsPerSample / 8
        let bytesPerFrame = bytesPerSample * channels
        let dataEnd = min(bytes.count, dataOffset + dataSize)
        let chunkFrames = 1_024

        var frameCount = 0
        var sumSquares: Float = 0
        var index = dataOffset

        while index + bytesPerFrame <= dataEnd {
            var frameSquareSum: Float = 0
            for channel in 0..<channels {
                let sampleOffset = index + (channel * bytesPerSample)
                let sample = Int16(bitPattern: readUInt16LE(bytes, sampleOffset))
                let normalized = Float(sample) / Float(Int16.max)
                frameSquareSum += normalized * normalized
            }

            sumSquares += frameSquareSum / Float(channels)
            frameCount += 1
            index += bytesPerFrame

            if frameCount == chunkFrames {
                let rms = sqrt(sumSquares / Float(frameCount))
                analyzer.ingest(rmsLevel: rms, frameCount: frameCount, sampleRate: sampleRate)
                frameCount = 0
                sumSquares = 0
            }
        }

        if frameCount > 0 {
            let rms = sqrt(sumSquares / Float(frameCount))
            analyzer.ingest(rmsLevel: rms, frameCount: frameCount, sampleRate: sampleRate)
        }
    }

    private func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private func fixtureAudioURL(named baseName: String) throws -> URL {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "Fixtures/audio"),
            Bundle.module.url(forResource: baseName, withExtension: "wav", subdirectory: "audio"),
            Bundle.module.url(forResource: baseName, withExtension: "wav")
        ]

        for candidate in candidates {
            if let candidate {
                return candidate
            }
        }

        throw NSError(
            domain: "AudioActivityAnalyzerTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture audio \(baseName).wav"]
        )
    }
}
