import Foundation

/// Standalone contract checks. Also type-checks against the iOS 15 simulator SDK.
@main struct BackgroundUploadProbeTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    static func main() {
        let config = BackgroundUploadProbe.configuration(identifier: "com.dropclip.spike.test")
        check(config.identifier == "com.dropclip.spike.test", "background session identifier")
        check(config.sharedContainerIdentifier == BackgroundUploadProbe.appGroup, "App Group")
        check(config.tlsMinimumSupportedProtocolVersion == .TLSv13, "TLS 1.3 minimum")

        let url = URL(string: "https://192.168.1.2:53317/api/v1/file/t/i")!
        let request = BackgroundUploadProbe.request(url: url)
        check(request?.httpMethod == "POST", "POST method")
        check(request?.value(forHTTPHeaderField: "X-Offset") == "0", "start offset")
        check(request?.httpBody == nil, "body stays on disk")

        check(BackgroundUploadProbe.request(url: URL(string: "http://192.168.1.2/file")!) == nil,
              "reject plaintext endpoint")

        check(BackgroundUploadProbe.request(url: url, offset: -1) == nil, "reject negative offset")

        let probe = BackgroundUploadProbe()
        let file = URL(fileURLWithPath: "/does-not-exist/dropclip-spike.bin")
        check(probe.upload(file: file, to: url, identifier: "com.dropclip.spike.missing") == nil,
              "reject missing file")
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("dropclip-spike-empty")
        FileManager.default.createFile(atPath: outside.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outside) }
        check(probe.upload(file: outside, to: url, identifier: "com.dropclip.spike.outside") == nil,
              "reject file outside App Group")

        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        probe.urlSession(session, task: task, didCompleteWithError: nil)
        check(probe.completedStatus == nil && probe.completedError == nil,
              "completion records task result")
        BackgroundUploadProbe.discoveryBrowser().cancel()
        print("BackgroundUploadProbe checks passed")
    }
}
