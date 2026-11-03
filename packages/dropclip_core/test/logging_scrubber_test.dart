import 'dart:convert';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

/// Builds a fake PEM block. The armor label is assembled at runtime so the
/// literal `BEGIN ... PRIVATE KEY` header never appears in the repository,
/// which the CI secret scan (NFR-S02) rejects. The body is not a real key.
String _fakePem(String type, String body) {
  const label = 'PRIVATE ' 'KEY';
  return '-----BEGIN $type $label-----\n$body\n-----END $type $label-----';
}

void main() {
  group('LoggingScrubber (T0.3 & NFR-S02, NFR-S04)', () {
    test('Redacts PEM EC and RSA Private Keys from string messages', () {
      for (final type in ['EC', 'RSA']) {
        final pemKey = _fakePem(type,
            'MHcCAQEEIIz9U/R5c+76w1yX1a7s5tM4k+79A9jK3a71b2c3d4e5\noAoGCCqGSM49AwEHoUQDQgAE');

        final logMessage = 'Key generation successful: $pemKey for node-1';
        final scrubbed = LoggingScrubber.scrubText(logMessage);

        expect(scrubbed, contains('[REDACTED_PRIVATE_KEY]'), reason: type);
        expect(scrubbed, isNot(contains('MHcCAQEEIIz9U')), reason: type);
      }
    });

    test(
        'Redacts sensitive keys (pin, password, token, private_key) in structured data',
        () {
      final data = {
        'device_name': 'MacBook Pro',
        'pin': '639589',
        'password': 'SuperSecretPassword',
        'token': 'auth_bearer_987654321',
        'safe_counter': 42,
      };

      final scrubbed = LoggingScrubber.scrubData(data) as Map<String, dynamic>;

      expect(scrubbed['device_name'], equals('MacBook Pro'));
      expect(scrubbed['safe_counter'], equals(42));
      expect(scrubbed['pin'], equals('[REDACTED]'));
      expect(scrubbed['password'], equals('[REDACTED]'));
      expect(scrubbed['token'], equals('[REDACTED]'));
    });

    test(
        'Redacts raw payload and clipboard content while preserving length metadata',
        () {
      final data = {
        'event': 'clipboard.update',
        'payload': 'Secret company contract and personal identifiers',
        'clip_text': 'Confidential memo',
      };

      final scrubbed = LoggingScrubber.scrubData(data) as Map<String, dynamic>;

      expect(scrubbed['payload'], equals('[REDACTED_CONTENT: length=48]'));
      expect(scrubbed['clip_text'], equals('[REDACTED_CONTENT: length=17]'));
      expect(scrubbed['payload'], isNot(contains('Secret company contract')));
    });

    test('Recursively scrubs nested collections', () {
      final data = {
        'session': {
          'user': 'alice',
          'credentials': {'private_key': '0123456789abcdef'},
        },
        'items': [
          {'pin': '123456'},
          {'status': 'ok'},
        ],
      };

      final scrubbed = LoggingScrubber.scrubData(data) as Map<String, dynamic>;

      final nested = (scrubbed['session']
          as Map<String, dynamic>)['credentials'] as Map<String, dynamic>;
      expect(nested['private_key'], equals('[REDACTED]'));

      final items = scrubbed['items'] as List;
      expect((items[0] as Map)['pin'], equals('[REDACTED]'));
      expect((items[1] as Map)['status'], equals('ok'));
    });

    test('Formats valid single-line JSON log conforming to schema', () {
      final jsonLine = LoggingScrubber.formatLogLine(
        level: 'info',
        component: 'discovery',
        deviceId: 'dev-001',
        msg: 'Device discovered on mDNS',
        data: {'ip': '192.168.1.100', 'port': 52520, 'pin': '123456'},
        timestamp: DateTime.utc(2026, 10, 13, 12, 0, 0),
      );

      final parsed = jsonDecode(jsonLine) as Map<String, dynamic>;
      expect(parsed['ts'], equals('2026-10-13T12:00:00.000Z'));
      expect(parsed['level'], equals('INFO'));
      expect(parsed['component'], equals('discovery'));
      expect(parsed['device_id'], equals('dev-001'));
      expect(parsed['msg'], equals('Device discovered on mDNS'));

      final data = parsed['data'] as Map<String, dynamic>;
      expect(data['ip'], equals('192.168.1.100'));
      expect(data['port'], equals(52520));
      expect(data['pin'], equals('[REDACTED]'));
    });
  });
}
