import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private enum MicIconState {
        case idle
        case working
        case paused
        case noAudio
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let shell: AppShell
    private let settingsWindowController: SettingsWindowController
    private var cancellables = Set<AnyCancellable>()
    private var blinkTimer: Timer?
    private var blinkPhase = false
    private var iconState: MicIconState = .idle
    private var currentMeterLevel: Float = 0
    private var smoothedMeterLevel: Float = 0
    private var currentSessionState: SessionState = .idle
    private var currentPermissionState: MicrophonePermissionState = .undetermined
    private var lastActiveSignalAt: Date?
    private var isSpeechActive = false
    private var noiseFloor: Float = 0.005
    private var speechOnThreshold: Float = 0.020
    private var speechOffThreshold: Float = 0.012

    private let smoothingAlpha: Float = 0.22
    private let noiseFloorAlpha: Float = 0.08
    private let minNoiseFloor: Float = 0.005
    private let maxNoiseFloor: Float = 0.060
    private let speechOnFloor: Float = 0.020
    private let speechOffFloor: Float = 0.012
    private let speechOnNoiseMultiplier: Float = 2.2
    private let speechOffNoiseMultiplier: Float = 1.5
    private let noAudioTimeoutSeconds: TimeInterval = 1.4

    init(shell: AppShell) {
        self.shell = shell
        self.settingsWindowController = SettingsWindowController(shell: shell)
        super.init()
        shell.openSettingsWindowHandler = { [weak self] in
            self?.openSettings()
        }
        configureStatusItem()
        configurePopover()
        bindShellState()
        startBlinkTimer()
        updateIconAppearance()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Settings", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit SmartTranscript", action: #selector(quitApp), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }

        togglePopover(sender)
    }

    @objc private func openSettings() {
        settingsWindowController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "SmartTranscript") == nil {
            button.title = "ST"
        } else {
            setStatusIcon(symbolName: "mic.circle", tintColor: nil)
        }

        button.imagePosition = .imageOnly
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 520, height: 760)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(shell))
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func bindShellState() {
        shell.$meterLevel
            .receive(on: RunLoop.main)
            .sink { [weak self] level in
                guard let self else { return }
                currentMeterLevel = level
                smoothedMeterLevel = (smoothedMeterLevel == 0)
                    ? level
                    : ((1 - smoothingAlpha) * smoothedMeterLevel + smoothingAlpha * level)

                if currentSessionState == .recording {
                    updateNoiseFloor(using: smoothedMeterLevel)

                    if isSpeechActive {
                        if smoothedMeterLevel < speechOffThreshold {
                            isSpeechActive = false
                        }
                    } else if smoothedMeterLevel > speechOnThreshold {
                        isSpeechActive = true
                    }

                    if isSpeechActive {
                        lastActiveSignalAt = Date()
                    }
                }
                reevaluateMicIconState()
            }
            .store(in: &cancellables)

        shell.$sessionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if currentSessionState != .recording, state == .recording {
                    lastActiveSignalAt = Date()
                    smoothedMeterLevel = 0
                    isSpeechActive = false
                    noiseFloor = minNoiseFloor
                    speechOnThreshold = speechOnFloor
                    speechOffThreshold = speechOffFloor
                } else if state != .recording {
                    lastActiveSignalAt = nil
                    smoothedMeterLevel = 0
                    isSpeechActive = false
                    noiseFloor = minNoiseFloor
                    speechOnThreshold = speechOnFloor
                    speechOffThreshold = speechOffFloor
                }
                currentSessionState = state
                reevaluateMicIconState()
            }
            .store(in: &cancellables)

        shell.$permissionState
            .receive(on: RunLoop.main)
            .sink { [weak self] permission in
                guard let self else { return }
                currentPermissionState = permission
                reevaluateMicIconState()
            }
            .store(in: &cancellables)
    }

    private func startBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = Timer(timeInterval: 0.45, target: self, selector: #selector(handleBlinkTimerTick), userInfo: nil, repeats: true)
        if let blinkTimer {
            RunLoop.main.add(blinkTimer, forMode: .common)
        }
    }

    @objc private func handleBlinkTimerTick() {
        blinkPhase.toggle()
        reevaluateMicIconState()
    }

    private func reevaluateMicIconState() {
        var silenceDuration: TimeInterval = 0

        if currentSessionState != .recording {
            iconState = .idle
            updateIconAppearance()
            publishDebug(silenceDuration: silenceDuration)
            return
        }

        if currentPermissionState != .authorized {
            iconState = .noAudio
            updateIconAppearance()
            publishDebug(silenceDuration: silenceDuration)
            return
        }

        if isSpeechActive {
            iconState = .working
            updateIconAppearance()
            publishDebug(silenceDuration: silenceDuration)
            return
        }

        silenceDuration = Date().timeIntervalSince(lastActiveSignalAt ?? .distantPast)
        iconState = silenceDuration >= noAudioTimeoutSeconds ? .noAudio : .paused
        updateIconAppearance()
        publishDebug(silenceDuration: silenceDuration)
    }

    private func updateIconAppearance() {
        switch iconState {
        case .idle:
            setStatusIcon(symbolName: "mic.circle", tintColor: nil)
        case .working:
            setStatusIcon(
                symbolName: blinkPhase ? "waveform.circle.fill" : "waveform.circle",
                tintColor: NSColor.systemGreen
            )
        case .paused:
            setStatusIcon(
                symbolName: blinkPhase ? "pause.circle" : "waveform.circle",
                tintColor: blinkPhase ? NSColor.systemGreen : NSColor.systemGray
            )
        case .noAudio:
            setStatusIcon(
                symbolName: blinkPhase ? "mic.slash.circle.fill" : "mic.slash.circle",
                tintColor: NSColor.systemRed
            )
        }
    }

    private func setStatusIcon(symbolName: String, tintColor: NSColor?) {
        guard let button = statusItem.button,
              let image = symbolImage(named: symbolName) else {
            return
        }

        let baseConfig = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
        var configuredImage = image.withSymbolConfiguration(baseConfig) ?? image

        if let tintColor {
            let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [tintColor])
            configuredImage = configuredImage.withSymbolConfiguration(paletteConfig) ?? configuredImage
            configuredImage.isTemplate = false
            button.contentTintColor = tintColor
        } else {
            configuredImage.isTemplate = true
            button.contentTintColor = nil
        }

        button.image = configuredImage
        button.title = ""
    }

    private func symbolImage(named symbolName: String) -> NSImage? {
        let candidates = [symbolName, "mic.circle.fill", "mic.circle", "waveform.circle.fill"]
        for candidate in candidates {
            if let image = NSImage(systemSymbolName: candidate, accessibilityDescription: "SmartTranscript") {
                return image
            }
        }
        return nil
    }

    private func updateNoiseFloor(using level: Float) {
        let boundedLevel = min(level, max(noiseFloor, minNoiseFloor) * 1.8)
        noiseFloor = ((1 - noiseFloorAlpha) * noiseFloor) + (noiseFloorAlpha * max(0, boundedLevel))
        noiseFloor = min(max(noiseFloor, minNoiseFloor), maxNoiseFloor)

        speechOnThreshold = max(speechOnFloor, noiseFloor * speechOnNoiseMultiplier)
        speechOffThreshold = max(speechOffFloor, noiseFloor * speechOffNoiseMultiplier)
    }

    private func publishDebug(silenceDuration: TimeInterval) {
        shell.menubarIconDebug = String(
            format: "icon=%@ raw=%.3f smooth=%.3f floor=%.3f on=%.3f off=%.3f speech=%@ silence=%.1fs",
            iconStateLabel(iconState),
            currentMeterLevel,
            smoothedMeterLevel,
            noiseFloor,
            speechOnThreshold,
            speechOffThreshold,
            isSpeechActive ? "yes" : "no",
            max(0, silenceDuration)
        )
    }

    private func iconStateLabel(_ state: MicIconState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .working:
            return "working"
        case .paused:
            return "paused"
        case .noAudio:
            return "no-audio"
        }
    }
}
