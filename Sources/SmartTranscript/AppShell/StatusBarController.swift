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

    private let smoothingAlpha: Float = 0.22
    private let speechOnThreshold: Float = 0.020
    private let speechOffThreshold: Float = 0.012
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

        if NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "SmartTranscript") == nil {
            button.title = "ST"
        } else {
            setStatusIcon(tintColor: nil)
        }

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
                } else if state != .recording {
                    lastActiveSignalAt = nil
                    smoothedMeterLevel = 0
                    isSpeechActive = false
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
            setStatusIcon(tintColor: nil)
        case .working:
            setStatusIcon(tintColor: blinkPhase ? NSColor.systemGreen : NSColor.systemGreen.withAlphaComponent(0.35))
        case .paused:
            setStatusIcon(tintColor: blinkPhase ? NSColor.systemGreen : NSColor.systemGray)
        case .noAudio:
            setStatusIcon(tintColor: NSColor.systemRed)
        }
    }

    private func setStatusIcon(tintColor: NSColor?) {
        guard let button = statusItem.button,
              let image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "SmartTranscript") else {
            return
        }

        image.isTemplate = tintColor == nil
        button.image = image
        button.contentTintColor = tintColor
    }

    private func publishDebug(silenceDuration: TimeInterval) {
        shell.menubarIconDebug = String(
            format: "icon=%@ raw=%.3f smooth=%.3f speech=%@ silence=%.1fs",
            iconStateLabel(iconState),
            currentMeterLevel,
            smoothedMeterLevel,
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
