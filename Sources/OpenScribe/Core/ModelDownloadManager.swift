import CryptoKit
import Foundation

final class ModelDownloadManager: ObservableObject {
    @Published var activeDownloadModelID: String?
    @Published var progress: Double = 0

    let catalog: [ModelAsset]

    private let modelsDirectory: URL
    private let fileManager: FileManager

    init(layout: DirectoryLayout, fileManager: FileManager = .default) {
        self.modelsDirectory = layout.models
        self.fileManager = fileManager
        self.catalog = [
            ModelAsset(
                id: "tiny",
                displayName: "tiny",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin?download=true")!,
                expectedSizeBytes: 77_691_713,
                sha256: nil
            ),
            ModelAsset(
                id: "base",
                displayName: "base",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin?download=true")!,
                expectedSizeBytes: 147_951_465,
                sha256: nil
            ),
            ModelAsset(
                id: "small",
                displayName: "small",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true")!,
                expectedSizeBytes: 487_601_967,
                sha256: nil
            ),
            ModelAsset(
                id: "medium",
                displayName: "medium",
                downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin?download=true")!,
                expectedSizeBytes: 1_533_763_059,
                sha256: nil
            )
        ]
    }

    func localPath(for modelID: String) -> URL {
        modelsDirectory.appendingPathComponent("ggml-\(modelID).bin")
    }

    func isInstalled(modelID: String) -> Bool {
        fileManager.fileExists(atPath: localPath(for: modelID).path)
    }

    func installedModels() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }
            .map { $0.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "") }
            .sorted()
    }

    func remove(modelID: String) throws {
        let url = localPath(for: modelID)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func installedSizeBytes(modelID: String) -> Int64 {
        let url = localPath(for: modelID)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return 0
        }
        return Int64(size)
    }

    func totalInstalledSizeBytes() -> Int64 {
        installedModels().reduce(0) { partial, modelID in
            partial + installedSizeBytes(modelID: modelID)
        }
    }

    @MainActor
    func ensureInstalled(modelID: String) async throws -> URL {
        let destination = localPath(for: modelID)
        if fileManager.fileExists(atPath: destination.path) {
            return destination
        }

        guard let asset = catalog.first(where: { $0.id == modelID }) else {
            throw ProviderError.missingModel(modelID)
        }

        activeDownloadModelID = modelID
        progress = 0
        defer {
            activeDownloadModelID = nil
            progress = 0
        }

        let temp = destination.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).download")
        let request = URLRequest(
            url: asset.downloadURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 600
        )

        let progressDelegate = DownloadProgressDelegate { [weak self] value in
            Task { @MainActor [weak self] in
                self?.progress = value
            }
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 3_600
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let (downloadedURL, _) = try await session.download(for: request, delegate: progressDelegate)
        if fileManager.fileExists(atPath: temp.path) {
            try fileManager.removeItem(at: temp)
        }
        try fileManager.moveItem(at: downloadedURL, to: temp)
        progress = 1

        try validate(asset: asset, file: temp)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temp, to: destination)
        return destination
    }

    private func validate(asset: ModelAsset, file: URL) throws {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize {
            let expected = Int(asset.expectedSizeBytes)
            if expected > 0 && abs(size - expected) > 4_096 {
                throw ProviderError.processFailed("Downloaded model size mismatch for \(asset.id).")
            }
        }

        if let expectedHash = asset.sha256 {
            let data = try Data(contentsOf: file)
            let digest = SHA256.hash(data: data)
            let hash = digest.compactMap { String(format: "%02x", $0) }.joined()
            if hash.lowercased() != expectedHash.lowercased() {
                throw ProviderError.processFailed("Downloaded model hash mismatch for \(asset.id).")
            }
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        let value = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        onProgress(value)
    }
}
