import Cocoa
import FlutterMacOS

/// Serves the PROTO-DC-V2.0 §14.1 clipboard channels on macOS (T1.6).
/// The logic lives in the Flutter-free core (Classes/Core); this class only
/// converts between it and the platform channels.
public class DropClipMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let access = ClipboardAccess(pasteboard: NSPasteboard.general)
    private var poller: ClipboardPoller?
    private var sink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DropClipMacosPlugin()
        let methods = FlutterMethodChannel(
            name: "dropclip/clipboard", binaryMessenger: registrar.messenger)
        registrar.addMethodCallDelegate(instance, channel: methods)
        FlutterEventChannel(
            name: "dropclip/clipboard/events", binaryMessenger: registrar.messenger
        ).setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startPolling()
            result(nil)
        case "stop":
            poller?.stop()
            poller = nil
            result(nil)
        case "read":
            result(access.read().map(Self.encode))
        case "write":
            guard let items = Self.decodeItems(call.arguments) else {
                result(FlutterError(code: "BAD_ARGS", message: "write needs items", details: nil))
                return
            }
            result(["change_token": access.write(items)])
        case "clear":
            access.clear()
            result(nil)
        case "changeToken":
            result(access.changeToken)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        sink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    private func startPolling() {
        guard poller == nil else { return }
        let poller = ClipboardPoller(watcher: ClipboardWatcher(access: access)) {
            [weak self] snapshot in
            self?.sink?(Self.encode(snapshot))
        }
        poller.start()
        self.poller = poller
    }

    /// `ClipSnapshot` as the channel map of §14.1.
    static func encode(_ snapshot: ClipSnapshot) -> [String: Any] {
        [
            "change_token": snapshot.changeToken,
            "is_concealed": snapshot.isConcealed,
            "items": snapshot.items.map {
                ["mime": $0.mime, "data": FlutterStandardTypedData(bytes: $0.data)]
            },
            "ts": snapshot.ts,
        ]
    }

    /// `{items: [{mime, data}]}` of `write`; nil when malformed.
    static func decodeItems(_ arguments: Any?) -> [ClipItem]? {
        guard let map = arguments as? [String: Any],
            let raw = map["items"] as? [[String: Any]]
        else { return nil }
        var items: [ClipItem] = []
        for item in raw {
            guard let mime = item["mime"] as? String,
                let data = item["data"] as? FlutterStandardTypedData
            else { return nil }
            items.append(ClipItem(mime: mime, data: data.data))
        }
        return items
    }
}
