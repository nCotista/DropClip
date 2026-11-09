import Social
import UIKit
import UniformTypeIdentifiers
import Darwin

/// Disposable S0.2 extension: copies a shared file to the App Group and enqueues a file upload.
final class ShareUploadViewController: SLComposeServiceViewController {
    private let group = BackgroundUploadProbe.appGroup
    private var probe: BackgroundUploadProbe?
    private var simulatorSession: URLSession?

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        #if targetEnvironment(simulator)
        let container = FileManager.default.temporaryDirectory
        let endpoint = SimulatorUpload.endpoint
        var baseline = rusage()
        if getrusage(RUSAGE_SELF, &baseline) == 0 {
            NSLog("S02_SIM_BEGIN baseline_peak_rss_bytes=%ld", baseline.ru_maxrss)
        }
        #else
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let value = try? String(contentsOf: container.appendingPathComponent("endpoint.txt")),
              let endpoint = HarnessChecks.localEndpoint(value) else {
            cancel("Missing App Group or HTTPS endpoint")
            return
        }
        #endif
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let provider = items.flatMap({ $0.attachments ?? [] }).first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.data.identifier)
              }) else {
            cancel("Missing shared file")
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
                #if targetEnvironment(simulator)
                guard let request = SimulatorUpload.request(endpoint, file: staged) else {
                    self.cancel("Invalid simulator upload")
                    return
                }
                let session = URLSession(configuration: SimulatorUpload.configuration())
                self.simulatorSession = session
                let startedAt = Date()
                session.uploadTask(with: request, fromFile: staged) { _, response, error in
                    var usage = rusage()
                    let peak = getrusage(RUSAGE_SELF, &usage) == 0 ? usage.ru_maxrss : -1
                    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                    NSLog("S02_SIM_UPLOAD status=%ld peak_rss_bytes=%ld duration_s=%.2f error=%@",
                          status, peak, Date().timeIntervalSince(startedAt),
                          error == nil ? "none" : "transport")
                    try? FileManager.default.removeItem(at: staged)
                    session.finishTasksAndInvalidate()
                    DispatchQueue.main.async {
                        if error == nil && status == 200 {
                            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        } else {
                            self.cancel("Simulator upload failed")
                        }
                    }
                }.resume()
                #else
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
                #endif
            } catch { self.cancel("Could not stage file in App Group: \(error.localizedDescription)") }
        }
    }

    private func cancel(_ reason: String) {
        let error = NSError(domain: "DropClipS02", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: reason])
        extensionContext?.cancelRequest(withError: error)
    }
}
