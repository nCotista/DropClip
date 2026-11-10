import 'dart:async';

/// Outbound event emitted by Android Quick Settings Tile or Share Sheet
/// over `dropclip/android/events` (PROTO-DC-V2.0 §14.2).
class AndroidBridgeEvent {
  final String action;
  final bool isSensitive;
  final String? text;
  final List<String> uris;
  final int timestampMs;

  const AndroidBridgeEvent({
    required this.action,
    this.isSensitive = false,
    this.text,
    this.uris = const <String>[],
    required this.timestampMs,
  });
}

/// Abstract gateway modeling Android platform channels (`dropclip/android/service`,
/// `dropclip/discovery`, and `dropclip/clipboard` per PROTO-DC-V2.0 §14.2).
abstract interface class AndroidNativeGateway {
  Future<bool> startForegroundService({required String serviceType});
  Future<void> stopForegroundService();
  Future<bool> isServiceRunning();
  Future<bool> acquireMulticastLock();
  Future<void> releaseMulticastLock();
  Future<bool> requestBatteryExemption();
  Future<void> writePrimaryClip(String text);
}

/// In-memory implementation of [AndroidNativeGateway] for unit & integration tests.
class InMemoryAndroidNativeGateway implements AndroidNativeGateway {
  bool _running = false;
  String? _activeServiceType;
  bool _multicastLockHeld = false;
  bool _batteryExempted = false;
  String? _primaryClip;

  bool get isMulticastLockHeld => _multicastLockHeld;
  bool get isBatteryExempted => _batteryExempted;
  String? get activeServiceType => _activeServiceType;
  String? get primaryClip => _primaryClip;

  @override
  Future<bool> startForegroundService({required String serviceType}) async {
    if (serviceType != 'connectedDevice') {
      throw ArgumentError.value(
        serviceType,
        'serviceType',
        'Android 14/15 requires foregroundServiceType="connectedDevice" (ADR-007)',
      );
    }
    _running = true;
    _activeServiceType = serviceType;
    return true;
  }

  @override
  Future<void> stopForegroundService() async {
    _running = false;
    _multicastLockHeld = false;
  }

  @override
  Future<bool> isServiceRunning() async => _running;

  @override
  Future<bool> acquireMulticastLock() async {
    if (!_running) return false;
    _multicastLockHeld = true;
    return true;
  }

  @override
  Future<void> releaseMulticastLock() async {
    _multicastLockHeld = false;
  }

  @override
  Future<bool> requestBatteryExemption() async {
    _batteryExempted = true;
    return true;
  }

  @override
  Future<void> writePrimaryClip(String text) async {
    _primaryClip = text;
  }
}

/// Core Dart Isolate IPC & Lifecycle Manager for Android Tier 2 (`T2.1`, PROTO §14.2).
class AndroidServiceBridge {
  static const String requiredForegroundType = 'connectedDevice';
  static const double maxDailyBatteryPercent = 3.0;

  final AndroidNativeGateway _gateway;
  final Future<void> Function()? _onReconnectAfterDoze;
  final StreamController<AndroidBridgeEvent> _outboundController =
      StreamController<AndroidBridgeEvent>.broadcast();
  bool _multicastHeld = false;
  int _suppressedSensitiveCount = 0;
  int _dozeRecoveryCount = 0;

  AndroidServiceBridge({
    required AndroidNativeGateway gateway,
    Future<void> Function()? onReconnectAfterDoze,
  })  : _gateway = gateway,
        _onReconnectAfterDoze = onReconnectAfterDoze;

  Stream<AndroidBridgeEvent> get outboundEvents => _outboundController.stream;
  bool get isMulticastLockHeld => _multicastHeld;
  int get suppressedSensitiveCount => _suppressedSensitiveCount;
  int get dozeRecoveryCount => _dozeRecoveryCount;

  Future<bool> startService({bool acquireMdnsLock = true}) async {
    final started = await _gateway.startForegroundService(
      serviceType: requiredForegroundType,
    );
    if (started && acquireMdnsLock) {
      _multicastHeld = await _gateway.acquireMulticastLock();
    }
    return started;
  }

  Future<void> stopService() async {
    if (_multicastHeld) {
      await _gateway.releaseMulticastLock();
      _multicastHeld = false;
    }
    await _gateway.stopForegroundService();
  }

  Future<bool> isRunning() => _gateway.isServiceRunning();

  Future<bool> acquireMulticastLock() async {
    _multicastHeld = await _gateway.acquireMulticastLock();
    return _multicastHeld;
  }

  Future<void> releaseMulticastLock() async {
    await _gateway.releaseMulticastLock();
    _multicastHeld = false;
  }

  Future<bool> requestBatteryExemption() => _gateway.requestBatteryExemption();

  Future<bool> onBootCompleted({required bool autoStartEnabled}) async {
    if (!autoStartEnabled) return false;
    return startService(acquireMdnsLock: true);
  }

  Future<void> onDozeStateChanged({required bool inDozeMode}) async {
    if (inDozeMode) {
      await releaseMulticastLock();
      return;
    }
    if (!await _gateway.isServiceRunning()) {
      await startService(acquireMdnsLock: true);
    } else {
      await acquireMulticastLock();
    }
    _dozeRecoveryCount++;
    if (_onReconnectAfterDoze != null) {
      await _onReconnectAfterDoze();
    }
  }

  bool handleNativeEvent(AndroidBridgeEvent event) {
    if (event.isSensitive) {
      _suppressedSensitiveCount++;
      return false;
    }
    _outboundController.add(event);
    return true;
  }

  Future<void> writeInboundClipboard(String text) =>
      _gateway.writePrimaryClip(text);

  Future<void> dispose() async {
    await stopService();
    await _outboundController.close();
  }
}
