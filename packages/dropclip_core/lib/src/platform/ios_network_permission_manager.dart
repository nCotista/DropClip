import 'dart:async';
import 'dart:convert';

/// Local Network privacy permission states on iOS 15+ (`T3.1`, PROTO §14.3).
enum IosLocalNetworkPermissionState {
  notDetermined,
  preExplainerShown,
  granted,
  denied,
}

/// Validates required iOS `Info.plist` keys for Bonjour discovery without raw multicast.
class IosInfoPlistConfig {
  static const String requiredBonjourService = '_dropclip._tcp';
  final String? localNetworkUsageDescription;
  final List<String> bonjourServices;
  final int minimumIosMajorVersion;

  const IosInfoPlistConfig({
    required this.localNetworkUsageDescription,
    required this.bonjourServices,
    this.minimumIosMajorVersion = 15,
  });

  /// Verifies `NSLocalNetworkUsageDescription`, `NSBonjourServices`, and iOS 15+ support.
  void validate() {
    final desc = localNetworkUsageDescription?.trim() ?? '';
    if (desc.isEmpty) {
      throw StateError('Missing NSLocalNetworkUsageDescription in Info.plist');
    }
    if (!bonjourServices.contains(requiredBonjourService)) {
      throw StateError(
        'NSBonjourServices in Info.plist must contain $requiredBonjourService',
      );
    }
    if (minimumIosMajorVersion < 15) {
      throw StateError('Minimum supported iOS version must be >= 15');
    }
  }
}

/// Decoded Bonjour peer discovered via `NWBrowser` on iOS (`_dropclip._tcp`).
class IosNwDiscoveredPeer {
  final String deviceId;
  final String displayName;
  final String os;
  final int tier;
  final int port;
  final String fingerprint;

  const IosNwDiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.os,
    required this.tier,
    required this.port,
    required this.fingerprint,
  });

  factory IosNwDiscoveredPeer.fromTxtRecord(Map<String, String> txt) {
    final rawName = txt['name'] ?? '';
    final decodedName = utf8.decode(base64.decode(rawName));
    return IosNwDiscoveredPeer(
      deviceId: txt['id']!,
      displayName: decodedName,
      os: txt['os']!,
      tier: int.parse(txt['tier']!),
      port: int.parse(txt['port']!),
      fingerprint: txt['fp']!,
    );
  }
}

/// Abstract gateway for iOS `NWBrowser` and Settings deep-link platform channel (`dropclip/ios`).
abstract interface class IosNwBrowserGateway {
  Future<IosLocalNetworkPermissionState> startNwBrowser();
  Future<void> stopNwBrowser();
  Future<bool> openSystemSettings();
}

/// In-memory `NWBrowser` gateway for unit and integration testing across iOS 15/16/17+.
class InMemoryIosNwBrowserGateway implements IosNwBrowserGateway {
  IosLocalNetworkPermissionState simulatedOsResponse;
  bool browserRunning = false;
  int settingsOpenedCount = 0;

  InMemoryIosNwBrowserGateway({
    this.simulatedOsResponse = IosLocalNetworkPermissionState.granted,
  });

  @override
  Future<IosLocalNetworkPermissionState> startNwBrowser() async {
    browserRunning =
        simulatedOsResponse == IosLocalNetworkPermissionState.granted;
    return simulatedOsResponse;
  }

  @override
  Future<void> stopNwBrowser() async {
    browserRunning = false;
  }

  @override
  Future<bool> openSystemSettings() async {
    settingsOpenedCount++;
    return true;
  }
}

/// Manages iOS Pre-Permission Explainer, `NWBrowser` lifecycle, and Deny recovery (`T3.1`).
class IosNetworkDiscoveryBridge {
  final IosInfoPlistConfig plistConfig;
  final IosNwBrowserGateway _gateway;
  final StreamController<List<IosNwDiscoveredPeer>> _peersController =
      StreamController<List<IosNwDiscoveredPeer>>.broadcast();

  IosLocalNetworkPermissionState _state =
      IosLocalNetworkPermissionState.notDetermined;
  final Map<String, IosNwDiscoveredPeer> _peersById =
      <String, IosNwDiscoveredPeer>{};

  IosNetworkDiscoveryBridge({
    required this.plistConfig,
    required IosNwBrowserGateway gateway,
  }) : _gateway = gateway {
    plistConfig.validate();
  }

  IosLocalNetworkPermissionState get permissionState => _state;
  bool get shouldShowDeniedSettingsGuide =>
      _state == IosLocalNetworkPermissionState.denied;
  List<IosNwDiscoveredPeer> get currentPeers =>
      List<IosNwDiscoveredPeer>.unmodifiable(_peersById.values);
  Stream<List<IosNwDiscoveredPeer>> get peersStream => _peersController.stream;

  /// Marks that the Pre-Permission Explainer UI has been presented to the user.
  void markPreExplainerShown() {
    if (_state == IosLocalNetworkPermissionState.notDetermined) {
      _state = IosLocalNetworkPermissionState.preExplainerShown;
    }
  }

  /// Starts `NWBrowser` discovery after verifying the Pre-Permission Explainer was shown.
  Future<IosLocalNetworkPermissionState>
      requestPermissionAndStartDiscovery() async {
    if (_state == IosLocalNetworkPermissionState.notDetermined) {
      throw StateError(
        'Pre-permission explainer must be shown before triggering iOS Local Network prompt',
      );
    }
    _state = await _gateway.startNwBrowser();
    return _state;
  }

  /// Processes TXT records emitted by native `NWBrowser.browseResultsChangedHandler`.
  void onNativeBrowseResults(List<Map<String, String>> txtRecords) {
    if (_state != IosLocalNetworkPermissionState.granted) return;
    _peersById.clear();
    for (final txt in txtRecords) {
      try {
        final peer = IosNwDiscoveredPeer.fromTxtRecord(txt);
        _peersById[peer.deviceId] = peer;
      } on Object {
        // Ignore malformed TXT entries per PROTO §3.2.
      }
    }
    _peersController.add(currentPeers);
  }

  /// Deep-links to iOS App Settings when Local Network permission was denied.
  Future<bool> openSettingsForPermissionRecovery() {
    return _gateway.openSystemSettings();
  }

  Future<void> dispose() async {
    await _gateway.stopNwBrowser();
    await _peersController.close();
  }
}
