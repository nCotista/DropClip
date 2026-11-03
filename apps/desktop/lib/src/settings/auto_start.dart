import 'dart:io';

import 'config.dart';

/// Runs a process; injectable for tests.
typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Launch-at-login registration (FR-12). Started with `--hidden`, the app
/// stays in the tray (NFR-U03).
abstract interface class AutoStart {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool enabled);
}

class AutoStartException implements Exception {
  final String message;
  const AutoStartException(this.message);
  @override
  String toString() => 'AutoStartException: $message';
}

/// Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (FR-12),
/// written with the system `reg.exe` so no plugin is needed. Per-user, so no
/// admin rights.
class WindowsRunKeyAutoStart implements AutoStart {
  static const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const valueName = 'DropClip';

  final String executablePath;
  final ProcessRunner _run;

  WindowsRunKeyAutoStart(this.executablePath, {ProcessRunner? run})
      : _run = run ?? ((exe, args) => Process.run(exe, args));

  String get command => '"$executablePath" --hidden';

  @override
  Future<bool> isEnabled() async {
    final r = await _run('reg', ['query', key, '/v', valueName]);
    // Only our own command counts; a stale path from an old install does not.
    return r.exitCode == 0 && '${r.stdout}'.contains(command);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final r = enabled
        ? await _run('reg',
            ['add', key, '/v', valueName, '/t', 'REG_SZ', '/d', command, '/f'])
        : await _run('reg', ['delete', key, '/v', valueName, '/f']);
    // Deleting a value that is not there is fine.
    if (r.exitCode != 0 && (enabled || await isEnabled())) {
      throw AutoStartException('reg exited ${r.exitCode}: ${r.stderr}');
    }
  }
}

/// macOS needs `SMAppService` (13+) / a LaunchAgent (12) from native code,
/// which is not written yet; reports off and refuses to change.
class UnsupportedAutoStart implements AutoStart {
  const UnsupportedAutoStart();

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<void> setEnabled(bool enabled) async =>
      throw const AutoStartException('auto-start is not available here yet');
}

/// Applies config changes that have side effects outside the app, then
/// saves. If the OS refuses, the old config is kept (FR-12: "ระบบทำงาน
/// สอดคล้องกับการตั้งค่า").
class ConfigController {
  final ConfigStore store;
  final AutoStart autoStart;

  ConfigController(this.store, this.autoStart);

  Future<void> update(AppConfig next) async {
    if (next.autoStart != store.config.value.autoStart) {
      await autoStart.setEnabled(next.autoStart);
    }
    await store.save(next);
  }

  /// Makes the OS registration match the loaded config (e.g. after the app
  /// moved, or on first run where `auto_start` defaults to true).
  Future<void> reconcile() async {
    final want = store.config.value.autoStart;
    try {
      if (await autoStart.isEnabled() != want) {
        await autoStart.setEnabled(want);
      }
    } on AutoStartException {
      // Not fatal: the app runs; the Settings page shows the real state.
    }
  }
}
