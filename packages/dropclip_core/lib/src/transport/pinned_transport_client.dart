import 'dart:io';
import 'dart:typed_data';

import '../security/device_identity.dart';
import '../security/trusted_device_store.dart';
import 'tls_transport_server.dart';

/// HTTPS / WebSocket client that pins the peer by SHA-256 fingerprint
/// (PROTO §4.4, client side) over TLS 1.3 only (§4.3).
///
/// No public CA is trusted, so every server cert goes through [verifyServer]:
/// with `expectedFp` (QR pairing / reconnect to a known device) only that
/// fingerprint passes; otherwise the fingerprint must pass `isTrusted`.
class PinnedTransportClient {
  final HttpClient httpClient;
  final String? _expectedFp;
  final bool Function(String fp) _isTrusted;

  PinnedTransportClient._(
    SecurityContext ctx,
    String? expectedFp,
    this._isTrusted,
  )   : _expectedFp = expectedFp?.toLowerCase(),
        httpClient = HttpClient(context: ctx) {
    httpClient.badCertificateCallback =
        (cert, _, __) => verifyServer(certificateFingerprint(cert));
  }

  /// Client for a paired device: presents this device's cert (mTLS).
  factory PinnedTransportClient.paired({
    required Uint8List certPem,
    required Uint8List keyPem,
    required bool Function(String fp) isTrusted,
    String? expectedFp,
  }) =>
      PinnedTransportClient._(
        _tls13()
          ..useCertificateChainBytes(certPem)
          ..usePrivateKeyBytes(keyPem),
        expectedFp,
        isTrusted,
      );

  /// Client for the pairing endpoints: sends NO client cert, because the
  /// host does not trust it yet and the handshake would fail (§4.4).
  factory PinnedTransportClient.pairing({required String expectedFp}) =>
      PinnedTransportClient._(_tls13(), expectedFp, (_) => false);

  /// Paired client using this device's identity; the private key is read
  /// from envelope storage (§4.2) and the decrypted copy is zeroed.
  static Future<PinnedTransportClient> forIdentity({
    required DeviceIdentityManager identity,
    required TrustedDeviceStore store,
    String? expectedFp,
  }) async {
    final keyPem = await identity.loadPrivateKeyPem();
    try {
      return PinnedTransportClient.paired(
        certPem: identity.identity.certPem,
        keyPem: keyPem,
        isTrusted: store.isActiveFingerprint,
        expectedFp: expectedFp,
      );
    } finally {
      keyPem.fillRange(0, keyPem.length, 0);
    }
  }

  /// Returns true iff the server cert fingerprint [fp] is acceptable.
  bool verifyServer(String fp) {
    final expected = _expectedFp;
    return expected != null ? fp == expected : _isTrusted(fp);
  }

  /// Opens `wss://` through the same pinned TLS client (§6.1).
  Future<WebSocket> connectWebSocket(Uri uri) =>
      WebSocket.connect(uri.toString(), customClient: httpClient);

  void close({bool force = false}) => httpClient.close(force: force);

  static SecurityContext _tls13() => SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3;
}
