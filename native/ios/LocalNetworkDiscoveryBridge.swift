import Foundation
import Network
import UIKit

/// Native iOS Bonjour Discovery & Local Network Permission Bridge (T3.1, PROTO §3 & §14.3).
///
/// Uses `NWBrowser` with `_dropclip._tcp` declared in `Info.plist -> NSBonjourServices`
/// so the app does NOT require the restricted `com.apple.developer.networking.multicast` entitlement.
@available(iOS 15.0, *)
final class LocalNetworkDiscoveryBridge {

    static let serviceType = "_dropclip._tcp"
    static let policyDeniedErrorCode = -65570 // kDNSServiceErr_PolicyDenied

    enum PermissionState: String {
        case notDetermined = "not_determined"
        case granted = "granted"
        case denied = "denied"
    }

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.dropclip.ios.nwbrowser")
    var onPermissionStateChanged: ((PermissionState) -> Void)?
    var onPeersUpdated: (([[String: String]]) -> Void)?

    /// Starts `NWBrowser` after the user acknowledges the Pre-Permission Explainer.
    func startBrowsing() {
        stopBrowsing()
        let params = NWParameters()
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: Self.serviceType,
            domain: "local."
        )
        let nwBrowser = NWBrowser(for: descriptor, using: params)

        nwBrowser.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.onPermissionStateChanged?(.granted)
            case .waiting(let error), .failed(let error):
                if case .dns(let dnsError) = error, Int(dnsError) == Self.policyDeniedErrorCode {
                    self.onPermissionStateChanged?(.denied)
                }
            default:
                break
            }
        }

        nwBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            var records: [[String: String]] = []
            for result in results {
                if case .bonjour(let txtRecord) = result.metadata {
                    records.append(txtRecord.dictionary)
                }
            }
            self.onPeersUpdated?(records)
        }

        self.browser = nwBrowser
        nwBrowser.start(queue: queue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    /// Deep-links the user to iOS Settings when Local Network permission was denied (T3.1 AC #2).
    func openAppSettings(completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString),
                  UIApplication.shared.canOpenURL(url) else {
                completion?(false)
                return
            }
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }
}
