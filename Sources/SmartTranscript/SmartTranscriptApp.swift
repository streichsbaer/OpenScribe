import SwiftUI

@main
struct SmartTranscriptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Keep a hidden scene to satisfy SwiftUI App requirements.
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
}
