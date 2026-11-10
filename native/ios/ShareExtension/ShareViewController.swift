import UIKit
import Security
import Social
import CryptoKit
import UniformTypeIdentifiers

/**
 * iOS Share Extension handling fast one-shot clipboard and file sharing (PROTO-DC-V2.0 §14.3, FR-03C).
 * Designed with Swift native URLSession to strictly respect Jetsam RAM quota (< 30 MB peak RAM).
 */
class ShareViewController: SLComposeServiceViewController, URLSessionDelegate {

    static let appGroupId = "group.com.dropclip.shared"
    static let backgroundSessionId = "com.dropclip.share.bg"
    private var expectedServerFingerprint: String?

    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments,
              let provider = itemProviders.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
              }) else {
            finish()
            return
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, _) in
            guard let self = self else { return }
            guard let text = item as? String else {
                self.finish()
                return
            }
            self.sendClipboardToDesktop(text: text) { _ in
                self.finish()
            }
        }
    }

    private func finish() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Sends clipboard text via `POST /api/v1/clipboard` (§9.4) over mTLS 1.3 and calls `completion` once.
    private func sendClipboardToDesktop(text: String, completion: @escaping (Bool) -> Void) {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        guard let host = defaults?.string(forKey: "last_active_desktop_ip"),
              let fp = defaults?.string(forKey: "last_active_desktop_fp") else {
            completion(false)
            return
        }
        let port = defaults?.integer(forKey: "last_active_desktop_port") ?? 53317
        let hlc = defaults?.string(forKey: "last_hlc_header") ?? "0:0:ios-ext"
        expectedServerFingerprint = fp.lowercased()

        guard let url = URL(string: "https://\(host):\(port)/api/v1/clipboard") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(hlc, forHTTPHeaderField: "X-DropClip-HLC")
        request.httpBody = Data(text.utf8)

        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session.dataTask(with: request) { _, response, error in
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 204
            session.finishTasksAndInvalidate()
            completion(ok)
        }.resume()
    }

    /// Streams a large file (up to 4 GB) from disk via Background URLSession (< 30 MB RAM, NFR-R03B).
    func streamFileInBackground(fileURL: URL, transferId: String, itemId: String) -> URLSessionUploadTask? {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        guard let host = defaults?.string(forKey: "last_active_desktop_ip"),
              let fp = defaults?.string(forKey: "last_active_desktop_fp") else {
            return nil
        }
        let port = defaults?.integer(forKey: "last_active_desktop_port") ?? 53317
        expectedServerFingerprint = fp.lowercased()
        guard let url = URL(string: "https://\(host):\(port)/api/v1/file/\(transferId)/\(itemId)") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("0", forHTTPHeaderField: "X-Offset")

        let bgConfig = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionId)
        bgConfig.sharedContainerIdentifier = Self.appGroupId
        bgConfig.tlsMinimumSupportedProtocolVersion = .TLSv13
        let session = URLSession(configuration: bgConfig, delegate: self, delegateQueue: nil)
        let task = session.uploadTask(with: request, fromFile: fileURL)
        task.resume()
        return task
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        if method == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           let certChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
           let leaf = certChain.first {
            let der = SecCertificateCopyData(leaf) as Data
            let digest = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
            if digest == expectedServerFingerprint {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
