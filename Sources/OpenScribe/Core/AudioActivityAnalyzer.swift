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
    var initialCalibrationDurationSeconds: Double = 0.75
    var initialAmbientMinimumLevel: Double = 0.004
    var initialAmbientMaximumLevel: Double = 0.020
    var maximumAmbientVariation: Double = 0.08
    var minimumSpeechVariation: Double = 0.12
    var minNoiseFloor: Double = 0.0005
    var maxNoiseFloor: Double = 0.060
    var minActivityThreshold: Double = 0.0018
    var activityNoiseMultiplier: Double = 2.5
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
    private struct LevelSample {
        let level: Double
        var durationSeconds: Double
    }

    private struct LevelStatistics {
        let mean: Double
        let coefficientOfVariation: Double
    }

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
    private var speechIsConfirmed = false
    private var calibrationSamples: [LevelSample] = []
    private var calibrationDurationSeconds: Double = 0
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

        if speechIsConfirmed {
            lowerNoiseFloorIfNeeded(using: boundedLevel, isActive: isActive)
        } else {
            updateUnconfirmedActivity(
                level: boundedLevel,
                durationSeconds: durationSeconds,
                isActive: isActive
            )
        }

        latestSnapshot = AudioActivitySnapshot(
            rmsLevel: Float(boundedLevel),
            levelDBFS: Self.decibelsFS(for: boundedLevel),
            noiseFloor: Float(noiseFloor),
            threshold: Float(activityThreshold),
            isActive: isCurrentlyActive
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

    private func updateUnconfirmedActivity(level: Double, durationSeconds: Double, isActive: Bool) {
        appendCalibrationSample(level: level, durationSeconds: durationSeconds)

        guard let statistics = calibrationStatistics() else {
            return
        }

        let hasEnoughActivity = activeDurationSeconds >= configuration.minActiveDurationSeconds
            && longestActiveBurstSeconds >= configuration.minActiveBurstSeconds
        if hasEnoughActivity,
           statistics.coefficientOfVariation >= configuration.minimumSpeechVariation {
            confirmSpeech()
            return
        }

        let calibrationWindow = max(
            configuration.initialCalibrationDurationSeconds,
            configuration.minActiveDurationSeconds
        )
        let hasFullCalibrationWindow = calibrationDurationSeconds >= calibrationWindow - 0.000_001
        if hasFullCalibrationWindow, isInitialContinuousActivity {
            let resemblesAmbientNoise = statistics.coefficientOfVariation <= configuration.maximumAmbientVariation
                && statistics.mean >= configuration.initialAmbientMinimumLevel
                && statistics.mean <= configuration.initialAmbientMaximumLevel
            if resemblesAmbientNoise {
                rebaselineInitialAmbientNoise(to: statistics.mean)
                return
            }

            if hasEnoughActivity {
                confirmSpeech()
                return
            }
        }

        if !isActive {
            updateUnconfirmedNoiseFloor(using: level)
        }
    }

    private var isInitialContinuousActivity: Bool {
        speechStartSeconds == 0
            && activeDurationSeconds >= max(0, totalDurationSeconds - 0.000_001)
    }

    private func appendCalibrationSample(level: Double, durationSeconds: Double) {
        calibrationSamples.append(
            LevelSample(
                level: min(level, configuration.maxNoiseFloor),
                durationSeconds: durationSeconds
            )
        )
        calibrationDurationSeconds += durationSeconds

        let windowDuration = max(configuration.initialCalibrationDurationSeconds, configuration.minActiveDurationSeconds)
        var excessDuration = calibrationDurationSeconds - windowDuration
        while excessDuration > 0, !calibrationSamples.isEmpty {
            if calibrationSamples[0].durationSeconds <= excessDuration {
                let removedDuration = calibrationSamples.removeFirst().durationSeconds
                calibrationDurationSeconds -= removedDuration
                excessDuration -= removedDuration
            } else {
                calibrationSamples[0].durationSeconds -= excessDuration
                calibrationDurationSeconds -= excessDuration
                excessDuration = 0
            }
        }
    }

    private func calibrationStatistics() -> LevelStatistics? {
        guard calibrationDurationSeconds > 0 else {
            return nil
        }

        let weightedLevel = calibrationSamples.reduce(0.0) {
            $0 + ($1.level * $1.durationSeconds)
        }
        let mean = weightedLevel / calibrationDurationSeconds
        let weightedVariance = calibrationSamples.reduce(0.0) {
            let difference = $1.level - mean
            return $0 + (difference * difference * $1.durationSeconds)
        } / calibrationDurationSeconds
        let denominator = max(mean, configuration.minNoiseFloor)
        return LevelStatistics(
            mean: mean,
            coefficientOfVariation: sqrt(weightedVariance) / denominator
        )
    }

    private func confirmSpeech() {
        speechIsConfirmed = true
        calibrationSamples.removeAll(keepingCapacity: false)
        calibrationDurationSeconds = 0
    }

    private func rebaselineInitialAmbientNoise(to level: Double) {
        noiseFloor = min(max(level, configuration.minNoiseFloor), configuration.maxNoiseFloor)
        refreshActivityThreshold()
        activeDurationSeconds = 0
        currentActiveBurstSeconds = 0
        longestActiveBurstSeconds = 0
        speechStartSeconds = nil
        speechEndSeconds = nil
        isCurrentlyActive = false
    }

    private func updateUnconfirmedNoiseFloor(using level: Double) {
        let boundedLevel = min(max(level, configuration.minNoiseFloor), configuration.maxNoiseFloor)
        noiseFloor = ((1 - configuration.noiseFloorAlpha) * noiseFloor)
            + (configuration.noiseFloorAlpha * boundedLevel)
        refreshActivityThreshold()
    }

    private func lowerNoiseFloorIfNeeded(using level: Double, isActive: Bool) {
        guard !isActive, level < noiseFloor else {
            return
        }

        let boundedLevel = max(level, configuration.minNoiseFloor)
        noiseFloor = ((1 - configuration.noiseFloorAlpha) * noiseFloor)
            + (configuration.noiseFloorAlpha * boundedLevel)
        refreshActivityThreshold()
    }

    private func refreshActivityThreshold() {
        noiseFloor = min(max(noiseFloor, configuration.minNoiseFloor), configuration.maxNoiseFloor)
        activityThreshold = max(
            configuration.minActivityThreshold,
            noiseFloor * configuration.activityNoiseMultiplier
        )
    }

    private static func decibelsFS(for level: Double) -> Float {
        guard level > 0 else {
            return -80
        }
        return Float(max(-80, 20 * log10(level)))
    }
}
