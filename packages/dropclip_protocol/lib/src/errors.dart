import 'package:meta/meta.dart';

import 'constants.dart';

/// Official 18 Protocol Error Codes defined in PROTO-DC-V2.0 §8.
enum ProtocolErrorCode {
  unsupportedVersion('E_UNSUPPORTED_VERSION', 400, true),
  notPaired('E_NOT_PAIRED', 403, true),
  revoked('E_REVOKED', 403, true),
  malformed('E_MALFORMED', 400, false),
  payloadTooLarge('E_PAYLOAD_TOO_LARGE', 413, false),
  rateLimited('E_RATE_LIMITED', 429, false),
  pairLocked('E_PAIR_LOCKED', 429, false),
  pairingInvalid('E_PAIRING_INVALID', 401, false),
  nonceExpired('E_NONCE_EXPIRED', 410, false),
  sasFailed('E_SAS_FAILED', 401, true),
  unknownTransfer('E_UNKNOWN_TRANSFER', 404, false),
  offsetMismatch('E_OFFSET_MISMATCH', 409, false),
  checksumMismatch('E_CHECKSUM_MISMATCH', 422, false),
  diskFull('E_DISK_FULL', 507, false),
  invalidPath('E_INVALID_PATH', 400, false),
  blobExpired('E_BLOB_EXPIRED', 410, false),
  unsupportedType('E_UNSUPPORTED_TYPE', 415, false),
  internal('E_INTERNAL', 500, false);

  final String code;
  final int httpStatus;
  final bool fatal;
  const ProtocolErrorCode(this.code, this.httpStatus, this.fatal);

  static ProtocolErrorCode? tryFromCode(String? code) {
    if (code == null) return null;
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }

  static ProtocolErrorCode fromCode(String code) =>
      tryFromCode(code) ??
      (throw FormatException('Unknown protocol error code: $code'));
}

/// Exception representing a normative DropClip protocol violation (§8).
@immutable
class ProtocolException implements Exception {
  final ProtocolErrorCode errorCode;
  final String message;
  final String? refMsgId;
  final int? wsCloseCode;

  const ProtocolException(
    this.errorCode,
    this.message, {
    this.refMsgId,
    this.wsCloseCode,
  });

  bool get fatal => errorCode.fatal;
  int get httpStatus => errorCode.httpStatus;

  Map<String, dynamic> toHttpJson() => {
        'error': {'code': errorCode.code, 'message': message},
      };

  Map<String, dynamic> toWsPayload() => {
        'code': errorCode.code,
        'message': message,
        'fatal': fatal,
        'ref_msg_id': refMsgId,
      };

  @override
  String toString() => 'ProtocolException(${errorCode.code}): $message';
}

/// Negotiates compatible wire protocol version per PROTO-DC-V2.0 §2.4 & §6.7.
class VersionNegotiator {
  VersionNegotiator._();

  static const int wsCloseProtocolError = 4000;
  static const int wsCloseDuplicateConnection = 4001;
  static const int wsCloseUnsupportedVersion = 4003;
  static const int wsCloseNotPairedOrRevoked = 4004;
  static const int wsCloseHeartbeatTimeout = 4008;

  static int negotiate({
    int localV = ProtocolConstants.protocolVersion,
    int localMinV = ProtocolConstants.minSupportedProtocolVersion,
    required int remoteV,
    required int remoteMinV,
  }) {
    if (remoteV < 1 || remoteMinV < 1 || remoteMinV > remoteV) {
      throw const ProtocolException(
        ProtocolErrorCode.malformed,
        'invalid protocol version bounds',
        wsCloseCode: wsCloseProtocolError,
      );
    }
    final negotiated = localV < remoteV ? localV : remoteV;
    final requiredMin = localMinV > remoteMinV ? localMinV : remoteMinV;
    if (negotiated < requiredMin) {
      throw const ProtocolException(
        ProtocolErrorCode.unsupportedVersion,
        'no mutually supported protocol version',
        wsCloseCode: wsCloseUnsupportedVersion,
      );
    }
    return negotiated;
  }
}
