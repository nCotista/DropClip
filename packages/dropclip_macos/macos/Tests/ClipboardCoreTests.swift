import AppKit
import XCTest

@testable import DropClipMacCore

/// In-memory pasteboard that counts content reads.
final class FakePasteboard: PasteboardSource {
    private(set) var changeCount = 0
    private(set) var reads = 0
    private var store: [NSPasteboard.PasteboardType: Data] = [:]
    private var order: [NSPasteboard.PasteboardType] = []

    var currentTypes: [NSPasteboard.PasteboardType] { order }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        reads += 1
        return store[type]
    }

    func clearContents() -> Int {
        changeCount += 1
        store = [:]
        order = []
        return changeCount
    }

    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard let data = data else { return false }
        store[type] = data
        order.append(type)
        return true
    }

    /// Another app copies [items].
    func copy(_ items: [(NSPasteboard.PasteboardType, String)]) {
        _ = clearContents()
        for (type, value) in items { _ = setData(Data(value.utf8), forType: type) }
    }
}

final class ClipboardCoreTests: XCTestCase {
    private var pb: FakePasteboard!
    private var access: ClipboardAccess!

    override func setUp() {
        pb = FakePasteboard()
        access = ClipboardAccess(pasteboard: pb, now: { Date(timeIntervalSince1970: 1_757_280_000) })
    }

    func testReadsEveryFormatInReportingOrder() {
        pb.copy([(.tiff, "T"), (.string, "hello"), (.png, "P"), (.URL, "https://x")])
        let snap = access.read()
        XCTAssertEqual(snap?.changeToken, 1)
        XCTAssertEqual(snap?.isConcealed, false)
        XCTAssertEqual(snap?.ts, 1_757_280_000_000)
        XCTAssertEqual(snap?.items.map(\.mime), ["text/plain", "text/uri-list", "image/png", "image/tiff"])
        XCTAssertEqual(snap?.items.first?.data, Data("hello".utf8))
    }

    func testConcealedMarkersAreReportedWithoutReadingContent() {
        for marker in ClipboardFormats.concealed {
            pb.copy([(.string, "hunter2"), (marker, "")])
            let before = pb.reads
            let snap = access.read()
            XCTAssertEqual(snap?.isConcealed, true, marker.rawValue)
            XCTAssertEqual(snap?.items, [], marker.rawValue)
            XCTAssertEqual(pb.reads, before, "read content despite \(marker.rawValue)")
        }
    }

    func testNothingSyncableReadsAsNil() {
        XCTAssertNil(access.read())
        pb.copy([(NSPasteboard.PasteboardType("com.example.private"), "x")])
        XCTAssertNil(access.read())
    }

    func testWatcherReportsEachChangeOnce() {
        let watcher = ClipboardWatcher(access: access)
        XCTAssertNil(watcher.poll())
        pb.copy([(.string, "one")])
        XCTAssertEqual(watcher.poll()?.items.first?.data, Data("one".utf8))
        XCTAssertNil(watcher.poll())
        pb.copy([(.string, "two")])
        XCTAssertEqual(watcher.poll()?.changeToken, 2)
    }

    func testWriteReplacesContentSkipsUnknownAndReturnsToken() {
        pb.copy([(.string, "old")])
        let token = access.write([
            ClipItem(mime: "text/plain", data: Data("new".utf8)),
            ClipItem(mime: "application/x-unknown", data: Data([1])),
            ClipItem(mime: "image/png", data: Data([0x89])),
        ])
        XCTAssertEqual(token, 2)
        XCTAssertEqual(pb.currentTypes, [.string, .png])
        XCTAssertEqual(access.read()?.items.first?.data, Data("new".utf8))
    }

    func testClearEmptiesThePasteboard() {
        pb.copy([(.string, "x")])
        access.clear()
        XCTAssertNil(access.read())
        XCTAssertEqual(access.changeToken, 2)
    }

    /// The real NSPasteboard, on a private pasteboard so the user's
    /// clipboard is untouched.
    func testRealPasteboardRoundTripAndConcealedType() {
        let real = NSPasteboard.withUniqueName()
        defer { real.releaseGlobally() }
        let access = ClipboardAccess(pasteboard: real)
        let token = access.write([ClipItem(mime: "text/plain", data: Data("hi".utf8))])
        XCTAssertEqual(access.changeToken, token)
        XCTAssertEqual(access.read()?.items, [ClipItem(mime: "text/plain", data: Data("hi".utf8))])

        real.clearContents()
        real.setString("secret", forType: .string)
        real.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        XCTAssertEqual(access.read()?.isConcealed, true)
        XCTAssertEqual(access.read()?.items, [])
    }
}
