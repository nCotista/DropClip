import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:shelf/shelf.dart';

import '../security/p256.dart';
import '../security/trusted_device_store.dart';
import 'pairing_engine.dart';

/// What the Host's pairing screen shows (UI-03).
sealed class PairingHostEvent {
  const PairingHostEvent();
}

/// Both sides show [sas]; the Host user compares and calls [PairingHost.confirm].
class PairingSasReady extends PairingHostEvent {
  final String sas, peerName, peerOs;
  const PairingSasReady(this.sas, this.peerName, this.peerOs);
}

class PairingCompleted extends PairingHostEvent {
  final TrustedDevice device;
  const PairingCompleted(this.device);
}

class PairingFailed extends PairingHostEvent {
  final String code;
  const PairingFailed(this.code);
}

/// The Host side of §5.4 served at `/api/v1/pair*` by [TlsTransportServer].
///
/// `/pair` must carry the client's certificate as `cert` (base64 DER) whose
/// SHA-256 equals `fp`: the server refuses client certs it was not given, so
/// the Host needs the cert itself to accept the peer's mTLS later (§4.4).
/// `/finalize` waits for the Host user's [confirm] before answering.
class PairingHost {
  final PairingEngine engine;
  final TrustedDeviceStore store;

  /// Called once a peer is stored, e.g. to trust its cert on the server.
  final void Function(TrustedDevice device)? onPaired;

  final _events = StreamController<PairingHostEvent>.broadcast();
  Completer<bool>? _decision;
  String _peerName = '', _peerOs = '';
  String? _peerFp;

  PairingHost({required this.engine, required this.store, this.onPaired});

  Stream<PairingHostEvent> get events => _events.stream;

  /// Opens a single-use session (§5.1) and returns what to show on screen.
  ({String pin, QrPairingPayload qr}) open({
    required String ip,
    required int port,
  }) {
    _decision = Completer<bool>();
    final s = engine.startSession(hostIp: ip, hostPort: port);
    return (pin: s.pin, qr: s.qr);
  }

  /// The Host user's answer to "do the numbers match?".
  void confirm(bool match) {
    final d = _decision;
    if (d != null && !d.isCompleted) d.complete(match);
  }

  Handler get handler => (Request request) async {
        final info = request.context['shelf.io.connection_info'];
        final ip =
            info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
        try {
          final body = jsonDecode(await request.readAsString());
          if (body is! Map<String, dynamic>) throw const FormatException();
          return _json(200, await _handle(request.url.path, body, ip));
        } on FormatException {
          const e = ProtocolException(ProtocolErrorCode.malformed, 'bad JSON');
          return _json(e.httpStatus, e.toHttpJson());
        } on ProtocolException catch (e) {
          if (request.url.path.endsWith('finalize')) {
            _events.add(PairingFailed(e.errorCode.code));
          }
          return _json(e.httpStatus, e.toHttpJson());
        }
      };

  Future<Map<String, dynamic>> _handle(
      String path, Map<String, dynamic> body, String ip) async {
    switch (path) {
      case 'api/v1/pair':
        final der = _certDer(body);
        _peerName = body['name'] as String? ?? '';
        _peerOs = body['os'] as String? ?? '';
        return engine.handlePairRequest(body,
            clientIp: ip,
            tlsClientCertFp: sha256.convert(der).toString(),
            tlsClientCertPem: P256.certPemFromDer(der));
      case 'api/v1/pair/confirm':
        final reply = engine.handlePairConfirm(body, clientIp: ip);
        _events
            .add(PairingSasReady(engine.currentSasCode!, _peerName, _peerOs));
        return reply;
      case 'api/v1/pair/finalize':
        final clientMatched = body['result'] == 'match';
        final hostMatched = clientMatched &&
            await (_decision?.future ?? Future.value(false)).timeout(
                const Duration(
                    milliseconds: PairingEngine.pairConfirmTimeoutMs),
                onTimeout: () => false);
        final reply = await engine.handlePairFinalize(body,
            clientIp: ip, hostUserConfirmedMatch: hostMatched);
        final device = store.getByFingerprint(_peerFp!)!;
        onPaired?.call(device);
        _events.add(PairingCompleted(device));
        return reply;
      default:
        throw const ProtocolException(
            ProtocolErrorCode.malformed, 'unknown pairing path');
    }
  }

  List<int> _certDer(Map<String, dynamic> body) {
    try {
      final der = base64Decode(body['cert'] as String? ?? '');
      final fp = (body['fp'] as String? ?? '').toLowerCase();
      if (der.isNotEmpty && sha256.convert(der).toString() == fp) {
        _peerFp = fp;
        return der;
      }
    } on FormatException {
      // Falls through to the same error as a mismatched cert.
    }
    throw const ProtocolException(
        ProtocolErrorCode.pairingInvalid, 'cert missing or not matching fp');
  }

  static Response _json(int status, Map<String, dynamic> body) => Response(
        status,
        body: jsonEncode(body),
        headers: const {'content-type': 'application/json'},
      );

  Future<void> close() => _events.close();
}
