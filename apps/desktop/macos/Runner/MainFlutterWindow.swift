import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: false)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // --hidden (LaunchAgent login start) keeps the window hidden until opened
    // from the tray; normal launch shows it immediately unless a primary
    // instance is already running.
    if !CommandLine.arguments.contains("--hidden")
      && AppDelegate.findExistingInstance() == nil
    {
      self.makeKeyAndOrderFront(nil)
    }
  }
}
