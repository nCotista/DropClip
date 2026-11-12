import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';

import '../security/device_identity.dart';
import '../security/p256.dart';
import '../security/trusted_device_store.dart';

/// Client side of §5.4, PIN mode. TLS is server-auth only (§4.4); the Host
/// cert is pinned to [expectedHostFp] (mDNS `fp`) or, for a manual IP, to what
/// it shows, which the SAS then authenticates. The PIN never leaves this
/// device. The Host is stored only after both users confirmed the SAS.
class PairingClient {
  PairingClient._();

  static Future<TrustedDevice> pairWithPin({
    required String host,
    required int port,
    required String pin,
    required DeviceIdentity me,
    required TrustedDeviceStore store,
    required Future<bool> Function(String sas, String hostName) confirmSas,
    String? expectedHostFp,
    int tier = 1,
  }) async {
    final proof = PairingClientProof.forPin(pin: pin, clientFingerprint: me.fp);
    List<int>? serverDer;
    final http = HttpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (cert, _, __) {
        final fp = sha256.convert(cert.der).toString();
        if (expectedHostFp != null && fp != expectedHostFp.toLowerCase()) {
          return false;
        }
        serverDer = cert.der;
        return true;
      };
    Future<Map<String, dynamic>> post(
        String path, Map<String, Object> body) async {
      final req = await http.postUrl(
          Uri(scheme: 'https', host: host, port: port, path: '/api/v1/$path'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final json = jsonDecode(await utf8.decoder.bind(res).join())
          as Map<String, dynamic>;
      if (res.statusCode != 200) {
        final err = json['error'] as Map<String, dynamic>? ?? const {};
        throw PairingClientException(
            err['code'] as String? ?? 'HTTP ${res.statusCode}',
            err['message'] as String? ?? '');
      }
      return json;
    }

    try {
      final hello = await post('pair', {
        ...proof.begin(),
        'v': ProtocolConstants.protocolVersion,
        'min_supported_v': ProtocolConstants.minSupportedProtocolVersion,
        'device_id': me.deviceId,
        'name': me.name,
        'os': me.os,
        'tier': tier,
        'cert': base64Encode(me.certDer),
      });
      final hostDer = serverDer!;
      await post(
          'pair/confirm',
          proof.acceptHostReveal(
            pairId: hello['pair_id'] as String,
            tlsServerFingerprint: sha256.convert(hostDer).toString(),
            responseFingerprint: hello['host_fp'] as String,
            responseNonceA: hello['nonce_A'] as String,
          ));
      final hostName = hello['host_name'] as String? ?? host;
      final match = await confirmSas(proof.sas, hostName);
      await post('pair/finalize', proof.finalize(userConfirmedMatch: match));
      if (!match) throw const PairingClientException('E_SAS_FAILED', '');
      final now = DateTime.now().millisecondsSinceEpoch;
      final device = TrustedDevice(
        deviceId: hello['host_id'] as String,
        name: hostName,
        os: hello['host_os'] as String? ?? 'unknown',
        tier: hello['host_tier'] as int? ?? 1,
        fp: sha256.convert(hostDer).toString(),
        certPem: P256.certPemFromDer(hostDer),
        pairedAt: now,
        lastSeenAt: now,
      );
      await store.upsert(device);
      return device;
    } on ArgumentError catch (e) {
      throw PairingClientException('E_PAIRING_INVALID', '${e.message}');
    } finally {
      http.close(force: true);
    }
  }
}

/// Pairing stopped; [code] is the §8 error code (e.g. `E_SAS_FAILED`).
class PairingClientException implements Exception {
  final String code;
  final String message;

  const PairingClientException(this.code, this.message);

  @override
  String toString() => 'PairingClientException($code): $message';
}
