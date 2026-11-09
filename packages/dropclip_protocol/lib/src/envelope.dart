import 'dart:convert';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'errors.dart';
import 'hlc.dart';

/// Normative Control Plane message types (PROTO-DC-V2.0 §7.2).
enum MessageType {
  hello('hello'),
  helloAck('hello.ack'),
  clipboardUpdate('clipboard.update'),
  clipboardClear('clipboard.clear'),
  fileOffer('file.offer'),
  fileAccept('file.accept'),
  fileReject('file.reject'),
  fileProgress('file.progress'),
  fileComplete('file.complete'),
  fileCancel('file.cancel'),
  deviceRevoked('device.revoked'),
  clusterRevocation('cluster.revocation'),
  revocationSync('revocation.sync'),
  ping('ping'),
  pong('pong'),
  error('error');

  final String wire;
  const MessageType(this.wire);

  bool get isControlExcludedFromQueue =>
      this == ping || this == pong || this == hello || this == helloAck;

  static MessageType? tryParse(String? raw) {
    if (raw == null) return null;
    for (final v in values) {
      if (v.wire == raw) return v;
    }
    return null;
  }
}

/// Control Plane WebSocket Envelope (PROTO-DC-V2.0 §7.1).
@immutable
class Envelope {
  static final RegExp _uuidV4Regex = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  final int v;
  final MessageType type;
  final String msgId;
  final String origin;
  final Hlc hlc;
  final int ts;
  final Map<String, dynamic> payload;

  Envelope({
    this.v = ProtocolConstants.protocolVersion,
    required this.type,
    required String msgId,
    required String origin,
    required this.hlc,
    required this.ts,
    required Map<String, dynamic> payload,
  })  : msgId = msgId.toLowerCase().trim(),
        origin = origin.toLowerCase().trim(),
        payload = Map.unmodifiable(payload) {
    if (v < 1 ||
        !_uuidV4Regex.hasMatch(this.msgId) ||
        !_uuidV4Regex.hasMatch(this.origin)) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'invalid envelope version or UUIDv4 identifiers',
      );
    }
  }

  factory Envelope.fromJson(Map<String, dynamic> json) {
    final v = json['v'];
    final typeRaw = json['type'];
    final msgId = json['msg_id'];
    final origin = json['origin'];
    final hlcRaw = json['hlc'];
    final ts = json['ts'];
    final payloadRaw = json['payload'];
    if (v is! int ||
        typeRaw is! String ||
        msgId is! String ||
        origin is! String ||
        hlcRaw is! Map ||
        ts is! int ||
        payloadRaw is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'missing or invalid required envelope fields',
      );
    }
    final parsedType = MessageType.tryParse(typeRaw);
    if (parsedType == null ||
        hlcRaw['l'] is! int ||
        hlcRaw['c'] is! int ||
        hlcRaw['d'] is! String) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'invalid message type or hlc fields',
      );
    }
    return Envelope(
      v: v,
      type: parsedType,
      msgId: msgId,
      origin: origin,
      hlc: Hlc.fromJson(Map<String, dynamic>.from(hlcRaw)),
      ts: ts,
      payload: Map<String, dynamic>.from(payloadRaw),
    );
  }

  factory Envelope.decodeWire(String rawFrame) {
    if (utf8.encode(rawFrame).length > ProtocolConstants.wsMaxMessageSize) {
      throw const ProtocolException(
        ProtocolErrorCode.payloadTooLarge,
        'WebSocket control frame exceeds 64 KiB limit',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawFrame);
    } on FormatException {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'malformed JSON in WebSocket frame',
      );
    }
    if (decoded is! Map) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'WebSocket frame root must be a JSON object',
      );
    }
    return Envelope.fromJson(Map<String, dynamic>.from(decoded));
  }

  Map<String, dynamic> toJson() => {
        'v': v,
        'type': type.wire,
        'msg_id': msgId,
        'origin': origin,
        'hlc': hlc.toJson(),
        'ts': ts,
        'payload': payload,
      };

  String encodeWire() {
    final encoded = jsonEncode(toJson());
    if (utf8.encode(encoded).length > ProtocolConstants.wsMaxMessageSize) {
      throw const ProtocolException(
        ProtocolErrorCode.payloadTooLarge,
        'encoded WebSocket control frame exceeds 64 KiB limit',
      );
    }
    return encoded;
  }
}
