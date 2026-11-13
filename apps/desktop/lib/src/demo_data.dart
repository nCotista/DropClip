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

/// `online`: synced passively (Tier 1–2). `manual`: needs a user action,
/// e.g. iOS Share Sheet (Tier 3, FR-03C).
enum PeerReach { online, manual }

class NearbyDevice {
  final String name;

  /// e.g. `Android · 6 ms` or `iOS · Share Sheet`.
  final String detail;
  final PeerReach reach;

  /// The peer's device_id when it came from discovery.
  final String? id;

  const NearbyDevice(this.name, this.detail, this.reach, {this.id});
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
    this.nearby = const [],
    this.latencyP95Ms = const [],
  });

  final List<NearbyDevice> nearby;

  /// Recent clipboard sync latency p95 samples, oldest first (NFR-P01A).
  final List<int> latencyP95Ms;

  int get clipCount => clips.length;

  /// Replaces the demo nearby list with live discovery results (T1.1).
  ShellStatus withNearby(List<NearbyDevice> nearby) => copyWith(nearby: nearby);

  ShellStatus copyWith({
    String? networkName,
    String? address,
    int? verifiedDevices,
    int? activeTransfers,
    int? deviceCount,
    List<ClipItem>? clips,
    int? suppressedClips,
    List<NearbyDevice>? nearby,
  }) =>
      ShellStatus(
        networkName: networkName ?? this.networkName,
        address: address ?? this.address,
        verifiedDevices: verifiedDevices ?? this.verifiedDevices,
        activeTransfers: activeTransfers ?? this.activeTransfers,
        deviceCount: deviceCount ?? this.deviceCount,
        clips: clips ?? this.clips,
        suppressedClips: suppressedClips ?? this.suppressedClips,
        nearby: nearby ?? this.nearby,
        latencyP95Ms: latencyP95Ms,
      );
}

const demoShellStatus = ShellStatus(
  networkName: 'Home-WiFi',
  address: '192.168.1.24:53317',
  verifiedDevices: 3,
  activeTransfers: 3,
  deviceCount: 4,
  suppressedClips: 1,
  nearby: [
    NearbyDevice('Pixel 8', 'Android · 6 ms', PeerReach.online),
    NearbyDevice('Surface Laptop', 'Windows · 3 ms', PeerReach.online),
    NearbyDevice('iPhone 15', 'iOS · Share Sheet', PeerReach.manual),
  ],
  latencyP95Ms: [
    380, 402, 365, 431, 390, 410, 372, 455, 420, 388, //
    398, 470, 395, 415, 380, 428, 401, 449, 409, 412,
  ],
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
