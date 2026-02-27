@preconcurrency import AVFoundation
import Foundation

enum MicrophonePermissionState {
    case authorized
    case denied
    case undetermined
}

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?

    var onLevelUpdate: ((Float) -> Void)?

    var currentInputDeviceName: String? {
        AVCaptureDevice.default(for: .audio)?.localizedName
    }

    func permissionState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .undetermined
        }
    }

    @MainActor
    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording(to tempURL: URL) throws {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true) else {
            throw ProviderError.unsupported("Failed to create output audio format.")
        }

        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        audioFile = try AVAudioFile(forWriting: tempURL, settings: targetFormat.settings, commonFormat: .pcmFormatInt16, interleaved: true)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, inputFormat: inputFormat, outputFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        audioFile = nil
        converter = nil

        onLevelUpdate?(0)
    }

    private func handle(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        let level = rmsLevel(from: buffer, inputFormat: inputFormat)
        onLevelUpdate?(level)

        guard let converter = converter,
              let audioFile = audioFile else {
            return
        }

        let frameRatio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio) + 64

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            return
        }

        var error: NSError?
        final class OneShotFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var consumed = false

            func consumeOnce() -> Bool {
                lock.lock()
                defer { lock.unlock() }

                if consumed {
                    return false
                }

                consumed = true
                return true
            }
        }
        let oneShot = OneShotFlag()

        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if !oneShot.consumeOnce() {
                outStatus.pointee = .noDataNow
                return nil
            }

            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            return
        }

        if outputBuffer.frameLength > 0 {
            try? audioFile.write(from: outputBuffer)
        }
    }

    private func rmsLevel(from buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> Float {
        guard let channelData = buffer.floatChannelData else {
            if let intData = buffer.int16ChannelData {
                let frameLength = Int(buffer.frameLength)
                guard frameLength > 0 else { return 0 }

                var sum: Float = 0
                let data = intData[0]
                for idx in 0..<frameLength {
                    let normalized = Float(data[idx]) / Float(Int16.max)
                    sum += normalized * normalized
                }

                return sqrt(sum / Float(frameLength))
            }

            return 0
        }

        let channelCount = Int(inputFormat.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0 else { return 0 }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for idx in 0..<frameLength {
                let sample = samples[idx]
                sum += sample * sample
            }
        }

        let mean = sum / Float(frameLength * channelCount)
        return sqrt(mean)
    }
}
