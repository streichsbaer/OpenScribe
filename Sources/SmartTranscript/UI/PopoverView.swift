import AVFoundation
import Foundation
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var shell: AppShell
    @StateObject private var playbackManager = AudioPlaybackManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputSection
            Divider()
            sessionSection
            Divider()
            textSection

            if let hotkeyError = shell.hotkeyError {
                Text("Hotkey issue: \(hotkeyError)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if let lastError = shell.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            HStack {
                Text(shell.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Settings") {
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(width: 520)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Input")
                .font(.headline)

            Text(shell.currentSession?.metadata.inputDeviceName ?? "Device: \(AVAudioSessionBridge.defaultInputName)")
                .font(.subheadline)

            HStack(spacing: 8) {
                Text("Level")
                    .font(.caption)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 10)
                    Capsule()
                        .fill(shell.microphoneIndicatorColorName == "green" ? Color.green : Color.gray)
                        .frame(width: max(6, CGFloat(shell.meterLevel) * 220), height: 10)
                }
                .frame(width: 220)
            }

            Text(permissionText)
                .font(.caption)
                .foregroundColor(shell.permissionState == .authorized ? .secondary : .orange)

        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.headline)

            Text("State: \(shell.sessionState.rawValue)")
                .font(.subheadline)

            HStack {
                Button(shell.sessionState == .recording ? "Stop (Fn+Space)" : "Start (Fn+Space)") {
                    shell.toggleRecording()
                }
                .buttonStyle(.borderedProminent)

                if let audioURL = shell.currentSession?.paths.audioURL,
                   FileManager.default.fileExists(atPath: audioURL.path) {
                    Button(playbackManager.isPlaying ? "Stop Audio" : "Play Audio") {
                        playbackManager.toggle(url: audioURL)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Reveal") {
                    shell.revealCurrentSessionInFinder()
                }
                .buttonStyle(.bordered)
            }

            if let session = shell.currentSession {
                Text(session.paths.folderURL.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(.headline)

            Text("Raw transcript")
                .font(.subheadline)
                .foregroundColor(.secondary)

            TextEditor(text: Binding(
                get: { shell.rawTranscript },
                set: { shell.updateRawTranscriptFromEditor($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 110)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("Polished transcript")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if shell.sessionState == .polishing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Polishing... \(formattedDuration(shell.polishElapsedSeconds))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ScrollView {
                Text(polishedBodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 150)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Copy Latest") {
                    shell.copyLatestPolished()
                }
                .buttonStyle(.bordered)

                Button("Retry Polish") {
                    shell.retryPolish()
                }
                .buttonStyle(.bordered)
                .disabled(shell.rawTranscript.isEmpty)
            }
        }
    }

    private var permissionText: String {
        switch shell.permissionState {
        case .authorized:
            return "Microphone permission granted"
        case .denied:
            return "No input: microphone permission denied"
        case .undetermined:
            return "Microphone permission not requested"
        }
    }

    private func openSettings() {
        shell.openSettingsWindow()
    }

    private var polishedBodyText: String {
        if !shell.polishedTranscript.isEmpty {
            return shell.polishedTranscript
        }
        if shell.sessionState == .polishing {
            return "Polishing in progress..."
        }
        return "Polished transcript will appear here."
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

enum AVAudioSessionBridge {
    static var defaultInputName: String {
        AVCaptureDevice.default(for: .audio)?.localizedName ?? "Unknown input"
    }
}
