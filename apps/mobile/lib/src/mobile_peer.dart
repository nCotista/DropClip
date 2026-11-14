import 'package:dropclip_core/dropclip_core.dart';
import 'package:flutter/foundation.dart';

/// What the phone screen needs from the node, so tests can fake it.
abstract interface class MobilePeer {
  ValueListenable<List<TrustedDevice>> get trusted;
  Stream<Set<String>> get connectedChanges;
  Set<String> get connected;
  Future<TrustedDevice> pair(String host, int port, String pin,
      Future<bool> Function(String sas, String hostName) confirm);

  /// Pairs from the scanned QR text of the desktop's pairing screen (§5.3).
  Future<TrustedDevice> pairWithQr(String scanned,
      Future<bool> Function(String sas, String hostName) confirm);
  void sendText(String text);

  /// This phone's name, as paired computers see it.
  String get myName;

  /// Changes this phone's name; paired computers see it when they next
  /// connect.
  Future<void> rename(String name);

  /// Forgets a paired computer and tells it to forget this phone (§13.1).
  Future<void> forget(String deviceId);

  /// Sends the file at [path] to connected computer [deviceId] (FR-07);
  /// [onProgress] gets bytes sent so far and the total.
  Future<void> sendFile(String deviceId, String path,
      {void Function(int sent, int total)? onProgress});
}
