@preconcurrency import AVFoundation
import Foundation

protocol MicrophoneDeviceCatalogProtocol: AnyObject {
    var onSnapshotChange: ((MicrophoneDeviceSnapshot) -> Void)? { get set }
    func currentSnapshot() -> MicrophoneDeviceSnapshot
}

final class MicrophoneDeviceCatalog: NSObject, MicrophoneDeviceCatalogProtocol {
    var onSnapshotChange: ((MicrophoneDeviceSnapshot) -> Void)?

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        super.init()
        registerForDeviceChanges()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func currentSnapshot() -> MicrophoneDeviceSnapshot {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        let devices = discoverySession.devices
            .map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        let systemDefault = AVCaptureDevice.default(for: .audio)
        return MicrophoneDeviceSnapshot(
            devices: devices,
            systemDefaultDeviceID: systemDefault?.uniqueID,
            systemDefaultDeviceName: systemDefault?.localizedName
        )
    }

    private func registerForDeviceChanges() {
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: AVCaptureDevice.wasConnectedNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleDeviceChange),
            name: AVCaptureDevice.wasDisconnectedNotification,
            object: nil
        )
    }

    @objc
    private func handleDeviceChange(_ notification: Notification) {
        publishSnapshot()
    }

    private func publishSnapshot() {
        onSnapshotChange?(currentSnapshot())
    }
}
