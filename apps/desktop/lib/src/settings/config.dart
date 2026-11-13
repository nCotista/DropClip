import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum SyncType { text, url, image }

enum AppLanguage { th, en }

/// `config.json` (PROTO-DC-V2.0 §15.6, E-06, FR-12). `language` (NFR-L01)
/// and `first_run_done` (§3.1 firewall onboarding) are additions that
/// §15.6 does not list yet.
@immutable
class AppConfig {
  static const int version = 1;

  final String deviceName;
  final bool autoAccept;
  final String destinationDir;
  final bool clipboardSyncEnabled;
  final Set<SyncType> syncTypes;

  /// `null` = never clear the received clipboard.
  final int? clipboardTtlSeconds;
  final bool autoStart;
  final String logLevel;
  final AppLanguage language;

  /// The first-run firewall explanation was dismissed.
  final bool firstRunDone;

  /// Opt-in flag enabling the local HTTPS `/web` browser companion.
  final bool webCompanionEnabled;

  const AppConfig({
    required this.deviceName,
    this.autoAccept = false,
    this.destinationDir = '~/Downloads/DropClip',
    this.clipboardSyncEnabled = true,
    this.syncTypes = const {SyncType.text, SyncType.url, SyncType.image},
    this.clipboardTtlSeconds,
    this.autoStart = true,
    this.logLevel = 'info',
    this.language = AppLanguage.th,
    this.firstRunDone = false,
    this.webCompanionEnabled = false,
  });

  static const _logLevels = {'debug', 'info', 'warn', 'error'};

  /// [destinationDir] as an absolute directory, expanding a leading `~`.
  Directory get destinationDirectory => resolveDestinationDirectory(
      Platform.environment, isWindows: Platform.isWindows);

  /// Resolves [destinationDir] against [env] without leaving relative `~` paths.
  @visibleForTesting
  Directory resolveDestinationDirectory(Map<String, String> env,
      {bool? isWindows}) {
    final win = isWindows ?? Platform.isWindows;
    final sep = win ? r'\' : '/';
    var path = destinationDir.trim();
    if (path.isEmpty ||
        (path.startsWith('~') &&
            path != '~' &&
            !path.startsWith('~/') &&
            !path.startsWith(r'~\'))) {
      path = '~/Downloads/DropClip';
    }
    if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
      final home = (win ? env['USERPROFILE'] : env['HOME'])?.trim();
      if (home != null && home.isNotEmpty) {
        final base = home.endsWith('/') || home.endsWith(r'\')
            ? home.substring(0, home.length - 1)
            : home;
        final rest = path.substring(1);
        path = '$base${win ? rest.replaceAll('/', r'\') : rest}';
      } else {
        final temp = Directory.systemTemp.path;
        final tempBase = temp.endsWith('/') || temp.endsWith(r'\')
            ? temp.substring(0, temp.length - 1)
            : temp;
        final rest = path.length > 2 ? path.substring(2) : 'DropClip';
        path = '$tempBase$sep${win ? rest.replaceAll('/', r'\') : rest}';
      }
    }
    return Directory(path);
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'device_name': deviceName,
        'auto_accept': autoAccept,
        'destination_dir': destinationDir,
        'clipboard_sync_enabled': clipboardSyncEnabled,
        'sync_types': [
          for (final t in SyncType.values)
            if (syncTypes.contains(t)) t.name
        ],
        'clipboard_ttl_seconds': clipboardTtlSeconds,
        'auto_start': autoStart,
        'log_level': logLevel,
        'language': language.name,
        'first_run_done': firstRunDone,
        'web_companion_enabled': webCompanionEnabled,
      };

  /// Invalid or missing values fall back to the default; each one is
  /// reported to [onWarn] (§15.6: "ใช้ค่า default และ log `warn`").
  factory AppConfig.fromJson(Map<String, Object?> json,
      {required String defaultDeviceName, void Function(String)? onWarn}) {
    final d = AppConfig(deviceName: defaultDeviceName);
    T pick<T>(String key, T fallback, bool Function(T) valid) {
      final v = json[key];
      if (v == null && !json.containsKey(key)) return fallback;
      if (v is T && valid(v)) return v;
      onWarn?.call('config: invalid "$key", using default');
      return fallback;
    }

    final types = json['sync_types'];
    Set<SyncType>? parsedTypes;
    if (types is List &&
        types.every((t) => SyncType.values.any((s) => s.name == t))) {
      parsedTypes = {
        for (final t in types) SyncType.values.byName(t as String)
      };
    } else if (json.containsKey('sync_types')) {
      onWarn?.call('config: invalid "sync_types", using default');
    }
    final ttl = json['clipboard_ttl_seconds'];
    final ttlOk = ttl == null || (ttl is int && ttl > 0);
    if (!ttlOk) {
      onWarn?.call('config: invalid "clipboard_ttl_seconds", using default');
    }
    final lang = json['language'];
    final langOk = AppLanguage.values.any((l) => l.name == lang);
    if (lang != null && !langOk) {
      onWarn?.call('config: invalid "language", using default');
    }

    return AppConfig(
      deviceName:
          pick<String>('device_name', d.deviceName, (s) => s.trim().isNotEmpty),
      autoAccept: pick<bool>('auto_accept', d.autoAccept, (_) => true),
      destinationDir: pick<String>('destination_dir', d.destinationDir, (s) {
        final t = s.trim();
        if (t.isEmpty) return false;
        if (t.startsWith('~') &&
            t != '~' &&
            !t.startsWith('~/') &&
            !t.startsWith(r'~\')) {
          return false;
        }
        return true;
      }),
      clipboardSyncEnabled: pick<bool>(
          'clipboard_sync_enabled', d.clipboardSyncEnabled, (_) => true),
      syncTypes: parsedTypes ?? d.syncTypes,
      clipboardTtlSeconds: ttlOk ? ttl as int? : d.clipboardTtlSeconds,
      autoStart: pick<bool>('auto_start', d.autoStart, (_) => true),
      logLevel: pick<String>('log_level', d.logLevel, _logLevels.contains),
      language: langOk ? AppLanguage.values.byName(lang as String) : d.language,
      firstRunDone: pick<bool>('first_run_done', d.firstRunDone, (_) => true),
      webCompanionEnabled: pick<bool>(
          'web_companion_enabled', d.webCompanionEnabled, (_) => true),
    );
  }

  AppConfig copyWith({
    String? deviceName,
    bool? autoAccept,
    String? destinationDir,
    bool? clipboardSyncEnabled,
    Set<SyncType>? syncTypes,
    int? Function()? clipboardTtlSeconds,
    bool? autoStart,
    AppLanguage? language,
    bool? firstRunDone,
    bool? webCompanionEnabled,
  }) =>
      AppConfig(
        deviceName: deviceName ?? this.deviceName,
        autoAccept: autoAccept ?? this.autoAccept,
        destinationDir: destinationDir ?? this.destinationDir,
        clipboardSyncEnabled: clipboardSyncEnabled ?? this.clipboardSyncEnabled,
        syncTypes: syncTypes ?? this.syncTypes,
        clipboardTtlSeconds: clipboardTtlSeconds != null
            ? clipboardTtlSeconds()
            : this.clipboardTtlSeconds,
        autoStart: autoStart ?? this.autoStart,
        logLevel: logLevel,
        language: language ?? this.language,
        firstRunDone: firstRunDone ?? this.firstRunDone,
        webCompanionEnabled: webCompanionEnabled ?? this.webCompanionEnabled,
      );
}

/// Loads and saves `config.json`; [config] notifies listeners so a change
/// applies without restarting (§15.6).
class ConfigStore {
  final File file;
  final String defaultDeviceName;
  final void Function(String)? onWarn;
  final ValueNotifier<AppConfig> config;

  ConfigStore(this.file, {required this.defaultDeviceName, this.onWarn})
      : config = ValueNotifier(AppConfig(deviceName: defaultDeviceName));

  /// `%APPDATA%\DropClip\config.json` on Windows,
  /// `~/Library/Application Support/DropClip/config.json` on macOS.
  static File defaultFile(Map<String, String> env, {required bool isMacOS}) {
    final dir = isMacOS
        ? '${env['HOME']}/Library/Application Support/DropClip'
        : '${env['APPDATA']}\\DropClip';
    return File(isMacOS ? '$dir/config.json' : '$dir\\config.json');
  }

  /// Reads the file; a missing or corrupt file yields defaults.
  Future<AppConfig> load() async {
    AppConfig loaded;
    try {
      final json = jsonDecode(await file.readAsString());
      loaded = json is Map<String, Object?>
          ? AppConfig.fromJson(json,
              defaultDeviceName: defaultDeviceName, onWarn: onWarn)
          : AppConfig(deviceName: defaultDeviceName);
      if (json is! Map) onWarn?.call('config: not an object, using defaults');
    } on PathNotFoundException {
      loaded = AppConfig(deviceName: defaultDeviceName);
    } on FormatException {
      onWarn?.call('config: unreadable JSON, using defaults');
      loaded = AppConfig(deviceName: defaultDeviceName);
    }
    return config.value = loaded;
  }

  /// Writes atomically (temp file + rename) so a crash never leaves a
  /// half-written config, then applies it.
  Future<void> save(AppConfig next) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(next.toJson()),
        flush: true);
    await tmp.rename(file.path);
    config.value = next;
  }
}
