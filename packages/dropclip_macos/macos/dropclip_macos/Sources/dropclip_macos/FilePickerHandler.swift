import Cocoa
import FlutterMacOS

/// Serves `dropclip/file_picker` using `NSOpenPanel` so picking files never
/// invokes `/usr/bin/osascript` or prompts for Finder Automation permissions.
final class FilePickerHandler: NSObject, FlutterPlugin {
    static let shared = FilePickerHandler()
    private var isPresenting = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dropclip/file_picker", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(shared, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "pickFiles" else {
            result(FlutterMethodNotImplemented)
            return
        }
        if Thread.isMainThread {
            presentPanel(result: result)
        } else {
            DispatchQueue.main.async {
                self.presentPanel(result: result)
            }
        }
    }

    private func presentPanel(result: @escaping FlutterResult) {
        guard !isPresenting else {
            result([String]())
            return
        }
        isPresenting = true
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        let finish: (NSApplication.ModalResponse) -> Void = {
            [weak self, weak panel] response in
            self?.isPresenting = false
            guard response == .OK, let panel = panel else {
                result([String]())
                return
            }
            result(FilePickerSupport.normalizeFileURLs(panel.urls))
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
