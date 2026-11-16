import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Free space for received files, so the app can refuse an offer that
    // would not fit instead of filling the phone.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DropClipStorage") {
      let channel = FlutterMethodChannel(
        name: "dropclip/storage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "freeBytes" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values?.volumeAvailableCapacityForImportantUsage {
          result(NSNumber(value: free))
        } else {
          result(nil)
        }
      }
    }
  }
}
