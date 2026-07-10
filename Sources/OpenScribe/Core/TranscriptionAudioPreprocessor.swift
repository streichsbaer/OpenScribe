@preconcurrency import AVFoundation
import Foundation

struct PreparedTranscriptionAudio {
    let fileURL: URL
    let cleanupURL: URL?

    func cleanup(fileManager: FileManager = .default) {
        guard let cleanupURL else {
            return
        }
        try? fileManager.removeItem(at: cleanupURL)
    }
}

enum TranscriptionAudioPreprocessor {
    static func prepare(
        sourceURL: URL,
        assessment: AudioActivityAssessment?,
        fileManager: FileManager = .default
    ) throws -> PreparedTranscriptionAudio {
        guard let assessment,
              let range = assessment.transcriptionRange(),
              range.lowerBound > 0 || range.upperBound < assessment.totalDurationMs else {
            return PreparedTranscriptionAudio(fileURL: sourceURL, cleanupURL: nil)
        }

        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent("openscribe-transcription-\(UUID().uuidString).wav")
        do {
            try writeTrimmedPCM(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                startMs: range.lowerBound,
                endMs: range.upperBound
            )
            return PreparedTranscriptionAudio(fileURL: destinationURL, cleanupURL: destinationURL)
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    private static func writeTrimmedPCM(
        sourceURL: URL,
        destinationURL: URL,
        startMs: Int,
        endMs: Int
    ) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, endMs > startMs else {
            throw ProviderError.unsupported("Unable to determine a valid transcription audio range.")
        }

        let startFrame = min(
            inputFile.length,
            AVAudioFramePosition((Double(startMs) / 1_000 * sampleRate).rounded(.down))
        )
        let requestedEndFrame = AVAudioFramePosition((Double(endMs) / 1_000 * sampleRate).rounded(.up))
        let endFrame = min(inputFile.length, requestedEndFrame)
        guard endFrame > startFrame else {
            throw ProviderError.unsupported("Trimmed transcription audio would be empty.")
        }

        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: format.settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        inputFile.framePosition = startFrame

        var remainingFrames = endFrame - startFrame
        while remainingFrames > 0 {
            let frameCapacity = AVAudioFrameCount(min(remainingFrames, 8_192))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
                throw ProviderError.unsupported("Unable to allocate transcription audio buffer.")
            }
            try inputFile.read(into: buffer, frameCount: frameCapacity)
            guard buffer.frameLength > 0 else {
                break
            }
            try outputFile.write(from: buffer)
            remainingFrames -= AVAudioFramePosition(buffer.frameLength)
        }

        guard remainingFrames == 0 else {
            throw ProviderError.processFailed("Transcription audio ended before the requested trim range.")
        }
    }
}
