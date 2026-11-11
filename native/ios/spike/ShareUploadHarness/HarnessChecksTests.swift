import Foundation

@main enum HarnessChecksTests {
    static func main() throws {
        assert(HarnessChecks.localEndpoint("https://192.168.1.5:53317/upload") != nil)
        assert(HarnessChecks.localEndpoint("https://dropclip.local:53317/upload") != nil)
        assert(HarnessChecks.localEndpoint("http://192.168.1.5/upload") == nil)
        assert(HarnessChecks.localEndpoint("https://8.8.8.8/upload") == nil)
        assert(HarnessChecks.localEndpoint("https:///upload") == nil)
        assert(HarnessChecks.hasSpace(HarnessChecks.requiredFreeBytes))
        assert(!HarnessChecks.hasSpace(HarnessChecks.requiredFreeBytes - 1))
        assert(!HarnessChecks.hasSpace(nil))
        assert(HarnessChecks.peakRSSFilename == "peak-rss-bytes.txt")
        assert(HarnessChecks.peakRSSDescription("196820992") ==
               "Share Extension peak RSS: 187.70 MiB (196820992 bytes)")
        assert(HarnessChecks.peakRSSDescription(" 1048576\n") ==
               "Share Extension peak RSS: 1.00 MiB (1048576 bytes)")
        assert(HarnessChecks.peakRSSDescription("0") == "Share Extension peak RSS: 0.00 MiB (0 bytes)")
        assert(HarnessChecks.peakRSSDescription("-1") == nil)
        assert(HarnessChecks.peakRSSDescription("not-a-number") == nil)
        assert(HarnessChecks.peakRSSDescription(nil) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try HarnessChecks.prepareFile(in: directory)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64
        assert(size == HarnessChecks.byteCount)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 5)
        try handle.close()
        _ = try HarnessChecks.prepareFile(in: directory)
        let corrected = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? UInt64
        assert(corrected == HarnessChecks.byteCount)

        let request = SimulatorUpload.request(SimulatorUpload.endpoint, file: file)
        assert(request?.httpMethod == "POST")
        assert(request?.httpBody == nil)
        assert(request?.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        assert(SimulatorUpload.configuration().tlsMinimumSupportedProtocolVersion == .TLSv13)
        assert(SimulatorUpload.request(URL(string: "http://127.0.0.1:53317/upload")!, file: file) == nil)
        assert(SimulatorUpload.request(URL(string: "https://192.168.1.5:53317/upload")!, file: file) == nil)
        assert(SimulatorUpload.request(URL(string: "https://127.0.0.1:53318/upload")!, file: file) == nil)
        assert(SimulatorUpload.request(URL(string: "https://127.0.0.1:53317/other")!, file: file) == nil)
        assert(SimulatorUpload.request(SimulatorUpload.endpoint,
                                       file: directory.appendingPathComponent("missing")) == nil)
        print("HarnessChecksTests passed")
    }
}
