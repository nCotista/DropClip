import 'dart:io';

import 'package:dropclip_desktop/src/settings/auto_start.dart';
import 'package:dropclip_desktop/src/settings/config.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeReg {
  final calls = <List<String>>[];
  String? stored;
  int failAddWith = 0;

  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add([exe, ...args]);
    switch (args.first) {
      case 'query':
        return ProcessResult(0, stored == null ? 1 : 0,
            stored == null ? '' : '    DropClip    REG_SZ    $stored', '');
      case 'add':
        if (failAddWith != 0) {
          return ProcessResult(0, failAddWith, '', 'denied');
        }
        stored = args[args.indexOf('/d') + 1];
        return ProcessResult(0, 0, '', '');
      default: // delete
        final had = stored != null;
        stored = null;
        return ProcessResult(0, had ? 0 : 1, '', had ? '' : 'not found');
    }
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dropclip_cfg'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('WindowsRunKeyAutoStart (FR-12)', () {
    const exe = r'C:\Apps\DropClip\dropclip_desktop.exe';

    test('enable writes a hidden-launch Run value; disable removes it',
        () async {
      final reg = _FakeReg();
      final auto = WindowsRunKeyAutoStart(exe, run: reg.call);
      expect(await auto.isEnabled(), isFalse);

      await auto.setEnabled(true);
      expect(reg.stored, '"$exe" --hidden');
      expect(
          reg.calls.last,
          containsAllInOrder(
              ['reg', 'add', WindowsRunKeyAutoStart.key, '/v', 'DropClip']));
      expect(await auto.isEnabled(), isTrue);

      await auto.setEnabled(false);
      expect(await auto.isEnabled(), isFalse);
      await auto.setEnabled(false); // already gone: no error
    });

    test('a value pointing at another path is not ours', () async {
      final reg = _FakeReg()..stored = r'"C:\Old\dropclip.exe" --hidden';
      expect(await WindowsRunKeyAutoStart(exe, run: reg.call).isEnabled(),
          isFalse);
    });

    test('reg failure throws', () async {
      final reg = _FakeReg()..failAddWith = 5;
      expect(WindowsRunKeyAutoStart(exe, run: reg.call).setEnabled(true),
          throwsA(isA<AutoStartException>()));
    });
  });

  group('ConfigController', () {
    test('auto_start changes reach the OS before saving; failures keep old',
        () async {
      final reg = _FakeReg();
      final store =
          ConfigStore(File('${dir.path}/config.json'), defaultDeviceName: 'PC');
      await store.load();
      final ctl = ConfigController(
          store, WindowsRunKeyAutoStart(r'C:\a.exe', run: reg.call));

      await ctl.reconcile(); // default auto_start=true → registered
      expect(reg.stored, isNotNull);

      await ctl.update(store.config.value.copyWith(autoStart: false));
      expect(reg.stored, isNull);
      expect(store.config.value.autoStart, isFalse);

      reg.failAddWith = 5;
      await expectLater(
          ctl.update(store.config.value.copyWith(autoStart: true)),
          throwsA(isA<AutoStartException>()));
      expect(store.config.value.autoStart, isFalse);

      await ctl.update(store.config.value.copyWith(autoAccept: true));
      expect(reg.calls.where((c) => c[1] == 'add'), hasLength(2));
    });

    test('unsupported platforms report off and never throw on reconcile',
        () async {
      final store =
          ConfigStore(File('${dir.path}/config.json'), defaultDeviceName: 'PC');
      await store.load();
      const auto = UnsupportedAutoStart();
      expect(await auto.isEnabled(), isFalse);
      await ConfigController(store, auto).reconcile();
      expect(auto.setEnabled(true), throwsA(isA<AutoStartException>()));
    });
  });
}
