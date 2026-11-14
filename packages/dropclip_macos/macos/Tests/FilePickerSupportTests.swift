import Foundation
import XCTest

@testable import DropClipMacCore

final class FilePickerSupportTests: XCTestCase {
    func testNormalizesMultipleFileURLsPreservingOrder() {
        let urls = [
            URL(fileURLWithPath: "/Users/alice/report.pdf"),
            URL(fileURLWithPath: "/Users/alice/photo.png"),
        ]
        XCTAssertEqual(
            FilePickerSupport.normalizeFileURLs(urls),
            ["/Users/alice/report.pdf", "/Users/alice/photo.png"]
        )
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(FilePickerSupport.normalizeFileURLs([]), [])
    }

    func testDropsNonFileURLsAndEmptyFileURL() {
        var urls: [URL] = []
        if let web = URL(string: "https://example.com/a.txt") { urls.append(web) }
        if let mail = URL(string: "mailto:user@example.com") { urls.append(mail) }
        if let emptyFile = URL(string: "file://") { urls.append(emptyFile) }
        urls.append(URL(fileURLWithPath: "/tmp/valid.txt"))

        XCTAssertEqual(
            FilePickerSupport.normalizeFileURLs(urls),
            ["/tmp/valid.txt"]
        )
    }

    func testDeduplicatesEquivalentStandardizedPaths() {
        let urls = [
            URL(fileURLWithPath: "/tmp/file.txt"),
            URL(fileURLWithPath: "/tmp/sub/../file.txt"),
            URL(fileURLWithPath: "/tmp/file.txt"),
            URL(fileURLWithPath: "/tmp/other.txt"),
        ]
        XCTAssertEqual(
            FilePickerSupport.normalizeFileURLs(urls),
            ["/tmp/file.txt", "/tmp/other.txt"]
        )
    }
}
