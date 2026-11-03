library dropclip_clipboard;

export 'src/image/dib.dart';
export 'src/image/png_encoder.dart';

/// Data class representing an item on the native clipboard
class ClipboardItem {
  final String mime;
  final List<int> data;

  const ClipboardItem({required this.mime, required this.data});
}

/// Abstract contract for clipboard access across platforms (PROTO-DC-V2.0 §14.1)
abstract interface class PlatformClipboard {
  Future<void> start();
  Future<void> stop();
  Future<List<ClipboardItem>?> read();
  Future<int> write(List<ClipboardItem> items);
  Future<void> clear();
  int changeToken();
}
