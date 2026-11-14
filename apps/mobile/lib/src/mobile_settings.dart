import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What the phone's Settings page changes, kept in `settings.json`.
@immutable
class MobileSettings {
  /// `en` or `th`.
  final String language;

  /// Off: clips are neither sent nor received.
  final bool syncEnabled;

  const MobileSettings({this.language = 'en', this.syncEnabled = true});

  MobileSettings copyWith({String? language, bool? syncEnabled}) =>
      MobileSettings(
          language: language ?? this.language,
          syncEnabled: syncEnabled ?? this.syncEnabled);

  Map<String, Object?> toJson() =>
      {'language': language, 'sync_enabled': syncEnabled};

  factory MobileSettings.fromJson(Map<String, Object?> j) => MobileSettings(
      language: j['language'] == 'th' ? 'th' : 'en',
      syncEnabled: j['sync_enabled'] != false);

  /// Reads [file]; a missing or broken file gives the defaults.
  static Future<MobileSettings> load(File file) async {
    try {
      final j = jsonDecode(await file.readAsString());
      if (j is Map<String, Object?>) return MobileSettings.fromJson(j);
    } on Object {
      // First run or a damaged file: start from defaults.
    }
    return const MobileSettings();
  }

  static final _writeQueues = <String, Future<void>>{};

  /// Persists settings atomically (`tmp` + rename) through a per-path queue
  /// so rapid toggles never interleave or leave truncated JSON.
  Future<void> save(File file) {
    final prev = _writeQueues[file.path] ?? Future<void>.value();
    final next = prev.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      try {
        await tmp.writeAsString(jsonEncode(toJson()), flush: true);
        await tmp.rename(file.path);
      } on Object {
        if (await tmp.exists()) await tmp.delete();
        rethrow;
      }
    });
    _writeQueues[file.path] = next;
    return next;
  }
}
