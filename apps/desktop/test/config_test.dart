import 'dart:convert';
import 'dart:io';

import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dropclip_cfg'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('AppConfig (§15.6, FR-12)', () {
    test('defaults match the spec; auto_accept is off (T-E03)', () {
      final json = const AppConfig(deviceName: 'PC').toJson();
      expect(json, {
        'version': 1,
        'device_name': 'PC',
        'auto_accept': false,
        'destination_dir': '~/Downloads/DropClip',
        'clipboard_sync_enabled': true,
        'sync_types': ['text', 'url', 'image'],
        'clipboard_ttl_seconds': null,
        'auto_start': true,
        'log_level': 'info',
        'language': 'th',
        'first_run_done': false,
        'web_companion_enabled': false,
      });
    });

    test('round-trips every field', () {
      const c = AppConfig(
        deviceName: 'โน้ตบุ๊ก 💻',
        autoAccept: true,
        destinationDir: r'D:\Inbox',
        clipboardSyncEnabled: false,
        syncTypes: {SyncType.text},
        clipboardTtlSeconds: 60,
        autoStart: false,
        language: AppLanguage.en,
        firstRunDone: true,
        webCompanionEnabled: true,
      );
      final back = AppConfig.fromJson(c.toJson(), defaultDeviceName: 'x');
      expect(back.toJson(), c.toJson());
    });

    test('invalid values fall back to defaults and warn', () {
      final warns = <String>[];
      final c = AppConfig.fromJson({
        'device_name': '  ',
        'auto_accept': 'yes',
        'sync_types': ['text', 'video'],
        'clipboard_ttl_seconds': -5,
        'log_level': 'loud',
        'language': 'fr',
      }, defaultDeviceName: 'PC', onWarn: warns.add);
      expect(c.toJson(), const AppConfig(deviceName: 'PC').toJson());
      expect(warns, hasLength(6));
    });

    test('missing keys use defaults silently', () {
      final warns = <String>[];
      final c = AppConfig.fromJson({'auto_start': false},
          defaultDeviceName: 'PC', onWarn: warns.add);
      expect(c.autoStart, isFalse);
      expect(c.autoAccept, isFalse);
      expect(warns, isEmpty);
    });

    test('copyWith can clear the TTL', () {
      const c = AppConfig(deviceName: 'PC', clipboardTtlSeconds: 60);
      expect(c.copyWith(clipboardTtlSeconds: () => null).clipboardTtlSeconds,
          isNull);
      expect(c.copyWith(autoAccept: true).clipboardTtlSeconds, 60);
    });

    test('resolveDestinationDirectory expands ~/ and avoids relative ./~', () {
      const def = AppConfig(deviceName: 'PC');
      expect(
          def
              .resolveDestinationDirectory({'HOME': '/Users/a'},
                  isWindows: false)
              .path,
          '/Users/a/Downloads/DropClip');
      expect(
          def
              .resolveDestinationDirectory({'USERPROFILE': r'C:\Users\a'},
                  isWindows: true)
              .path,
          r'C:\Users\a\Downloads\DropClip');
      expect(
          const AppConfig(deviceName: 'PC', destinationDir: '~')
              .resolveDestinationDirectory({'HOME': '/Users/a/'},
                  isWindows: false)
              .path,
          '/Users/a');
      final noHome = def.resolveDestinationDirectory({}, isWindows: false).path;
      expect(noHome.startsWith('~'), isFalse);
      expect(noHome.endsWith('Downloads/DropClip'), isTrue);
    });

    test('invalid ~user or blank destination_dir falls back cleanly', () {
      final warns = <String>[];
      final c = AppConfig.fromJson({'destination_dir': '~other/DropClip'},
          defaultDeviceName: 'PC', onWarn: warns.add);
      expect(c.destinationDir, '~/Downloads/DropClip');
      expect(warns, hasLength(1));

      final blank = AppConfig.fromJson({'destination_dir': '   '},
          defaultDeviceName: 'PC', onWarn: warns.add);
      expect(blank.destinationDir, '~/Downloads/DropClip');
      expect(warns, hasLength(2));

      expect(
          const AppConfig(deviceName: 'PC', destinationDir: '~other/DropClip')
              .resolveDestinationDirectory({'HOME': '/Users/a'},
                  isWindows: false)
              .path,
          '/Users/a/Downloads/DropClip');
    });
  });

  group('ConfigStore', () {
    test('missing file → defaults; save writes JSON and notifies', () async {
      final store = ConfigStore(File('${dir.path}/sub/config.json'),
          defaultDeviceName: 'PC');
      expect((await store.load()).autoStart, isTrue);

      var notified = 0;
      store.config.addListener(() => notified++);
      await store.save(store.config.value.copyWith(autoAccept: true));
      expect(notified, 1);
      final onDisk = jsonDecode(await store.file.readAsString()) as Map;
      expect(onDisk['auto_accept'], isTrue);
      expect(File('${store.file.path}.tmp').existsSync(), isFalse);
      expect((await store.load()).autoAccept, isTrue);
    });

    test('corrupt or non-object JSON → defaults with a warning', () async {
      final warns = <String>[];
      final file = File('${dir.path}/config.json');
      final store =
          ConfigStore(file, defaultDeviceName: 'PC', onWarn: warns.add);
      await file.writeAsString('{not json');
      expect((await store.load()).deviceName, 'PC');
      await file.writeAsString('[1, 2]');
      expect((await store.load()).deviceName, 'PC');
      expect(warns, hasLength(2));
    });

    test('default location per OS', () {
      expect(
          ConfigStore.defaultFile({'APPDATA': r'C:\Users\a\AppData\Roaming'},
                  isMacOS: false)
              .path,
          r'C:\Users\a\AppData\Roaming\DropClip\config.json');
      expect(ConfigStore.defaultFile({'HOME': '/Users/a'}, isMacOS: true).path,
          '/Users/a/Library/Application Support/DropClip/config.json');
    });
  });
}
