import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let shell = AppShell()

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(shell: shell)

        if shell.settings.transcriptionProviderID == "whispercpp" {
            shell.downloadDefaultModelIfNeeded()
        }
    }
}
