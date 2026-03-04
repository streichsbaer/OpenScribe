@preconcurrency import AVFoundation
import Foundation

enum MicrophonePermissionState {
    case authorized
    case denied
    case undetermined
}

final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var wavWriter: WavFileWriter?
    private var converter: AVAudioConverter?
    private var activityAnalyzer: AudioActivityAnalyzer?

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
        wavWriter = try WavFileWriter(
            url: tempURL,
            sampleRate: Int(targetFormat.sampleRate),
            channels: Int(targetFormat.channelCount)
        )
        activityAnalyzer = AudioActivityAnalyzer()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, inputFormat: inputFormat, outputFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> AudioActivityAssessment {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        try? wavWriter?.close()
        wavWriter = nil
        converter = nil
        let assessment = activityAnalyzer?.assess() ?? .noData
        activityAnalyzer = nil

        onLevelUpdate?(0)
        return assessment
    }

    private func handle(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        let level = rmsLevel(from: buffer, inputFormat: inputFormat)
        activityAnalyzer?.ingest(
            rmsLevel: level,
            frameCount: Int(buffer.frameLength),
            sampleRate: inputFormat.sampleRate
        )
        onLevelUpdate?(level)

        guard let converter = converter,
              let wavWriter = wavWriter else {
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
            try? wavWriter.append(from: outputBuffer)
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

private final class WavFileWriter {
    private static let headerSize = 44
    private static let bitsPerSample: UInt16 = 16

    private let handle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private var dataBytesWritten: UInt32 = 0

    init(url: URL, sampleRate: Int, channels: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        self.sampleRate = UInt32(sampleRate)
        self.channels = UInt16(channels)

        try writeHeader(dataSize: 0)
    }

    func append(from buffer: AVAudioPCMBuffer) throws {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData else {
            return
        }

        let byteCount = Int(audioBuffer.mDataByteSize)
        guard byteCount > 0 else {
            return
        }

        let data = Data(bytes: dataPointer, count: byteCount)
        try handle.write(contentsOf: data)
        dataBytesWritten &+= UInt32(byteCount)
    }

    func close() throws {
        try writeHeader(dataSize: dataBytesWritten)
        try handle.close()
    }

    private func writeHeader(dataSize: UInt32) throws {
        let byteRate = sampleRate * UInt32(channels) * UInt32(Self.bitsPerSample / 8)
        let blockAlign = channels * (Self.bitsPerSample / 8)
        let riffChunkSize = UInt32(Self.headerSize - 8) &+ dataSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(littleEndianBytes(riffChunkSize))
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(littleEndianBytes(UInt32(16)))
        header.append(littleEndianBytes(UInt16(1)))
        header.append(littleEndianBytes(channels))
        header.append(littleEndianBytes(sampleRate))
        header.append(littleEndianBytes(byteRate))
        header.append(littleEndianBytes(blockAlign))
        header.append(littleEndianBytes(Self.bitsPerSample))
        header.append("data".data(using: .ascii)!)
        header.append(littleEndianBytes(dataSize))

        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
        try handle.seekToEnd()
    }

    private func littleEndianBytes(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }

    private func littleEndianBytes(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }
}
