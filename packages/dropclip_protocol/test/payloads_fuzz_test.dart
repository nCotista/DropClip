import 'dart:convert';
import 'dart:math';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  const hash64 =
      '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

  group('Protocol Payloads & Size Routing (§7.4 & §18.5)', () {
    test('HelloPayload and RevocationBroadcastToken round-trip cleanly', () {
      const hello = HelloPayload(
        deviceId: '550e8400-e29b-41d4-a716-446655440000',
        name: 'MacBook Pro',
        os: 'macos',
        tier: 1,
        appVersion: '1.0.0',
        capabilities: ['clip.text', 'file'],
        tombstonesHash: hash64,
        tombstoneCount: 0,
      );
      expect(HelloPayload.fromJson(hello.toJson()).deviceId, hello.deviceId);
      const token = RevocationBroadcastToken(
        revokerId: '550e8400-e29b-41d4-a716-446655440000',
        revokedId: 'b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f',
        revokedFp: hash64,
        timestamp: 1757280000000,
        signature: 'MEUCIQ==',
      );
      expect(
        RevocationBroadcastToken.fromJson(token.toJson()).signingInput,
        'dropclip-revoke-v1:550e8400-e29b-41d4-a716-446655440000:'
        'b2c3d4e5-6a7b-8c9d-0e1f-2a3b4c5d6e7f:$hash64:1757280000000',
      );
    });

    test('Enforces ClipboardUpdatePayload size routing & FileOfferItem path',
        () {
      for (final s in [32767, 32768]) {
        final p = ClipboardUpdatePayload(
            contentType: 'text/plain', hash: hash64, size: s, inline: 'SGVs=');
        expect(ClipboardUpdatePayload.fromJson(p.toJson()).size, s);
      }
      for (final s in [32769, 33554432]) {
        final p = ClipboardUpdatePayload(
            contentType: 'text/plain', hash: hash64, size: s, blobId: 'b1');
        expect(ClipboardUpdatePayload.fromJson(p.toJson()).size, s);
      }
      expect(
        () => ClipboardUpdatePayload(
            contentType: 'text/plain',
            hash: hash64,
            size: 33554433,
            blobId: 'b1'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => ClipboardUpdatePayload(
            contentType: 'text/plain',
            hash: hash64,
            size: 5,
            isConcealed: true,
            inline: 'YWJjZA=='),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => FileOfferItem(
            itemId: 'i1',
            path: '../../etc/passwd',
            size: 10,
            sha256: hash64,
            mime: 'text/plain',
            modifiedAt: 1),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('Protocol Parser Fuzz Suite (T0.2 — 10,000 random inputs)', () {
    test('Survives 10,000 random binary and mutated JSON frames without crash',
        () {
      final rng = Random(20261103);
      var handled = 0;
      for (var i = 0; i < 10000; i++) {
        final bytes =
            List<int>.generate(rng.nextInt(128), (_) => rng.nextInt(256));
        final raw = (i % 2 == 0)
            ? utf8.decode(bytes, allowMalformed: true)
            : '{"v":${rng.nextInt(5)},"type":"hello","msg_id":"$i","payload":{}}';
        try {
          HelloPayload.fromJson(Envelope.decodeWire(raw).payload);
        } on ProtocolException {
          handled++;
        }
      }
      expect(handled, equals(10000));
    });
  });
}
