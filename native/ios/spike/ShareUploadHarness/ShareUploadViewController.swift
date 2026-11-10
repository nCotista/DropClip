import Social
import UIKit
import UniformTypeIdentifiers
import Darwin

/// Disposable S0.2 extension: copies a shared file to the App Group and enqueues a file upload.
final class ShareUploadViewController: SLComposeServiceViewController {
    private let group = BackgroundUploadProbe.appGroup
    private var probe: BackgroundUploadProbe?

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let value = try? String(contentsOf: container.appendingPathComponent("endpoint.txt")),
              let endpoint = HarnessChecks.localEndpoint(value),
              let items = extensionContext?.inputItems as? [NSExtensionItem],
              let provider = items.flatMap({ $0.attachments ?? [] }).first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
              }) else {
            cancel("Missing App Group, HTTPS endpoint, or file")
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { [weak self] source, error in
            guard let self = self, let source = source, error == nil else {
                self?.cancel("File provider did not supply a file")
                return
            }
            do {
                let staged = container.appendingPathComponent(UUID().uuidString)
                try FileManager.default.copyItem(at: source, to: staged)
                let probe = BackgroundUploadProbe()
                guard probe.upload(file: staged, to: endpoint,
                                   identifier: "com.dropclip.spike.upload.\(UUID().uuidString)") != nil else {
                    self.cancel("Background upload could not be enqueued")
                    return
                }
                self.probe = probe
                var usage = rusage()
                if getrusage(RUSAGE_SELF, &usage) == 0 {
                    try? String(usage.ru_maxrss).write(
                        to: container.appendingPathComponent("peak-rss-kib.txt"),
                        atomically: true, encoding: .utf8)
                }
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } catch { self.cancel("Could not stage file in App Group: \(error.localizedDescription)") }
        }
    }

    private func cancel(_ reason: String) {
        let error = NSError(domain: "DropClipS02", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: reason])
        extensionContext?.cancelRequest(withError: error)
    }
}
