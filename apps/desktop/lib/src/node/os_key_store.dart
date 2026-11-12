import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:ffi/ffi.dart';

/// OS secure storage for the identity key and the Trusted Store key (§4.2,
/// NFR-S02): nothing is written to disk in plaintext.
///
/// Not unit-tested: it needs a real Windows/macOS user session.
SecureKeyStore osKeyStore(Directory dir) =>
    Platform.isWindows ? DpapiKeyStore(dir) : MacKeychainKeyStore();

/// Windows: DPAPI `CryptProtectData` (CurrentUser scope), one blob per key
/// under [dir].
class DpapiKeyStore implements SecureKeyStore {
  final Directory dir;

  DpapiKeyStore(this.dir);

  File _file(String key) =>
      File('${dir.path}/${key.replaceAll(RegExp(r'[^\w.-]'), '_')}.dpapi');

  @override
  Future<Uint8List?> read(String key) async {
    final f = _file(key);
    if (!await f.exists()) return null;
    return _dpapi(await f.readAsBytes(), protect: false);
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    await dir.create(recursive: true);
    await _file(key).writeAsBytes(_dpapi(value, protect: true), flush: true);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _protect =
      _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  static final _unprotect =
      _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');
  static final _localFree = _kernel32.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('LocalFree');

  static Uint8List _dpapi(Uint8List data, {required bool protect}) {
    final input = calloc<_Blob>();
    final output = calloc<_Blob>();
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = bytes;
      const uiForbidden = 0x1;
      final ok = (protect ? _protect : _unprotect)(
          input, nullptr, nullptr, nullptr, nullptr, uiForbidden, output);
      if (ok == 0) {
        throw StateError('DPAPI ${protect ? 'protect' : 'unprotect'} failed');
      }
      final out =
          Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      output.ref.pbData
          .asTypedList(output.ref.cbData)
          .fillRange(0, output.ref.cbData, 0);
      _localFree(output.ref.pbData.cast());
      return out;
    } finally {
      bytes.asTypedList(data.length).fillRange(0, data.length, 0);
      calloc
        ..free(bytes)
        ..free(input)
        ..free(output);
    }
  }
}

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(Pointer<_Blob>, Pointer<Void>,
    Pointer<_Blob>, Pointer<Void>, Pointer<Void>, Uint32, Pointer<_Blob>);
typedef _CryptDart = int Function(Pointer<_Blob>, Pointer<Void>, Pointer<_Blob>,
    Pointer<Void>, Pointer<Void>, int, Pointer<_Blob>);

/// macOS: login Keychain generic passwords via `/usr/bin/security`.
class MacKeychainKeyStore implements SecureKeyStore {
  static const _account = 'dropclip';

  @override
  Future<Uint8List?> read(String key) async {
    final r = await Process.run('/usr/bin/security',
        ['find-generic-password', '-a', _account, '-s', key, '-w']);
    if (r.exitCode != 0) return null;
    return base64Decode((r.stdout as String).trim());
  }

  @override
  Future<void> write(String key, Uint8List value) async {
    final r = await Process.run('/usr/bin/security', [
      'add-generic-password', '-U', '-a', _account, '-s', key, //
      '-w', base64Encode(value),
    ]);
    if (r.exitCode != 0) throw StateError('Keychain write failed: ${r.stderr}');
  }

  @override
  Future<void> delete(String key) => Process.run('/usr/bin/security',
      ['delete-generic-password', '-a', _account, '-s', key]);
}
