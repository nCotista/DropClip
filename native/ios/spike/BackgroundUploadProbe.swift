import Foundation
import Network

/// Small, isolated probe for ADR-007. Run from a Share Extension on a device.
/// A file URL in the App Group container is required for background uploads.
final class BackgroundUploadProbe: NSObject, URLSessionTaskDelegate {
    static let appGroup = "group.com.dropclip.shared"

    private(set) var session: URLSession?
    private(set) var completedStatus: Int?
    private(set) var completedError: Error?

    static func configuration(identifier: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sharedContainerIdentifier = appGroup
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        return config
    }

    static func discoveryBrowser() -> NWBrowser {
        NWBrowser(for: .bonjour(type: "_dropclip._tcp", domain: nil), using: .tcp)
    }

    static func request(url: URL, offset: Int64 = 0) -> URLRequest? {
        guard url.scheme == "https", offset >= 0 else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(offset), forHTTPHeaderField: "X-Offset")
        return request
    }

    func upload(file: URL, to url: URL, identifier: String) -> URLSessionUploadTask? {
        guard file.isFileURL,
              FileManager.default.fileExists(atPath: file.path),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup),
              file.standardizedFileURL.path.hasPrefix(container.standardizedFileURL.path + "/"),
              let request = Self.request(url: url) else { return nil }

        let session = URLSession(configuration: Self.configuration(identifier: identifier),
                                 delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.uploadTask(with: request, fromFile: file)
        task.resume()
        return task
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        completedStatus = (task.response as? HTTPURLResponse)?.statusCode
        completedError = error
        session.finishTasksAndInvalidate()
    }
}
