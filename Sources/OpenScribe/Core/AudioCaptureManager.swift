@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum MicrophonePermissionState {
    case authorized
    case denied
    case undetermined
}

struct AudioCaptureResult {
    let assessment: AudioActivityAssessment
    let outputFrameCount: Int64
}

enum AudioCaptureError: Error, LocalizedError, Equatable, Sendable {
    case conversionFailed(String)
    case writeFailed(String)
    case finalizationFailed(String)
    case noOutputFrames

    var errorDescription: String? {
        switch self {
        case .conversionFailed(let details):
            return "Audio conversion failed: \(details)"
        case .writeFailed(let details):
            return "Audio capture could not be saved: \(details)"
        case .finalizationFailed(let details):
            return "Audio capture could not be finalized: \(details)"
        case .noOutputFrames:
            return "The microphone was active, but no audio frames were saved."
        }
    }
}

final class AudioCaptureManager {
    private var engine: AVAudioEngine?
    private var wavWriter: WavFileWriter?
    private var converter: AVAudioConverter?
    private var activityAnalyzer: AudioActivityAnalyzer?
    private var onPCMChunk: (@Sendable (Data, Bool) -> Void)?
    private var outputFormat: AVAudioFormat?
    private var captureTempURL: URL?
    private let failureLock = NSLock()
    private var captureFailure: AudioCaptureError?

    var onActivityUpdate: ((AudioActivitySnapshot) -> Void)?

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

    func startRecording(
        to tempURL: URL,
        inputDeviceID: String?,
        sampleRate: Double = 16_000,
        onPCMChunk: (@Sendable (Data, Bool) -> Void)? = nil
    ) throws {
        cancelActiveCapture()
        setCaptureFailure(nil)

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }

        let freshEngine = AVAudioEngine()
        try configureInputDeviceIfNeeded(inputDeviceID, on: freshEngine)

        let inputNode = freshEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw ProviderError.unsupported("The selected microphone returned an invalid input format.")
        }

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true) else {
            throw ProviderError.unsupported("Failed to create output audio format.")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw ProviderError.unsupported("Failed to prepare audio conversion for the selected microphone.")
        }
        self.converter = converter
        self.outputFormat = targetFormat
        captureTempURL = tempURL
        do {
            wavWriter = try WavFileWriter(
                url: tempURL,
                sampleRate: Int(targetFormat.sampleRate),
                channels: Int(targetFormat.channelCount)
            )
        } catch {
            cleanupCaptureResources(removeTemporaryFile: true)
            throw error
        }
        self.onPCMChunk = onPCMChunk
        activityAnalyzer = AudioActivityAnalyzer()

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, inputFormat: inputFormat, outputFormat: targetFormat)
        }

        freshEngine.prepare()
        do {
            try freshEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            freshEngine.stop()
            cleanupCaptureResources(removeTemporaryFile: true)
            let selectedInputDescription = inputDeviceID ?? "system default input"
            throw ProviderError.unsupported(
                "Unable to start audio capture on \(selectedInputDescription): \(error.localizedDescription)"
            )
        }
        engine = freshEngine
    }

    func stopRecording() throws -> AudioCaptureResult {
        teardownEngine()

        let assessment = activityAnalyzer?.assess() ?? .noData
        do {
            try flushConverter()
        } catch let error as AudioCaptureError {
            recordCaptureFailure(error)
        } catch {
            recordCaptureFailure(.conversionFailed(error.localizedDescription))
        }

        let outputFrameCount = wavWriter?.frameCount ?? 0
        do {
            try wavWriter?.close()
        } catch {
            recordCaptureFailure(.finalizationFailed(error.localizedDescription))
        }
        if assessment.totalDurationMs > 0, outputFrameCount == 0 {
            recordCaptureFailure(.noOutputFrames)
        }

        let failure = currentCaptureFailure()
        cleanupCaptureResources(removeTemporaryFile: false)

        onActivityUpdate?(.silence)
        if let failure {
            throw failure
        }
        return AudioCaptureResult(assessment: assessment, outputFrameCount: outputFrameCount)
    }

    private func teardownEngine() {
        guard let engine else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
    }

    private func cancelActiveCapture() {
        teardownEngine()
        try? wavWriter?.close()
        cleanupCaptureResources(removeTemporaryFile: true)
    }

    private func cleanupCaptureResources(removeTemporaryFile: Bool) {
        if removeTemporaryFile, let captureTempURL {
            try? FileManager.default.removeItem(at: captureTempURL)
        }
        wavWriter = nil
        converter = nil
        outputFormat = nil
        activityAnalyzer = nil
        onPCMChunk = nil
        captureTempURL = nil
        setCaptureFailure(nil)
    }

    private func handle(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) {
        let level = AudioLevelMeter.rmsLevel(from: buffer, format: inputFormat)
        activityAnalyzer?.ingest(
            rmsLevel: level,
            frameCount: Int(buffer.frameLength),
            sampleRate: inputFormat.sampleRate
        )
        if let snapshot = activityAnalyzer?.latestSnapshot {
            onActivityUpdate?(snapshot)
        }

        guard currentCaptureFailure() == nil else {
            return
        }

        guard let converter = converter,
              let wavWriter = wavWriter else {
            return
        }

        let frameRatio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * frameRatio) + 64

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            recordCaptureFailure(.conversionFailed("Unable to allocate converted audio buffer."))
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
            recordCaptureFailure(.conversionFailed(error?.localizedDescription ?? "Unknown converter error."))
            return
        }

        if outputBuffer.frameLength > 0 {
            do {
                let pcmData = try wavWriter.append(from: outputBuffer)
                onPCMChunk?(pcmData, activityAnalyzer?.latestSnapshot.isActive ?? false)
            } catch {
                recordCaptureFailure(.writeFailed(error.localizedDescription))
            }
        }
    }

    private func flushConverter() throws {
        guard let converter,
              let outputFormat,
              let wavWriter else {
            return
        }

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
                throw AudioCaptureError.conversionFailed("Unable to allocate final audio buffer.")
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }

            if status == .error || conversionError != nil {
                throw AudioCaptureError.conversionFailed(
                    conversionError?.localizedDescription ?? "Unable to flush the audio converter."
                )
            }

            if outputBuffer.frameLength > 0 {
                do {
                    let pcmData = try wavWriter.append(from: outputBuffer)
                    onPCMChunk?(pcmData, activityAnalyzer?.latestSnapshot.isActive ?? false)
                } catch {
                    throw AudioCaptureError.writeFailed(error.localizedDescription)
                }
            }

            if status == .endOfStream || outputBuffer.frameLength == 0 {
                return
            }
        }
    }

    private func recordCaptureFailure(_ failure: AudioCaptureError) {
        failureLock.lock()
        defer { failureLock.unlock() }
        if captureFailure == nil {
            captureFailure = failure
        }
    }

    private func setCaptureFailure(_ failure: AudioCaptureError?) {
        failureLock.lock()
        captureFailure = failure
        failureLock.unlock()
    }

    private func currentCaptureFailure() -> AudioCaptureError? {
        failureLock.lock()
        defer { failureLock.unlock() }
        return captureFailure
    }

    private func configureInputDeviceIfNeeded(_ inputDeviceID: String?, on engine: AVAudioEngine) throws {
        guard let inputDeviceID else {
            return
        }

        guard let audioUnit = engine.inputNode.audioUnit else {
            throw ProviderError.unsupported("Unable to access audio input unit.")
        }

        guard let coreAudioDeviceID = CoreAudioMicrophoneCatalog.audioDeviceID(for: inputDeviceID) else {
            throw ProviderError.unsupported("Selected microphone is unavailable.")
        }

        var mutableDeviceID = coreAudioDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw ProviderError.unsupported(
                "Unable to select the requested microphone (OSStatus \(status))."
            )
        }
    }
}

private final class WavFileWriter {
    private static let headerSize = 44
    private static let bitsPerSample: UInt16 = 16

    private let handle: FileHandle
    private let sampleRate: UInt32
    private let channels: UInt16
    private var dataBytesWritten: UInt32 = 0

    var frameCount: Int64 {
        let bytesPerFrame = Int64(channels) * Int64(Self.bitsPerSample / 8)
        guard bytesPerFrame > 0 else {
            return 0
        }
        return Int64(dataBytesWritten) / bytesPerFrame
    }

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

    @discardableResult
    func append(from buffer: AVAudioPCMBuffer) throws -> Data {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData else {
            return Data()
        }

        let byteCount = Int(audioBuffer.mDataByteSize)
        guard byteCount > 0 else {
            return Data()
        }

        let data = Data(bytes: dataPointer, count: byteCount)
        try handle.write(contentsOf: data)
        dataBytesWritten &+= UInt32(byteCount)
        return data
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
