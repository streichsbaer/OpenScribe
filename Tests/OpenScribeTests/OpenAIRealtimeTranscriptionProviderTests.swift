import Foundation
import XCTest
@testable import OpenScribe

final class OpenAIRealtimeTranscriptionProviderTests: XCTestCase {
    func testSessionUpdatePayloadUsesRealtimeTranscriptionSchema() throws {
        let payload = OpenAIRealtimeTranscriptionSession.sessionUpdatePayload(
            model: "gpt-realtime-whisper",
            language: "en",
            sampleRate: 24_000
        )

        XCTAssertEqual(payload["type"] as? String, "session.update")

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")

        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)

        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-realtime-whisper")
        XCTAssertEqual(transcription["language"] as? String, "en")
        XCTAssertTrue(input["turn_detection"] is NSNull)
    }

    func testRealtimeAudioSenderPreservesChunkOrderBeforeFinish() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let sender = OpenAIRealtimeAudioSender { data in
            await recorder.append(data)
        }

        sender.append(Data([0x01]))
        sender.append(Data([0x02]))
        sender.append(Data([0x03]))

        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [
            Data([0x01]),
            Data([0x02]),
            Data([0x03])
        ])
    }

    func testRealtimeAudioSenderBuffersChunksUntilReady() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let gate = RealtimeAudioSendGate()
        let sender = OpenAIRealtimeAudioSender(
            onReady: {
                await gate.waitUntilOpened()
            },
            onSend: { data in
                await recorder.append(data)
            }
        )

        sender.append(Data([0x01]))
        sender.append(Data([0x02]))
        try await Task.sleep(nanoseconds: 20_000_000)
        let chunksBeforeReady = await recorder.chunks
        XCTAssertEqual(chunksBeforeReady, [])

        await gate.open()
        sender.append(Data([0x03]))
        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [
            Data([0x01]),
            Data([0x02]),
            Data([0x03])
        ])
    }

    func testRealtimeAudioSenderTrimsQuietEdgesWithProtectedPadding() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let sender = OpenAIRealtimeAudioSender(
            onSend: { data in
                await recorder.append(data)
            },
            sampleRate: 4
        )

        sender.append(Data([0x01, 0x01]), isActive: false)
        sender.append(Data([0x02, 0x02]), isActive: false)
        sender.append(Data([0x03, 0x03]), isActive: true)
        sender.append(Data([0x04, 0x04]), isActive: false)
        sender.append(Data([0x05, 0x05]), isActive: false)
        sender.append(Data([0x06, 0x06]), isActive: false)

        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [
            Data([0x02, 0x02]),
            Data([0x03, 0x03]),
            Data([0x04, 0x04]),
            Data([0x05, 0x05])
        ])
    }

    func testRealtimeAudioSenderKeepsPreRollWhenSpeechResumesAfterLongPause() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let sender = OpenAIRealtimeAudioSender(
            onSend: { data in
                await recorder.append(data)
            },
            sampleRate: 4
        )

        sender.append(Data([0x01, 0x01]), isActive: true)
        sender.append(Data([0x02, 0x02]), isActive: false)
        sender.append(Data([0x03, 0x03]), isActive: false)
        sender.append(Data([0x04, 0x04]), isActive: false)
        sender.append(Data([0x05, 0x05]), isActive: true)

        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [
            Data([0x01, 0x01]),
            Data([0x02, 0x02]),
            Data([0x03, 0x03]),
            Data([0x04, 0x04]),
            Data([0x05, 0x05])
        ])
    }

    func testRealtimeAudioSenderDropsAllQuietRecording() async throws {
        let recorder = RealtimeAudioSendRecorder()
        let sender = OpenAIRealtimeAudioSender { data in
            await recorder.append(data)
        }

        sender.append(Data([0x01]), isActive: false)
        sender.append(Data([0x02]), isActive: false)
        try await sender.finishSending()

        let chunks = await recorder.chunks
        XCTAssertEqual(chunks, [])
    }

    func testRealtimeAudioSenderFailsWhenNetworkBufferOverflows() async {
        let gate = RealtimeAudioSendGate()
        let sender = OpenAIRealtimeAudioSender(
            onReady: {
                await gate.waitUntilOpened()
            },
            onSend: { _ in },
            maxBufferedChunks: 2
        )

        sender.append(Data([0x01]))
        sender.append(Data([0x02]))
        sender.append(Data([0x03]))

        do {
            try await sender.finishSending()
            XCTFail("Expected realtime buffer overflow.")
        } catch let error as RealtimeAudioSenderError {
            XCTAssertEqual(error, .bufferOverflow)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await gate.open()
    }
}

private actor RealtimeAudioSendRecorder {
    private(set) var chunks: [Data] = []

    func append(_ data: Data) {
        chunks.append(data)
    }
}

private actor RealtimeAudioSendGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilOpened() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations = []
        for continuation in pending {
            continuation.resume()
        }
    }
}
