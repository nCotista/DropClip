import AppKit
import XCTest

@testable import DropClipMacCore

final class ClipboardPollerTests: XCTestCase {
    func testIntervalsFollowTheSpec() {
        let i = ClipboardPoller.interval
        XCTAssertEqual(i(0, false), 0.2)
        XCTAssertEqual(i(29.9, false), 0.2)
        XCTAssertEqual(i(30, false), 1.0)
        XCTAssertEqual(i(3600, false), 1.0)
        XCTAssertEqual(i(0, true), 2.0, "locked wins over recent input")
    }

    func testSystemIdleTimeIsReadable() {
        XCTAssertGreaterThanOrEqual(ClipboardPoller.systemSecondsSinceInput(), 0)
    }

    func testPollerReportsChangesUntilStopped() {
        let pb = FakePasteboard()
        var seen: [Int] = []
        let poller = ClipboardPoller(
            watcher: ClipboardWatcher(access: ClipboardAccess(pasteboard: pb)),
            secondsSinceInput: { 0 },  // active: 200 ms
            onChange: { seen.append($0.changeToken) })

        poller.start()
        poller.start()  // twice is harmless
        pb.copy([(.string, "a")])
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(seen, [1])

        poller.stop()
        XCTAssertFalse(poller.isRunning)
        pb.copy([(.string, "b")])
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(seen, [1])
    }

    func testLockedScreenSlowsPolling() {
        var idle: TimeInterval = 0
        let poller = ClipboardPoller(
            watcher: ClipboardWatcher(access: ClipboardAccess(pasteboard: FakePasteboard())),
            secondsSinceInput: { idle },
            onChange: { _ in })
        XCTAssertEqual(poller.currentInterval, 0.2)
        idle = 45
        XCTAssertEqual(poller.currentInterval, 1.0)
        poller.screenLocked = true
        XCTAssertEqual(poller.currentInterval, 2.0)
    }
}
