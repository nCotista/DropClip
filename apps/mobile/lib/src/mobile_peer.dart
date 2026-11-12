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
}
