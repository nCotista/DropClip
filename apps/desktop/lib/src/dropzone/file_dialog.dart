import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

/// Opens the OS "open files" dialog (multi-select) and returns the chosen
/// paths, or none if cancelled. Windows: `GetOpenFileNameW` via FFI, in an
/// isolate so the UI keeps painting. macOS: the system `choose file` dialog
/// through `osascript` (no extra plugin; `file_selector` conflicts with
/// desktop_drop's `cross_file`).
///
/// Not unit-tested: it needs a user to pick files.
Future<List<String>> pickFiles() async {
  if (Platform.isWindows) return Isolate.run(_windowsPick);
  if (Platform.isMacOS) {
    final r = await Process.run('/usr/bin/osascript', [
      '-e', 'set fs to choose file with multiple selections allowed', //
      '-e', 'set out to ""',
      '-e', 'repeat with f in fs',
      '-e', 'set out to out & POSIX path of f & linefeed',
      '-e', 'end repeat',
      '-e', 'return out',
    ]);
    if (r.exitCode != 0) return const [];
    return (r.stdout as String).split('\n').where((p) => p.isNotEmpty).toList();
  }
  return const [];
}

/// Splits the `lpstrFile` result: one full path, or a folder followed by
/// file names, each NUL-terminated, ending with an empty string.
List<String> parseOpenFileResult(List<String> parts) {
  final p = parts.where((s) => s.isNotEmpty).toList();
  if (p.length <= 1) return p;
  final dir = p.first.endsWith(r'\') ? p.first : '${p.first}\\';
  return [for (final name in p.skip(1)) '$dir$name'];
}

List<String> _windowsPick() {
  // The Explorer-style dialog needs COM on this (worker) thread.
  final com = _coInitializeEx(nullptr, 0x2); // COINIT_APARTMENTTHREADED
  try {
    return _openDialog();
  } finally {
    if (com >= 0) _coUninitialize();
  }
}

List<String> _openDialog() {
  const chars = 1 << 16;
  final ofn = calloc<_OpenFileName>();
  final buffer = calloc<Uint16>(chars);
  try {
    ofn.ref
      ..lStructSize = sizeOf<_OpenFileName>()
      ..hwndOwner = _getForegroundWindow()
      ..lpstrFile = buffer.cast()
      ..nMaxFile = chars
      // OFN_EXPLORER | OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST |
      // OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR
      ..flags = 0x80000 | 0x200 | 0x1000 | 0x800 | 0x8;
    if (_getOpenFileName(ofn) == 0) return const [];
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < chars; i++) {
      if (buffer[i] == 0) {
        if (i == start) break;
        parts.add(String.fromCharCodes(buffer.asTypedList(chars), start, i));
        start = i + 1;
      }
    }
    return parseOpenFileResult(parts);
  } finally {
    calloc
      ..free(buffer)
      ..free(ofn);
  }
}

final _comdlg32 = DynamicLibrary.open('comdlg32.dll');
final _user32 = DynamicLibrary.open('user32.dll');
final _ole32 = DynamicLibrary.open('ole32.dll');
final _coInitializeEx = _ole32.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32),
    int Function(Pointer<Void>, int)>('CoInitializeEx');
final _coUninitialize =
    _ole32.lookupFunction<Void Function(), void Function()>('CoUninitialize');
final _getOpenFileName = _comdlg32.lookupFunction<
    Int32 Function(Pointer<_OpenFileName>),
    int Function(Pointer<_OpenFileName>)>('GetOpenFileNameW');
final _getForegroundWindow =
    _user32.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetForegroundWindow');

/// `OPENFILENAMEW` (commdlg.h).
final class _OpenFileName extends Struct {
  @Uint32()
  external int lStructSize;
  external Pointer<Void> hwndOwner;
  external Pointer<Void> hInstance;
  external Pointer<Utf16> lpstrFilter;
  external Pointer<Utf16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Utf16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Utf16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Utf16> lpstrInitialDir;
  external Pointer<Utf16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Utf16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  external Pointer<Void> lpfnHook;
  external Pointer<Utf16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}
