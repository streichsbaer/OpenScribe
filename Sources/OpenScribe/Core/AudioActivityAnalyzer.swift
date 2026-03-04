import Foundation

struct AudioActivityAssessment: Codable, Equatable {
    enum Verdict: String, Codable {
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

    var hasUsableSpeech: Bool {
        verdict == .usableSpeech
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
        threshold: 0
    )
}

struct AudioActivityAnalyzerConfiguration {
    var minTotalDurationSeconds: Double = 0.35
    var minPeakLevel: Double = 0.012
    var minActiveDurationSeconds: Double = 0.20
    var minActiveRatio: Double = 0.03
    var minActiveBurstSeconds: Double = 0.08
    var noiseFloorAlpha: Double = 0.08
    var minNoiseFloor: Double = 0.004
    var maxNoiseFloor: Double = 0.060
    var minActivityThreshold: Double = 0.018
    var activityNoiseMultiplier: Double = 2.4
    var thresholdUpdateRatio: Double = 0.75
    var instantThresholdFloor: Double = 0.012
    var instantThresholdCeiling: Double = 0.020

    static let `default` = AudioActivityAnalyzerConfiguration()
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
    private var instantThreshold: Double

    init(configuration: AudioActivityAnalyzerConfiguration = .default) {
        self.configuration = configuration
        self.noiseFloor = configuration.minNoiseFloor
        self.activityThreshold = configuration.minActivityThreshold
        self.instantThreshold = configuration.instantThresholdFloor
    }

    func ingest(rmsLevel: Float, frameCount: Int, sampleRate: Double) {
        guard frameCount > 0, sampleRate > 0 else {
            return
        }

        let durationSeconds = Double(frameCount) / sampleRate
        let boundedLevel = min(max(Double(rmsLevel), 0), configuration.maxNoiseFloor)

        totalDurationSeconds += durationSeconds
        weightedLevelSeconds += boundedLevel * durationSeconds
        peakLevel = max(peakLevel, boundedLevel)

        updateThresholds(using: boundedLevel)

        let isActive = boundedLevel >= activityThreshold || boundedLevel >= instantThreshold
        if isActive {
            activeDurationSeconds += durationSeconds
            currentActiveBurstSeconds += durationSeconds
            longestActiveBurstSeconds = max(longestActiveBurstSeconds, currentActiveBurstSeconds)
        } else {
            currentActiveBurstSeconds = 0
        }
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
        } else if activeRatio < configuration.minActiveRatio {
            verdict = .noUsableSpeech
            reason = "Speech activity ratio stayed below threshold."
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
            threshold: activityThreshold
        )
    }

    private func updateThresholds(using level: Double) {
        let cutoff = max(activityThreshold * configuration.thresholdUpdateRatio, configuration.minActivityThreshold)
        if level <= cutoff {
            noiseFloor = ((1 - configuration.noiseFloorAlpha) * noiseFloor) + (configuration.noiseFloorAlpha * level)
            noiseFloor = min(max(noiseFloor, configuration.minNoiseFloor), configuration.maxNoiseFloor)
        }

        activityThreshold = max(configuration.minActivityThreshold, noiseFloor * configuration.activityNoiseMultiplier)
        instantThreshold = max(
            configuration.instantThresholdFloor,
            min(configuration.instantThresholdCeiling, activityThreshold * 0.7)
        )
    }
}
