enum ClipKind { text, link, image }

/// One entry of the in-memory clipboard history (FR-04, SF-03).
class ClipItem {
  final ClipKind kind;

  /// Text or URL; for images a label such as `name.png · 1.8 MB`.
  final String preview;
  final String sourceDevice;
  final String age;

  const ClipItem(this.kind, this.preview,
      {required this.sourceDevice, required this.age});
}

/// Snapshot shown by the shell. Filled from the engine once T1.9
/// (clipboard sync) and T1.11 (transfers) land; demo values until then.
class ShellStatus {
  final String networkName;
  final String address;
  final int verifiedDevices;
  final int activeTransfers;
  final int deviceCount;

  /// Newest first, at most 20, memory only.
  final List<ClipItem> clips;

  /// Clips dropped because of a password-manager marker (NFR-S04).
  final int suppressedClips;

  const ShellStatus({
    required this.networkName,
    required this.address,
    required this.verifiedDevices,
    required this.activeTransfers,
    required this.deviceCount,
    this.clips = const [],
    this.suppressedClips = 0,
  });

  int get clipCount => clips.length;
}

const demoShellStatus = ShellStatus(
  networkName: 'Home-WiFi',
  address: '192.168.1.24:53317',
  verifiedDevices: 3,
  activeTransfers: 3,
  deviceCount: 4,
  suppressedClips: 1,
  clips: [
    ClipItem(ClipKind.text,
        "Meeting notes: finalize protocol spec v2.0 before Friday's review",
        sourceDevice: 'MacBook Pro', age: 'just now'),
    ClipItem(ClipKind.link, 'https://github.com/nCotista/DropClip/pull/42',
        sourceDevice: 'Pixel 8', age: '2 min ago'),
    ClipItem(ClipKind.image, 'Screenshot 2026-10-28 at 22.14.png · 1.8 MB',
        sourceDevice: 'iPhone 15', age: '9 min ago'),
    ClipItem(ClipKind.text, 'Remember to update the RTM table for FR-11',
        sourceDevice: 'Surface Laptop', age: '21 min ago'),
  ],
);
