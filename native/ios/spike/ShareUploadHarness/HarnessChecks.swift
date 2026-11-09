import Foundation

enum HarnessChecks {
    static let byteCount: UInt64 = 4 * 1024 * 1024 * 1024
    static let requiredFreeBytes: Int64 = 16 * 1024 * 1024 * 1024

    static func hasSpace(_ available: Int64?) -> Bool {
        guard let available = available else { return false }
        return available >= requiredFreeBytes
    }

    static func localEndpoint(_ text: String?) -> URL? {
        guard let text = text, let url = URL(string: text), url.scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        let privateIPv4 = parts.count == 4 && (parts[0] == 10 ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168) ||
            (parts[0] == 169 && parts[1] == 254))
        guard privateIPv4 || host.hasSuffix(".local") else { return nil }
        return url
    }

    static func prepareFile(in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent("dropclip-spike-4gib.bin")
        if !FileManager.default.fileExists(atPath: file.path) {
            guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: byteCount)
        return file
    }
}

/// Simulator-only transport check. Foreground session avoids App Group provisioning.
enum SimulatorUpload {
    static let endpoint = URL(string: "https://127.0.0.1:53317/upload")!

    static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        return config
    }

    static func request(_ endpoint: URL, file: URL) -> URLRequest? {
        guard endpoint.scheme == "https", endpoint.host == "127.0.0.1",
              endpoint.port == 53317, endpoint.path == "/upload",
              file.isFileURL, FileManager.default.fileExists(atPath: file.path) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return request
    }
}
