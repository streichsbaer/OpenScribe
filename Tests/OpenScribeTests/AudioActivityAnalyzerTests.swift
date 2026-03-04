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
