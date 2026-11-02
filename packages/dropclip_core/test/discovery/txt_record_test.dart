import 'dart:convert';

import 'package:dropclip_core/dropclip_core.dart';
import 'package:test/test.dart';

const _id = '550e8400-e29b-41d4-a716-446655440000';
const _fp = '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';

Map<String, String> _validTxt() => {
      'v': '1',
      'min_v': '1',
      'id': _id,
      'name': 'TWFjQm9vayBQcm8g4LiC4Lit4LiH4LmA4LiI',
      'os': 'macos',
      'tier': '1',
      'port': '53317',
      'fp': _fp,
      'cap': 'clip.text,clip.image,clip.push,file,file.resume',
    };

void main() {
  group('DiscoveryRecord (T1.1, PROTO-DC-V2.0 §3.2)', () {
    test('Parses the spec example TXT record including a Thai name', () {
      final record = DiscoveryRecord.tryParse(_validTxt())!;

      expect(record.deviceId, _id);
      expect(record.name, 'MacBook Pro ของเจ');
      expect(record.os, DeviceOs.macos);
      expect(record.tier, 1);
      expect(record.port, 53317);
      expect(record.fingerprint, _fp);
      expect(record.capabilities, hasLength(5));
    });

    test('Round-trips Thai and emoji names through toTxt', () {
      final record = DiscoveryRecord(
        deviceId: _id,
        name: 'โน้ตบุ๊ก 💻🚀 ของธีร์',
        os: DeviceOs.windows,
        port: 53400,
        fingerprint: _fp,
      );

      final parsed = DiscoveryRecord.tryParse(record.toTxt())!;

      expect(parsed.name, 'โน้ตบุ๊ก 💻🚀 ของธีร์');
      expect(parsed.tier, 1);
      expect(record.toTxt().containsKey('cap'), isFalse);
      expect(parsed.capabilities, isEmpty);
    });

    test('Truncates names to 64 UTF-8 bytes on a code point boundary', () {
      final name = '😀' * 20; // 80 bytes
      final record = DiscoveryRecord(
        deviceId: _id,
        name: name,
        os: DeviceOs.macos,
        port: 53317,
        fingerprint: _fp,
      );

      expect(utf8.encode(record.name).length, 64);
      expect(record.name, '😀' * 16);
      expect(DiscoveryRecord.truncateName('ก' * 22), 'ก' * 21);
    });

    test('Normalises upper-case id and fingerprint', () {
      final txt = _validTxt()
        ..['id'] = _id.toUpperCase()
        ..['fp'] = _fp.toUpperCase();

      final record = DiscoveryRecord.tryParse(txt)!;

      expect(record.deviceId, _id);
      expect(record.fingerprint, _fp);
    });

    final malformed = <String, void Function(Map<String, String>)>{
      'missing v': (t) => t.remove('v'),
      'non-numeric v': (t) => t['v'] = 'x',
      'min_v above v': (t) => t['min_v'] = '2',
      'non-v4 id': (t) => t['id'] = '550e8400-e29b-11d4-a716-446655440000',
      'unknown os': (t) => t['os'] = 'linux',
      'tier inconsistent with os': (t) => t['tier'] = '3',
      'port out of range': (t) => t['port'] = '8080',
      'short fingerprint': (t) => t['fp'] = _fp.substring(1),
      'non-hex fingerprint': (t) => t['fp'] = 'z${_fp.substring(1)}',
      'invalid base64 name': (t) => t['name'] = '***',
      'invalid UTF-8 name': (t) => t['name'] = base64.encode([0xff, 0xfe]),
      'empty name': (t) => t['name'] = '',
      'name over 64 bytes': (t) =>
          t['name'] = base64.encode(List.filled(65, 65)),
    };

    for (final entry in malformed.entries) {
      test('Drops malformed record: ${entry.key}', () {
        final txt = _validTxt();
        entry.value(txt);
        expect(DiscoveryRecord.tryParse(txt), isNull);
      });
    }

    test('Tier is derived from OS for every platform', () {
      expect(DeviceOs.macos.tier, 1);
      expect(DeviceOs.windows.tier, 1);
      expect(DeviceOs.android.tier, 2);
      expect(DeviceOs.ios.tier, 3);
    });
  });
}
