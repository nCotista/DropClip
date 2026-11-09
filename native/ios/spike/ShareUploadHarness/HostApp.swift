import UIKit

@main final class HostApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = HarnessViewController()
        window?.makeKeyAndVisible()
        if ProcessInfo.processInfo.environment["S02_AUTO_PREPARE"] == "1" {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            _ = try? HarnessChecks.prepareFile(in: documents)
        }
        return true
    }
}

final class HarnessViewController: UIViewController {
    private let group = "group.com.dropclip.shared"
    private let endpoint = UITextField()
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        endpoint.placeholder = "https://<Mac LAN IP>:53317/upload"
        endpoint.borderStyle = .roundedRect
        endpoint.autocapitalizationType = .none
        endpoint.keyboardType = .URL
        #if targetEnvironment(simulator)
        endpoint.text = SimulatorUpload.endpoint.absoluteString
        endpoint.isEnabled = false
        #else
        if let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            endpoint.text = try? String(contentsOf: folder.appendingPathComponent("endpoint.txt"))
        }
        #endif
        status.numberOfLines = 0
        status.text = "Start the local HTTPS receiver, then share a 4 GiB file."
        let button = UIButton(type: .system)
        button.setTitle("Create and share 4 GiB", for: .normal)
        button.addTarget(self, action: #selector(share), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [endpoint, button, status])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(showResult),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func showResult() {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let text = try? String(contentsOf: folder.appendingPathComponent("peak-rss-kib.txt")),
              let peak = Int(text) else { return }
        status.text = "Share Extension peak RSS: \(peak / 1024) MiB (\(peak) KiB)"
    }

    @objc private func share() {
        #if !targetEnvironment(simulator)
        guard let url = HarnessChecks.localEndpoint(endpoint.text) else {
            status.text = "A local HTTPS receiver is required."
            return
        }
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            status.text = "App Group unavailable; check signing."
            return
        }
        #endif
        do {
            #if !targetEnvironment(simulator)
            try url.absoluteString.write(to: folder.appendingPathComponent("endpoint.txt"),
                                         atomically: true, encoding: .utf8)
            #endif
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
            guard HarnessChecks.hasSpace(free) else {
                status.text = "At least 16 GiB free storage is required for transfer copies."
                return
            }
            let file = try HarnessChecks.prepareFile(in: directory)
            let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
            present(activity, animated: true)
        } catch { status.text = "Could not prepare 4 GiB file: \(error.localizedDescription)" }
    }
}
