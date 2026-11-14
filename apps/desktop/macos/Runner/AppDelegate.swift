import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var activateObserver: NSObjectProtocol?

  /// Returns another non-terminated instance of this app, or nil if this is the
  /// primary instance (skipped under XCTest so test runners do not self-kill).
  static func findExistingInstance() -> NSRunningApplication? {
    let env = ProcessInfo.processInfo.environment
    if env["XCTestConfigurationFilePath"] != nil
      || Bundle.main.bundlePath.hasSuffix(".xctest")
    {
      return nil
    }
    guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
      return nil
    }
    let selfPid = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
      .first { $0.processIdentifier != selfPid && !$0.isTerminated }
  }

  private static var activateNotificationName: NSNotification.Name? {
    guard let bundleId = Bundle.main.bundleIdentifier, !bundleId.isEmpty else {
      return nil
    }
    return NSNotification.Name("\(bundleId).activate")
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let existing = Self.findExistingInstance() {
      if !CommandLine.arguments.contains("--hidden") {
        existing.activate(options: [.activateIgnoringOtherApps])
        if let name = Self.activateNotificationName {
          DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true)
        }
      }
      NSApp.terminate(nil)
      return
    }

    if let name = Self.activateNotificationName {
      activateObserver = DistributedNotificationCenter.default().addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.showMainWindow()
      }
    }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if let observer = activateObserver {
      DistributedNotificationCenter.default().removeObserver(observer)
      activateObserver = nil
    }
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag || !(mainFlutterWindow?.isVisible ?? false) {
      showMainWindow()
    }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    guard let window = mainFlutterWindow else { return }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }
}
