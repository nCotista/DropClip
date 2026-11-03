import 'dart:convert';

import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:test/test.dart';

void main() {
  const validMsgId = '6f1c2c1e-6a43-4c4e-9d0c-0b6f3a5b1e27';
  const validOrigin = '550e8400-e29b-41d4-a716-446655440000';
  final sampleHlc = Hlc(l: 1757280000000, c: 0, d: validOrigin);

  group('ProtocolErrorCode & VersionNegotiator (§2.4, §8)', () {
    test('Maps all 18 normative error codes with HTTP status and fatal flags',
        () {
      expect(ProtocolErrorCode.values, hasLength(18));
      expect(ProtocolErrorCode.fromCode('E_UNSUPPORTED_VERSION').fatal, isTrue);
      expect(ProtocolErrorCode.fromCode('E_NOT_PAIRED').httpStatus, 403);
      expect(ProtocolErrorCode.fromCode('E_DISK_FULL').httpStatus, 507);
      expect(ProtocolErrorCode.tryFromCode('E_UNKNOWN'), isNull);
      expect(
          () => ProtocolErrorCode.fromCode('E_UNKNOWN'), throwsFormatException);
    });

    test('Negotiates mutually compatible protocol versions and rejects 4003',
        () {
      expect(
        VersionNegotiator.negotiate(
            localV: 2, localMinV: 1, remoteV: 1, remoteMinV: 1),
        equals(1),
      );
      expect(
        () => VersionNegotiator.negotiate(
            localV: 3, localMinV: 2, remoteV: 1, remoteMinV: 1),
        throwsA(
          isA<ProtocolException>()
              .having((e) => e.errorCode, 'code',
                  ProtocolErrorCode.unsupportedVersion)
              .having((e) => e.wsCloseCode, 'wsCloseCode', 4003),
        ),
      );
      expect(
        () => VersionNegotiator.negotiate(remoteV: 1, remoteMinV: 2),
        throwsA(isA<ProtocolException>()
            .having((e) => e.errorCode, 'code', ProtocolErrorCode.malformed)),
      );
    });
  });

  group('Envelope & MessageType (§7.1, §7.2)', () {
    test('Round-trips all 16 message types and ignores unknown JSON fields',
        () {
      expect(MessageType.values, hasLength(16));
      final env = Envelope(
        type: MessageType.clipboardUpdate,
        msgId: validMsgId,
        origin: validOrigin,
        hlc: sampleHlc,
        ts: 1757280000000,
        payload: const {'size': 11},
      );
      final withExtra = jsonEncode({
        ...jsonDecode(env.encodeWire()) as Map<String, dynamic>,
        'future_field': 'ignored_safely',
      });
      final decoded = Envelope.decodeWire(withExtra);
      expect(decoded.type, MessageType.clipboardUpdate);
      expect(decoded.msgId, validMsgId);
      expect(decoded.payload['size'], 11);
    });

    test('Enforces 64 KiB quota and rejects malformed frames', () {
      final oversized = Envelope(
        type: MessageType.clipboardUpdate,
        msgId: validMsgId,
        origin: validOrigin,
        hlc: sampleHlc,
        ts: 1757280000000,
        payload: {'inline': 'A' * 70000},
      );
      expect(
        oversized.encodeWire,
        throwsA(isA<ProtocolException>().having(
            (e) => e.errorCode, 'code', ProtocolErrorCode.payloadTooLarge)),
      );
      expect(
          () => Envelope.decodeWire('{bad'), throwsA(isA<ProtocolException>()));
      expect(
        () => Envelope(
          type: MessageType.ping,
          msgId: 'bad-uuid',
          origin: validOrigin,
          hlc: sampleHlc,
          ts: 1,
          payload: const {},
        ),
        throwsA(isA<ProtocolException>()),
      );
    });
  });
}
