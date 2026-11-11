# S0.2 Share Extension device probe

This Xcode project is a disposable test host and native Share Extension. It creates a sparse 4 GiB file without loading it into RAM, shares it through iOS, stages it in `group.com.dropclip.shared`, and enqueues a file-backed background `URLSession` upload. Darwin reports `getrusage.ru_maxrss` in [bytes](https://github.com/apple/darwin-xnu/blob/main/bsd/man/man2/getrusage.2); the physical path stores an enqueue-time high-water snapshot in `peak-rss-bytes.txt` and the host displays MiB plus raw bytes. That snapshot has not been validated as a full-transfer peak. The LAN receiver reads 1 MiB at a time and verifies all 4 GiB plus SHA-256.

Simulator build: `xcodebuild -project ShareUploadHarness.xcodeproj -scheme ShareUploadHarness -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`. Run host checks with `swiftc HarnessChecks.swift HarnessChecksTests.swift -o /tmp/s02-checks && /tmp/s02-checks`, and receiver checks with `python3 receiver_test.py`.

For a simulator file smoke check, launch the host with `SIMCTL_CHILD_S02_AUTO_PREPARE=1 xcrun simctl launch <simulator-id> com.dropclip.s02upload`; its Documents file should have logical size `4294967296` bytes and consume no data blocks until copied.

## Simulator-only upload without App Group

The simulator build uses a foreground, file-backed `URLSession` from the Share Extension to `https://127.0.0.1:53317/upload`. It does not use the App Group or test background `URLSession` persistence. Start `receiver.py` bound to `127.0.0.1` with a local TLS 1.3 P-256 certificate trusted by the simulator (`xcrun simctl keychain booted add-root-cert <root-cert>`). Build and install the harness with `CODE_SIGNING_ALLOWED=NO`, open it, tap **Create and share 4 GiB**, select **DropClip S0.2 Upload**, and tap **Post**. The receiver must report `received=4294967296` and `valid=True`; find `S02_SIM_UPLOAD` in the simulator log for HTTP status, duration, and extension `peak_rss_bytes` (Darwin simulator `ru_maxrss` is in bytes). This is a Simulator measurement only and cannot satisfy the physical-device or background-session acceptance criteria.

## Run on iPhone

1. In Apple Developer, register `group.com.dropclip.shared` and enable it for **both** bundle IDs `com.dropclip.s02upload` and `com.dropclip.s02upload.Share`. Select that Team for both Xcode targets. A Personal Team profile without this entitlement fails signing.
2. Build and install the `ShareUploadHarness` scheme on the iPhone. Keep the phone on the same LAN as the Mac and ensure at least 16 GiB of free device storage for file-provider and `URLSession` copies; the host app checks this before sharing.
3. Start `receiver.py <Mac LAN IP> <TLS certificate PEM> <encrypted TLS private key PEM>`. Use a trusted ECDSA P-256 certificate with the LAN host/IP in its SAN; do not disable certificate validation. Enter the encrypted key password at the prompt. The receiver accepts only `/upload` and a 4 GiB zero-filled body.
4. In the host app enter `https://<Mac LAN IP>:53317/upload`, tap **Create and share 4 GiB**, select **DropClip S0.2 Upload**, then tap **Post**. The file is also visible in Files under the app's Documents if the share sheet omits the extension.
5. Confirm `valid=True` and `received=4294967296` in the receiver output. Return to the host app to read **Share Extension peak RSS**. NFR-R03B requires the successful transfer's measured peak to be strictly below **30 MB (30,000,000 bytes)**; the enqueue-time snapshot alone does not establish this. Record device/OS, transfer duration, and any jetsam report in the tracker worklog.

`BackgroundUploadProbe.swift` is compiled into the extension. The probe uses App Group storage and TLS 1.3. This harness measures the S0.2 platform constraint; the production mTLS identity and protocol endpoint belong to T3.2.
