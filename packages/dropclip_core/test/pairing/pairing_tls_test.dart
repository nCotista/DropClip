import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

typedef _Identity = ({DeviceIdentity device, SecurityContext tls});
typedef _Reply = ({int status, Map<String, dynamic> body, String fingerprint});

// Only encrypted key material reaches disk; the random password stays in memory.
Future<_Identity> _identity(String name) async {
  final dir = await Directory.systemTemp.createTemp('dc_pair_tls_');
  try {
    final random = Random.secure();
    final password =
        base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
    final certPath = '${dir.path}/cert.pem';
    final keyPath = '${dir.path}/key.enc';
    final process = await Process.start('openssl', [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:prime256v1',
      '-passout',
      'stdin',
      '-keyout',
      keyPath,
      '-out',
      certPath,
      '-days',
      '1',
      '-subj',
      '/CN=$name',
    ]);
    final output = process.stdout.drain<void>();
    final errors = process.stderr.drain<void>();
    process.stdin.writeln(password);
    await process.stdin.close();
    expect(await process.exitCode, 0, reason: 'P-256 fixture generation');
    await Future.wait([output, errors]);
    final pem =
        Uint8List.fromList(utf8.encode(await File(certPath).readAsString()));
    final keyPem = await File(keyPath).readAsString();
    expect(keyPem.contains('ENCRYPTED PRIVATE KEY'), isTrue);
    final encryptedKey = utf8.encode(keyPem);
    final der = await Process.run(
        'openssl', ['x509', '-in', certPath, '-outform', 'DER'],
        stdoutEncoding: null);
    expect(der.exitCode, 0);
    final bytes = Uint8List.fromList(der.stdout as List<int>);
    return (
      device: DeviceIdentity(
          deviceId: name,
          name: name,
          os: 'macos',
          certDer: bytes,
          certPem: pem,
          fp: sha256.convert(bytes).toString(),
          createdAt: 0),
      tls: SecurityContext(withTrustedRoots: false)
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3
        ..useCertificateChainBytes(pem)
        ..usePrivateKeyBytes(encryptedKey, password: password),
    );
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  late _Identity host, peer;
  late HttpServer server;
  late HttpClient http;
  late PairingEngine engine;
  late TrustedDeviceStore store;
  late QrPairingPayload qr;
  late String expectedServerFp;
  var now = 0;
  var hostMatches = true;
  final received = <(String, Map<String, dynamic>, bool)>[];

  setUpAll(() async {
    host = await _identity('pair-host');
    peer = await _identity('pair-client');
  });

  void session() {
    qr = engine
        .startSession(
            hostIp: '127.0.0.1', hostPort: server.port, pinOverride: '123456')
        .qr;
  }

  setUp(() async {
    now = DateTime.now().millisecondsSinceEpoch;
    hostMatches = true;
    received.clear();
    final dir = await Directory.systemTemp.createTemp('dc_pair_store_');
    addTearDown(() => dir.delete(recursive: true));
    store =
        TrustedDeviceStore(storageDir: dir, keyStore: InMemorySecureKeyStore());
    engine = PairingEngine(
        hostIdentity: host.device, trustedStore: store, clockMs: () => now);
    server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4, 0, host.tls,
        requestClientCertificate: true);
    addTearDown(() => server.close(force: true));
    // This is a test adapter, not the production T1.4 router.
    server.listen((request) async {
      try {
        final body = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        final path = request.uri.path;
        received.add((path, body, request.certificate == null));
        final ip = request.connectionInfo!.remoteAddress.address;
        final result = switch (path) {
          '/api/v1/pair' => engine.handlePairRequest(body,
              clientIp: ip,
              tlsClientCertFp: request.certificate == null
                  ? null
                  : sha256.convert(request.certificate!.der).toString()),
          '/api/v1/pair/confirm' =>
            engine.handlePairConfirm(body, clientIp: ip),
          '/api/v1/pair/finalize' => await engine.handlePairFinalize(body,
              clientIp: ip, hostUserConfirmedMatch: hostMatches),
          _ =>
            throw const ProtocolException(ProtocolErrorCode.malformed, 'path'),
        };
        request.response.write(jsonEncode(result));
      } on ProtocolException catch (error) {
        request.response
          ..statusCode = error.httpStatus
          ..persistentConnection = !error.fatal
          ..write(jsonEncode(error.toHttpJson()));
      } finally {
        await request.response.close();
      }
    });
    expectedServerFp = host.device.fp;
    http = HttpClient(
        context: SecurityContext(withTrustedRoots: false)
          ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_3)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (cert, _, __) =>
          sha256.convert(cert.der).toString() == expectedServerFp;
    addTearDown(() => http.close(force: true));
    session();
  });

  Future<_Reply> post(String path, Map<String, dynamic> body) async {
    final request = await http
        .postUrl(Uri.parse('https://127.0.0.1:${server.port}/api/v1/$path'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    final fingerprint = sha256.convert(response.certificate!.der).toString();
    final result = jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
    expect(result.keys,
        isNot(contains(anyOf('pin', 'pin_hash', 'pin_nonce', 'sas'))));
    if ((result['error'] as Map?)?['code'] == 'E_SAS_FAILED') {
      expect(response.persistentConnection, isFalse);
    }
    return (
      status: response.statusCode,
      body: result,
      fingerprint: fingerprint
    );
  }

  PairingClientProof proof(String method) => method == 'qr'
      ? PairingClientProof.fromQr(
          qr: qr.toJson(), clientFingerprint: peer.device.fp, nowMs: () => now)
      : PairingClientProof.forPin(
          pin: '123456', clientFingerprint: peer.device.fp);

  Map<String, dynamic> begin(PairingClientProof client) => {
        ...client.begin(),
        'v': 1,
        'min_supported_v': 1,
        'device_id': peer.device.deviceId,
        'name': 'client',
        'os': 'macos',
        'tier': 1,
      };

  Future<({PairingClientProof client, Map<String, String> confirm})> reveal(
      String method) async {
    final client = proof(method);
    final response = await post('pair', begin(client));
    expect(response.status, HttpStatus.ok);
    return (
      client: client,
      confirm: client.acceptHostReveal(
        pairId: response.body['pair_id'] as String,
        tlsServerFingerprint: response.fingerprint,
        responseFingerprint: response.body['host_fp'] as String,
        responseNonceA: response.body['nonce_A'] as String,
      )
    );
  }

  void error(_Reply response, ProtocolErrorCode code) {
    expect(response.status, code.httpStatus);
    expect((response.body['error'] as Map)['code'], code.code);
    expect(store.isActiveFingerprint(peer.device.fp), isFalse);
  }

  for (final method in ['qr', 'pin']) {
    test(
        '$method pairs over TLS 1.3 without a client certificate or PIN fields',
        () async {
      final timer = Stopwatch()..start();
      final flow = await reveal(method);
      expect((await post('pair/confirm', flow.confirm)).status, HttpStatus.ok);
      expect(flow.client.sas, engine.currentSasCode);
      expect(store.isActiveFingerprint(peer.device.fp), isFalse);
      expect(
          (await post('pair/finalize',
                  flow.client.finalize(userConfirmedMatch: true)))
              .status,
          HttpStatus.ok);
      expect(store.isActiveFingerprint(peer.device.fp), isTrue);
      expect(received.map((entry) => entry.$1), [
        '/api/v1/pair',
        '/api/v1/pair/confirm',
        '/api/v1/pair/finalize',
      ]);
      expect(received.every((entry) => entry.$3), isTrue);
      expect(
          received[0].$2.keys,
          unorderedEquals([
            'v',
            'min_supported_v',
            'device_id',
            'name',
            'os',
            'tier',
            'fp',
            'commitment_B',
            'method',
          ]));
      expect(received[1].$2.keys, unorderedEquals(['pair_id', 'nonce_B']));
      expect(received[2].$2.keys, unorderedEquals(['pair_id', 'result']));
      expect(
          SasCalculator.verifyCommitment(
              received[0].$2['commitment_B'] as String,
              base64Decode(flow.confirm['nonce_B']!),
              peer.device.fp),
          isTrue);
      timer.stop();
      // Automated loopback budget only; no camera scan or human confirmation.
      expect(timer.elapsed, lessThan(const Duration(seconds: 15)));
      print('$method automated TLS pairing: ${timer.elapsedMilliseconds} ms');
    });
  }

  for (final rejectingSide in ['client', 'host']) {
    test('$rejectingSide SAS rejection cannot persist trust', () async {
      final flow = await reveal('pin');
      await post('pair/confirm', flow.confirm);
      hostMatches = rejectingSide != 'host';
      error(
          await post(
              'pair/finalize',
              flow.client
                  .finalize(userConfirmedMatch: rejectingSide != 'client')),
          ProtocolErrorCode.sasFailed);
      expect(engine.state, PairingState.failed);
    });
  }

  test('a changed nonce cannot open the committed client proof', () async {
    final flow = await reveal('qr');
    final nonce = base64Decode(flow.confirm['nonce_B']!);
    nonce[0] ^= 1;
    error(
        await post(
            'pair/confirm', {...flow.confirm, 'nonce_B': base64Encode(nonce)}),
        ProtocolErrorCode.pairingInvalid);
    expect(engine.state, PairingState.failed);
  });

  test('server certificate pin mismatch fails before any HTTP request',
      () async {
    expectedServerFp = peer.device.fp;
    await expectLater(
        post('pair', begin(proof('qr'))), throwsA(isA<HandshakeException>()));
    expect(received, isEmpty);
    expect(engine.state, PairingState.open);
  });

  test('TLS 1.2 downgrade is rejected before HTTP', () async {
    for (final version in ['tls1_3', 'tls1_2']) {
      final process = await Process.start('openssl', [
        's_client',
        '-connect',
        '127.0.0.1:${server.port}',
        '-$version',
        '-brief',
      ]);
      final output = process.stdout.drain<void>();
      final errors = utf8.decoder.bind(process.stderr).join();
      await process.stdin.close();
      final exit = await process.exitCode.timeout(const Duration(seconds: 5),
          onTimeout: () {
        process.kill();
        fail('$version handshake did not finish promptly');
      });
      await output;
      final diagnostic = await errors;
      if (version == 'tls1_3') {
        expect(exit, 0);
        expect(diagnostic, contains('TLSv1.3'));
      } else {
        expect(exit, isNot(0));
        expect(diagnostic, isNot(contains('TLSv1.2')));
      }
    }
    expect(received, isEmpty);
  });

  test('expired session never reveals a host nonce', () async {
    final body = begin(proof('qr'));
    now += PairingEngine.pairNonceTtlMs + 1;
    final response = await post('pair', body);
    error(response, ProtocolErrorCode.nonceExpired);
    expect(response.body, isNot(contains('nonce_A')));
  });

  test('a supplied TLS certificate fingerprint still must match the claim', () {
    expect(
        () => engine.handlePairRequest(begin(proof('pin')),
            clientIp: '127.0.0.1', tlsClientCertFp: host.device.fp),
        throwsA(isA<ProtocolException>().having(
            (e) => e.errorCode, 'code', ProtocolErrorCode.pairingInvalid)));
    expect(store.isActiveFingerprint(peer.device.fp), isFalse);
  });

  test('certificate-free pairing still rejects a non-hex fingerprint',
      () async {
    error(await post('pair', {...begin(proof('pin')), 'fp': 'z' * 64}),
        ProtocolErrorCode.pairingInvalid);
  });

  test('sixth request is rate limited and the minute window recovers',
      () async {
    for (var i = 0; i < 5; i++) {
      session();
      expect((await post('pair', begin(proof('pin')))).status, HttpStatus.ok);
    }
    session();
    error(
        await post('pair', begin(proof('pin'))), ProtocolErrorCode.rateLimited);
    now += 60000;
    session();
    expect((await post('pair', begin(proof('pin')))).status, HttpStatus.ok);
  });

  test('three invalid commitments lock the IP for five minutes', () async {
    for (var i = 0; i < 3; i++) {
      session();
      final flow = await reveal('pin');
      final changedNonce = base64Decode(flow.confirm['nonce_B']!);
      changedNonce[0] ^= 1;
      error(
          await post('pair/confirm',
              {...flow.confirm, 'nonce_B': base64Encode(changedNonce)}),
          ProtocolErrorCode.pairingInvalid);
    }
    session();
    error(
        await post('pair', begin(proof('pin'))), ProtocolErrorCode.pairLocked);
    now += PairingEngine.pairLockoutDurationMs;
    session();
    expect((await post('pair', begin(proof('pin')))).status, HttpStatus.ok);
  });
}
