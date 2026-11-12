import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../security/device_identity.dart';
import '../security/trusted_device_store.dart';

/// First port of the DropClip transport range (PROTO §3.1, T1.4).
const int kTransportPortFirst = 53317;

/// Last port of the DropClip transport range (inclusive).
const int kTransportPortLast = 53417;

/// shelf request context key holding the verified peer fingerprint (§4.4).
const String kPeerFingerprintContextKey = 'dropclip.peer_fp';

/// Control Plane endpoint (§6.1), upgraded outside shelf.
const String kWebSocketPath = '/api/v1/ws';

/// Takes over a pinned `/api/v1/ws` request from the peer with [fp].
typedef WebSocketUpgrade = void Function(HttpRequest request, String fp);

/// The only endpoints reachable without a pinned client cert (§4.4, §9.1).
const Set<String> kPairingPaths = <String>{
  '/api/v1/pair',
  '/api/v1/pair/confirm',
  '/api/v1/pair/finalize',
};

/// `SHA-256(DER(cert))` as lowercase hex (§4.1).
String certificateFingerprint(X509Certificate cert) =>
    sha256.convert(cert.der).toString();

/// Builds a TLS 1.3-only context (§4.3) that trusts no public CA, presents
/// [certPem] / [keyPem], and accepts client certs in [trustedPeerCertsPem].
SecurityContext buildTls13Context({
  required Uint8List certPem,
  required Uint8List keyPem,
  Iterable<Uint8List> trustedPeerCertsPem = const <Uint8List>[],
}) {
  final ctx = SecurityContext(withTrustedRoots: false)
    ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
    ..useCertificateChainBytes(certPem)
    ..usePrivateKeyBytes(keyPem);
  for (final pem in trustedPeerCertsPem) {
    ctx.setTrustedCertificatesBytes(pem);
  }
  return ctx;
}

/// Thrown when no port in the requested range can be bound.
class TransportBindException implements Exception {
  final int firstPort;
  final int lastPort;
  final Object? lastError;

  const TransportBindException(this.firstPort, this.lastPort, this.lastError);

  @override
  String toString() =>
      'TransportBindException: no free port in $firstPort-$lastPort '
      '($lastError)';
}

/// mTLS 1.3 HTTPS server with SHA-256 fingerprint pinning (PROTO §4.3–§4.4).
///
/// Every request except [kPairingPaths] must carry a client cert whose
/// fingerprint passes `isTrusted`; otherwise it gets `403 E_NOT_PAIRED`.
/// The check runs on every request because a `SecurityContext` cannot drop
/// trust, so a revoked cert still completes the handshake until restart.
class TlsTransportServer {
  final HttpServer _server;
  final SecurityContext _context;
  final bool Function(String fp) _isTrusted;
  final Handler _pinnedHandler;
  final Handler? _pairingHandler;
  final WebSocketUpgrade? _webSocket;

  TlsTransportServer._(
    this._server,
    this._context,
    this._isTrusted,
    this._pinnedHandler,
    this._pairingHandler,
    this._webSocket,
  ) {
    _server.listen((req) {
      final ws = _webSocket;
      if (ws != null && req.uri.path == kWebSocketPath) {
        final cert = req.certificate;
        final fp = cert == null ? null : certificateFingerprint(cert);
        if (fp == null || !_isTrusted(fp)) {
          req.response
            ..statusCode = HttpStatus.forbidden
            ..close();
        } else {
          ws(req, fp);
        }
        return;
      }
      shelf_io.handleRequest(req, (r) => _route(req.certificate, r));
    });
  }

  int get port => _server.port;
  InternetAddress get address => _server.address;

  /// Binds the first free port in [firstPort]..[lastPort] (auto-shift).
  static Future<TlsTransportServer> bind({
    required SecurityContext context,
    required bool Function(String fp) isTrusted,
    required Handler pinnedHandler,
    Handler? pairingHandler,
    WebSocketUpgrade? webSocket,
    Object? address,
    int firstPort = kTransportPortFirst,
    int lastPort = kTransportPortLast,
  }) async {
    Object? lastError;
    for (var p = firstPort; p <= lastPort; p++) {
      try {
        final server = await HttpServer.bindSecure(
          address ?? InternetAddress.anyIPv4,
          p,
          context,
          requestClientCertificate: true,
        );
        return TlsTransportServer._(
          server,
          context,
          isTrusted,
          pinnedHandler,
          pairingHandler,
          webSocket,
        );
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw TransportBindException(firstPort, lastPort, lastError);
  }

  /// Binds with this device's identity and the active peers of [store].
  /// The private key is read from envelope storage (§4.2) and the decrypted
  /// copy is zeroed once BoringSSL has parsed it.
  static Future<TlsTransportServer> bindForIdentity({
    required DeviceIdentityManager identity,
    required TrustedDeviceStore store,
    required Handler pinnedHandler,
    Handler? pairingHandler,
    WebSocketUpgrade? webSocket,
    Object? address,
    int firstPort = kTransportPortFirst,
    int lastPort = kTransportPortLast,
  }) async {
    final keyPem = await identity.loadPrivateKeyPem();
    final SecurityContext ctx;
    try {
      ctx = buildTls13Context(
        certPem: identity.identity.certPem,
        keyPem: keyPem,
        trustedPeerCertsPem:
            store.activeDevices.map((d) => d.certPem).whereType<Uint8List>(),
      );
    } finally {
      keyPem.fillRange(0, keyPem.length, 0);
    }
    return bind(
      context: ctx,
      isTrusted: store.isActiveFingerprint,
      pinnedHandler: pinnedHandler,
      pairingHandler: pairingHandler,
      webSocket: webSocket,
      address: address,
      firstPort: firstPort,
      lastPort: lastPort,
    );
  }

  /// Trusts a newly paired peer's cert for future handshakes (no restart).
  void addTrustedPeerCert(Uint8List certPem) =>
      _context.setTrustedCertificatesBytes(certPem);

  Future<void> close({bool force = false}) => _server.close(force: force);

  Future<Response> _route(X509Certificate? cert, Request request) async {
    if (kPairingPaths.contains(request.requestedUri.path)) {
      final pairing = _pairingHandler;
      return pairing == null ? Response.notFound(null) : pairing(request);
    }
    final fp = cert == null ? null : certificateFingerprint(cert);
    if (fp == null || !_isTrusted(fp)) {
      const err = ProtocolException(
        ProtocolErrorCode.notPaired,
        'client certificate is not a paired device',
      );
      return Response(
        err.httpStatus,
        body: jsonEncode(err.toHttpJson()),
        headers: const {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
    }
    final response = await _pinnedHandler(
      request.change(context: {kPeerFingerprintContextKey: fp}),
    );
    return response.change(headers: const {'cache-control': 'no-store'});
  }
}
