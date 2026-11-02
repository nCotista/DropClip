/// Snapshot shown in the shell's sidebar. Filled from the engine once T1.9
/// (clipboard sync) and T1.11 (transfers) land; demo values until then.
class ShellStatus {
  final String networkName;
  final String address;
  final int verifiedDevices;
  final int clipCount;
  final int activeTransfers;
  final int deviceCount;

  const ShellStatus({
    required this.networkName,
    required this.address,
    required this.verifiedDevices,
    required this.clipCount,
    required this.activeTransfers,
    required this.deviceCount,
  });
}

const demoShellStatus = ShellStatus(
  networkName: 'Home-WiFi',
  address: '192.168.1.24:53317',
  verifiedDevices: 3,
  clipCount: 20,
  activeTransfers: 3,
  deviceCount: 4,
);
