import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:meta/meta.dart';

import '../../dropclip_clipboard.dart' show ClipboardItem;

/// Native clipboard MIME types sent over the platform channel (§14.1).
/// Converting images to the wire format is the Dart normalizer's job (§11).
abstract final class ClipMime {
  static const text = 'text/plain';
  static const uriList = 'text/uri-list';
  static const png = 'image/png';
  static const jpeg = 'image/jpeg';
  static const tiff = 'image/tiff';
  static const winDib = 'image/x-win-dib';
  static const winDibV5 = 'image/x-win-dibv5';

  /// Most preferred first. PNG wins over DIB (§11.2) and DIBV5 over DIB
  /// because it keeps alpha.
  static const preference = [
    png,
    jpeg,
    tiff,
    winDibV5,
    winDib,
    uriList,
    text,
  ];

  static bool isKnown(String mime) => preference.contains(mime);
}

/// One clipboard state from the native watcher (§14.1 `ClipSnapshot`).
@immutable
class ClipSnapshot {
  /// macOS `changeCount` / Windows `GetClipboardSequenceNumber()`.
  final int changeToken;

  /// Set from the OS sensitive markers (§10.4). When true, [items] is always
  /// empty, even if a buggy native layer sent content (NFR-S04).
  final bool isConcealed;
  final List<ClipboardItem> items;

  /// Milliseconds since epoch when the native layer saw the change.
  final int ts;

  ClipSnapshot({
    required this.changeToken,
    required this.isConcealed,
    required List<ClipboardItem> items,
    required this.ts,
  }) : items = isConcealed ? const [] : List.unmodifiable(items);

  /// Decodes the platform channel map. Throws [FormatException] on a
  /// malformed map; never includes clipboard content in the message.
  factory ClipSnapshot.fromMap(Object? raw) {
    if (raw is! Map) throw const FormatException('ClipSnapshot: not a map');
    final token = raw['change_token'];
    final concealed = raw['is_concealed'];
    final ts = raw['ts'];
    if (token is! int || token < 0) {
      throw const FormatException('ClipSnapshot: bad change_token');
    }
    if (concealed is! bool) {
      throw const FormatException('ClipSnapshot: bad is_concealed');
    }
    if (ts is! int) throw const FormatException('ClipSnapshot: bad ts');

    // Concealed: do not even look at items (§10.4).
    if (concealed) {
      return ClipSnapshot(
          changeToken: token, isConcealed: true, items: const [], ts: ts);
    }

    final rawItems = raw['items'];
    if (rawItems is! List) {
      throw const FormatException('ClipSnapshot: bad items');
    }
    final items = <ClipboardItem>[];
    for (final e in rawItems) {
      if (e is! Map) throw const FormatException('ClipSnapshot: bad item');
      final mime = e['mime'];
      final data = e['data'];
      if (mime is! String || data is! List<int>) {
        throw const FormatException('ClipSnapshot: bad item fields');
      }
      // Unknown native formats and content over CLIPBOARD_MAX_SIZE (§16)
      // are skipped, not errors: the rest of the change is still usable.
      if (!ClipMime.isKnown(mime)) continue;
      if (data.length > ProtocolConstants.clipboardMaxSize) continue;
      items.add(ClipboardItem(mime: mime, data: data));
    }
    return ClipSnapshot(
        changeToken: token, isConcealed: false, items: items, ts: ts);
  }

  /// The item to sync, by [ClipMime.preference]; null when concealed or
  /// there is nothing usable.
  ClipboardItem? get preferred {
    for (final mime in ClipMime.preference) {
      for (final item in items) {
        if (item.mime == mime) return item;
      }
    }
    return null;
  }
}
