import Foundation

struct AudioActivityAssessment: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Sendable {
        case usableSpeech
        case noUsableSpeech
    }

    let verdict: Verdict
    let reason: String
    let totalDurationMs: Int
    let activeDurationMs: Int
    let longestActiveBurstMs: Int
    let activeRatio: Double
    let peakLevel: Double
    let averageLevel: Double
    let noiseFloor: Double
    let threshold: Double
    let speechStartMs: Int?
    let speechEndMs: Int?

    var hasUsableSpeech: Bool {
        verdict == .usableSpeech
    }

    var userGuidance: String {
        switch reason {
        case "No audio data captured.":
            return "No microphone audio was received. Check the selected input and try again."
        case "Recording was too short.":
            return "Recording was too short. Speak for a little longer and try again."
        case "Signal peak stayed below speech threshold.":
            return "Input was very quiet. Move closer to the microphone or choose a more sensitive input."
        case "No sustained speech activity detected.":
            return "No sustained speech was detected. Check the microphone level and try again."
        default:
            return hasUsableSpeech ? "Usable speech detected." : "No usable speech was detected. Check the microphone and try again."
        }
    }

    static let noData = AudioActivityAssessment(
        verdict: .noUsableSpeech,
        reason: "No audio data captured.",
        totalDurationMs: 0,
        activeDurationMs: 0,
        longestActiveBurstMs: 0,
        activeRatio: 0,
        peakLevel: 0,
        averageLevel: 0,
        noiseFloor: 0,
        threshold: 0,
        speechStartMs: nil,
        speechEndMs: nil
    )

    func transcriptionRange(preRollMs: Int = 250, postRollMs: Int = 500) -> Range<Int>? {
        guard hasUsableSpeech,
              let speechStartMs,
              let speechEndMs,
              speechEndMs > speechStartMs else {
            return nil
        }

        let start = max(0, speechStartMs - preRollMs)
        let end = min(totalDurationMs, speechEndMs + postRollMs)
        return start..<max(start, end)
    }
}

struct AudioActivityAnalyzerConfiguration {
    var minTotalDurationSeconds: Double = 0.35
    var minPeakLevel: Double = 0.002
    var minActiveDurationSeconds: Double = 0.15
    var minActiveBurstSeconds: Double = 0.06
    var noiseFloorAlpha: Double = 0.04
    var minNoiseFloor: Double = 0.0005
    var maxNoiseFloor: Double = 0.060
    var minActivityThreshold: Double = 0.0018
    var activityNoiseMultiplier: Double = 2.5
    var thresholdUpdateRatio: Double = 0.85
    var releaseThresholdRatio: Double = 0.65

    static let `default` = AudioActivityAnalyzerConfiguration()
}

struct AudioActivitySnapshot: Equatable, Sendable {
    let rmsLevel: Float
    let levelDBFS: Float
    let noiseFloor: Float
    let threshold: Float
    let isActive: Bool

    static let silence = AudioActivitySnapshot(
        rmsLevel: 0,
        levelDBFS: -80,
        noiseFloor: 0,
        threshold: 0,
        isActive: false
    )
}

final class AudioActivityAnalyzer {
    private let configuration: AudioActivityAnalyzerConfiguration

    private var totalDurationSeconds: Double = 0
    private var activeDurationSeconds: Double = 0
    private var currentActiveBurstSeconds: Double = 0
    private var longestActiveBurstSeconds: Double = 0
    private var weightedLevelSeconds: Double = 0
    private var peakLevel: Double = 0
    private var noiseFloor: Double
    private var activityThreshold: Double
    private var speechStartSeconds: Double?
    private var speechEndSeconds: Double?
    private var isCurrentlyActive = false
    private(set) var latestSnapshot = AudioActivitySnapshot.silence

    init(configuration: AudioActivityAnalyzerConfiguration = .default) {
        self.configuration = configuration
        self.noiseFloor = configuration.minNoiseFloor
        self.activityThreshold = configuration.minActivityThreshold
    }

    func ingest(rmsLevel: Float, frameCount: Int, sampleRate: Double) {
        guard frameCount > 0, sampleRate > 0 else {
            return
        }

        let durationSeconds = Double(frameCount) / sampleRate
        let boundedLevel = min(max(Double(rmsLevel), 0), 1)
        let frameStartSeconds = totalDurationSeconds

        totalDurationSeconds += durationSeconds
        weightedLevelSeconds += boundedLevel * durationSeconds
        peakLevel = max(peakLevel, boundedLevel)

        let comparisonThreshold = isCurrentlyActive
            ? activityThreshold * configuration.releaseThresholdRatio
            : activityThreshold
        let isActive = boundedLevel >= comparisonThreshold
        if isActive {
            if speechStartSeconds == nil {
                speechStartSeconds = frameStartSeconds
            }
            speechEndSeconds = totalDurationSeconds
            activeDurationSeconds += durationSeconds
            currentActiveBurstSeconds += durationSeconds
            longestActiveBurstSeconds = max(longestActiveBurstSeconds, currentActiveBurstSeconds)
        } else {
            currentActiveBurstSeconds = 0
        }
        isCurrentlyActive = isActive

        updateThresholds(using: boundedLevel, isActive: isActive)
        latestSnapshot = AudioActivitySnapshot(
            rmsLevel: Float(boundedLevel),
            levelDBFS: Self.decibelsFS(for: boundedLevel),
            noiseFloor: Float(noiseFloor),
            threshold: Float(activityThreshold),
            isActive: isActive
        )
    }

    func assess() -> AudioActivityAssessment {
        guard totalDurationSeconds > 0 else {
            return .noData
        }

        let averageLevel = weightedLevelSeconds / totalDurationSeconds
        let activeRatio = activeDurationSeconds / totalDurationSeconds
        let verdict: AudioActivityAssessment.Verdict
        let reason: String

        if totalDurationSeconds < configuration.minTotalDurationSeconds {
            verdict = .noUsableSpeech
            reason = "Recording was too short."
        } else if peakLevel < configuration.minPeakLevel {
            verdict = .noUsableSpeech
            reason = "Signal peak stayed below speech threshold."
        } else if activeDurationSeconds < configuration.minActiveDurationSeconds || longestActiveBurstSeconds < configuration.minActiveBurstSeconds {
            verdict = .noUsableSpeech
            reason = "No sustained speech activity detected."
        } else {
            verdict = .usableSpeech
            reason = "Usable speech activity detected."
        }

        return AudioActivityAssessment(
            verdict: verdict,
            reason: reason,
            totalDurationMs: Int((totalDurationSeconds * 1_000).rounded()),
            activeDurationMs: Int((activeDurationSeconds * 1_000).rounded()),
            longestActiveBurstMs: Int((longestActiveBurstSeconds * 1_000).rounded()),
            activeRatio: activeRatio,
            peakLevel: peakLevel,
            averageLevel: averageLevel,
            noiseFloor: noiseFloor,
            threshold: activityThreshold,
            speechStartMs: speechStartSeconds.map { Int(($0 * 1_000).rounded()) },
            speechEndMs: speechEndSeconds.map { Int(($0 * 1_000).rounded()) }
        )
    }

    private func updateThresholds(using level: Double, isActive: Bool) {
        let cutoff = max(activityThreshold * configuration.thresholdUpdateRatio, configuration.minActivityThreshold)
        if !isActive, level <= cutoff {
            let boundedNoiseLevel = min(level, configuration.maxNoiseFloor)
            noiseFloor = ((1 - configuration.noiseFloorAlpha) * noiseFloor) + (configuration.noiseFloorAlpha * boundedNoiseLevel)
            noiseFloor = min(max(noiseFloor, configuration.minNoiseFloor), configuration.maxNoiseFloor)
        }

        activityThreshold = max(configuration.minActivityThreshold, noiseFloor * configuration.activityNoiseMultiplier)
    }

    private static func decibelsFS(for level: Double) -> Float {
        guard level > 0 else {
            return -80
        }
        return Float(max(-80, 20 * log10(level)))
    }
}
