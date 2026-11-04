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

/// macOS: a per-user LaunchAgent, `~/Library/LaunchAgents/<label>.plist`,
/// that starts the app with `--hidden` at login (FR-12, NFR-U03). Used on
/// macOS 12 and 13+ alike: `SMAppService.mainApp` (13+) cannot pass
/// `--hidden`, so a login launch would open the window. Per-user, no admin
/// rights, no native code; launchd reads it at the next login.
class MacLaunchAgentAutoStart implements AutoStart {
  static const label = 'dev.dropclip.dropclipDesktop.login';

  final String executablePath;
  final Directory launchAgents;

  MacLaunchAgentAutoStart(this.executablePath, {required String home})
      : launchAgents = Directory('$home/Library/LaunchAgents');

  File get plist => File('${launchAgents.path}/$label.plist');

  String get _program => '<string>${_xml(executablePath)}</string>';

  String get plistContent => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    $_program
    <string>--hidden</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
</dict>
</plist>
''';

  @override
  Future<bool> isEnabled() async {
    try {
      // Only our own path counts; a stale one from an old install does not.
      return plist.existsSync() && plist.readAsStringSync().contains(_program);
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      if (!enabled) {
        if (plist.existsSync()) plist.deleteSync();
        return;
      }
      launchAgents.createSync(recursive: true);
      final tmp = File('${plist.path}.tmp')..writeAsStringSync(plistContent);
      tmp.renameSync(plist.path);
    } on FileSystemException catch (e) {
      throw AutoStartException('LaunchAgent: ${e.message}');
    }
  }

  static String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// For platforms without auto-start: reports off and refuses to change.
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
