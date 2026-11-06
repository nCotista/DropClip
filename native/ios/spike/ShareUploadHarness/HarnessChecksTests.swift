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
        print("HarnessChecksTests passed")
    }
}
