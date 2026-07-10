import Foundation

struct MultipartFormDataBuilder {
    let boundary: String

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    func writeBody(
        fields: [String: String],
        fileFieldName: String,
        fileURL: URL,
        mimeType: String,
        destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        fileManager.createFile(atPath: destinationURL.path, contents: nil)

        let output = try FileHandle(forWritingTo: destinationURL)
        do {
            for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
                try output.write(contentsOf: Data("\(value)\r\n".utf8))
            }

            let filename = fileURL.lastPathComponent
            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(
                contentsOf: Data(
                    "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n".utf8
                )
            )
            try output.write(contentsOf: Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }

            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try output.close()
        } catch {
            try? output.close()
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }
}
