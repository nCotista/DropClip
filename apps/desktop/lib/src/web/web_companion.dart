import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dropclip_protocol/dropclip_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// A phone browser linked by scanning the desktop's web QR.
class WebSession {
  final String id;
  final String name;
  final DateTime since;
  final DateTime expiresAt;
  DateTime lastSeen;

  WebSession(this.id, this.name, this.since, this.expiresAt)
      : lastSeen = since;
}

/// A clip shown to linked browsers.
typedef WebClip = ({int id, String text, String from, int at});

/// Opt-in browser companion for phones without the app (Tier 3 web), at `/web`.
class WebCompanion {
  static const int _maxClaimBytes = 4 * 1024;
  static const int _maxClipJsonBytes = 2 << 20;
  static final _ctrlOrBidi =
      RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]');

  final Directory downloads;
  final String page;
  final Future<void> Function(String text) writeClipboard;
  final void Function(String text, String from)? onReceived;
  final bool Function() isEnabled;
  final Duration codeTtl;
  final Duration sessionTtl;
  final DateTime Function() now;

  final sessions = ValueNotifier<List<WebSession>>(const []);
  final _codes = <String, DateTime>{};
  final _tokens = <String, WebSession>{};
  final _clips = <WebClip>[];
  final _outbox = <String, ({File file, String name, String session})>{};
  final _claims = <DateTime>[];
  final _rng = Random.secure();
  int _nextClip = 1;

  WebCompanion({
    required this.downloads,
    required this.page,
    required this.writeClipboard,
    this.onReceived,
    bool Function()? isEnabled,
    bool enabled = false,
    this.codeTtl = const Duration(minutes: 2),
    this.sessionTtl = const Duration(hours: 8),
    DateTime Function()? now,
  })  : isEnabled = isEnabled ?? (() => enabled),
        now = now ?? DateTime.now;

  /// A new one-time link code for the QR.
  String newCode() {
    if (!isEnabled()) throw StateError('Web companion is disabled');
    _pruneExpired();
    final code = _random(12);
    _codes[code] = now().add(codeTtl);
    return code;
  }

  /// Shows [text] in linked browsers (clipboard history, newest last).
  void addClip(String text, String from) {
    if (!isEnabled()) return;
    _clips.add((
      id: _nextClip++,
      text: text,
      from: from,
      at: now().millisecondsSinceEpoch,
    ));
    if (_clips.length > 50) _clips.removeAt(0);
  }

  /// Makes [files] downloadable by browser [sessionId].
  void offer(String sessionId, List<File> files) {
    _pruneExpired();
    if (!isEnabled() || !_tokens.values.any((s) => s.id == sessionId)) return;
    for (final f in files) {
      _outbox[_random(16)] =
          (file: f, name: f.uri.pathSegments.last, session: sessionId);
    }
  }

  void revoke(String sessionId) {
    _tokens.removeWhere((_, s) => s.id == sessionId);
    _outbox.removeWhere((_, o) => o.session == sessionId);
    _publish();
  }

  /// Clears all codes, active browser sessions, and queued downloads.
  void revokeAll() {
    if (_codes.isEmpty && _tokens.isEmpty && _outbox.isEmpty) return;
    _codes.clear();
    _tokens.clear();
    _outbox.clear();
    _publish();
  }

  Handler get handler => (Request r) async {
        _pruneExpired();
        if (!isEnabled()) return _json(404, {'error': 'disabled'});
        final path = r.url.path;
        if (path == 'web' || path == 'web/') {
          return Response.ok(page, headers: const {
            'content-type': 'text/html; charset=utf-8',
            'cache-control': 'no-store',
            'referrer-policy': 'no-referrer',
          });
        }
        if (path == 'web/api/claim' && r.method == 'POST') return _claim(r);
        final token = r.headers['x-dropclip-token'] ?? '';
        final s = _tokens[sha256.convert(utf8.encode(token)).toString()];
        if (s == null) return _json(401, {'error': 'not linked'});
        s.lastSeen = now();
        return switch ((r.method, path)) {
          ('GET', 'web/api/state') => await _state(r, s),
          ('POST', 'web/api/clip') => await _clip(r, s),
          ('POST', 'web/api/upload') => await _upload(r, s),
          ('GET', _) when path.startsWith('web/api/file/') =>
            await _download(path.substring('web/api/file/'.length), s),
          _ => _json(404, {'error': 'unknown'}),
        };
      };

  void _pruneExpired() {
    final t = now();
    _codes.removeWhere((_, exp) => t.isAfter(exp));
    final expiredIds = <String>{};
    _tokens.removeWhere((_, s) {
      final expired = !t.isBefore(s.expiresAt);
      if (expired) expiredIds.add(s.id);
      return expired;
    });
    if (expiredIds.isNotEmpty) {
      _outbox.removeWhere((_, o) => expiredIds.contains(o.session));
      _publish();
    }
  }

  Future<({Uint8List? bytes, Response? error})> _readLimited(
      Request r, int maxBytes) async {
    final len = r.contentLength;
    if (len != null && len > maxBytes) {
      return (bytes: null, error: _json(413, {'error': 'too large'}));
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in r.read()) {
      if (b.length + chunk.length > maxBytes) {
        return (bytes: null, error: _json(413, {'error': 'too large'}));
      }
      b.add(chunk);
    }
    return (bytes: b.takeBytes(), error: null);
  }

  Future<({Map<String, Object?>? json, Response? error})> _readJson(
      Request r, int maxBytes) async {
    final raw = await _readLimited(r, maxBytes);
    if (raw.error != null) return (json: null, error: raw.error);
    try {
      final decoded = jsonDecode(utf8.decode(raw.bytes!));
      if (decoded is! Map<String, Object?>) {
        return (json: null, error: _json(400, {'error': 'invalid json'}));
      }
      return (json: decoded, error: null);
    } on FormatException {
      return (json: null, error: _json(400, {'error': 'invalid json'}));
    }
  }

  Future<Response> _claim(Request r) async {
    final t = now();
    _claims.removeWhere((c) => t.difference(c) > const Duration(minutes: 1));
    if (_claims.length >= 10) return _json(429, {'error': 'slow down'});
    _claims.add(t);
    final parsed = await _readJson(r, _maxClaimBytes);
    if (parsed.error != null) return parsed.error!;
    final body = parsed.json!;
    final code = body['code'];
    if (code is! String || code.isEmpty) {
      return _json(400, {'error': 'missing code'});
    }
    final expiry = _codes.remove(code);
    if (expiry == null || t.isAfter(expiry)) {
      return _json(401, {'error': 'code expired, scan again'});
    }
    final rawName = body['name'];
    final clean = rawName is String
        ? rawName.replaceAll(_ctrlOrBidi, '').trim()
        : 'Phone';
    final safeName = clean.isEmpty
        ? 'Phone'
        : (clean.length > 64 ? clean.substring(0, 64) : clean);
    final token = _random(32);
    final expiresAt = t.add(sessionTtl);
    final s = WebSession(_random(8), safeName, t, expiresAt);
    _tokens[sha256.convert(utf8.encode(token)).toString()] = s;
    _publish();
    return _json(200, {
      'token': token,
      'session': s.id,
      'expires_at': expiresAt.millisecondsSinceEpoch,
    });
  }

  Future<Response> _state(Request r, WebSession s) async {
    final after = int.tryParse(r.url.queryParameters['after'] ?? '') ?? 0;
    final files = <Map<String, Object?>>[];
    for (final e in _outbox.entries.toList()) {
      if (e.value.session != s.id) continue;
      final st = await e.value.file.stat();
      if (st.type != FileSystemEntityType.file) {
        _outbox.remove(e.key);
        continue;
      }
      files.add({'id': e.key, 'name': e.value.name, 'size': st.size});
    }
    return _json(200, {
      'clips': [
        for (final c in _clips)
          if (c.id > after)
            {'id': c.id, 'text': c.text, 'from': c.from, 'at': c.at}
      ],
      'files': files,
    });
  }

  Future<Response> _clip(Request r, WebSession s) async {
    final parsed = await _readJson(r, _maxClipJsonBytes);
    if (parsed.error != null) return parsed.error!;
    final rawText = parsed.json!['text'];
    if (rawText is! String || rawText.isEmpty || rawText.length > 1 << 20) {
      return _json(400, {'error': 'empty or too long'});
    }
    await writeClipboard(rawText);
    addClip(rawText, s.name);
    onReceived?.call(rawText, s.name);
    return _json(200, {'ok': true});
  }

  File _inDownloads(String leaf) =>
      File('${downloads.path}${Platform.pathSeparator}$leaf');

  static String? _sanitizeUploadName(String? raw) {
    if (raw == null) return 'file';
    final leaf = raw.split(RegExp(r'[\\/]')).last;
    try {
      final clean = PathSanitizer.sanitize(leaf);
      return clean.startsWith('.')
          ? PathSanitizer.sanitize('file$clean')
          : clean;
    } on InvalidPathException {
      return null;
    }
  }

  /// Stages uploads in a `.part` file before atomic rename; cleans up errors.
  Future<Response> _upload(Request r, WebSession s) async {
    final name = _sanitizeUploadName(r.url.queryParameters['name']);
    if (name == null) return _json(400, {'error': 'invalid file name'});
    await downloads.create(recursive: true);
    final part = _inDownloads('.${_random(12)}.part');
    final sink = part.openWrite();
    var closed = false;
    var promoted = false;
    try {
      await sink.addStream(r.read());
      await sink.flush();
      await sink.close();
      closed = true;
      var saved = name;
      var target = _inDownloads(saved);
      for (var i = 1; await target.exists(); i++) {
        saved = '($i) $name';
        target = _inDownloads(saved);
      }
      await part.rename(target.path);
      promoted = true;
      onReceived?.call('📎 $saved', s.name);
      return _json(200, {'saved': saved});
    } on Object {
      return _json(500, {'error': 'upload failed'});
    } finally {
      if (!closed) {
        try {
          await sink.close();
        } on Object {
          // Stream error already handled; continue removing `.part`.
        }
      }
      if (!promoted && await part.exists()) {
        await part.delete().catchError((Object _) => part);
      }
    }
  }

  Future<Response> _download(String id, WebSession s) async {
    final o = _outbox[id];
    if (o == null || o.session != s.id) return _json(404, {'error': 'gone'});
    final st = await o.file.stat();
    if (st.type != FileSystemEntityType.file) {
      _outbox.remove(id);
      return _json(404, {'error': 'gone'});
    }
    return Response.ok(o.file.openRead(), headers: {
      'content-type': 'application/octet-stream',
      'content-length': '${st.size}',
      'content-disposition':
          "attachment; filename*=UTF-8''${Uri.encodeComponent(o.name)}",
    });
  }

  void _publish() => sessions.value = _tokens.values.toList();

  String _random(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _rng.nextInt(256)))
      .replaceAll('=', '');

  static Response _json(int status, Map<String, Object?> body) => Response(
        status,
        body: jsonEncode(body),
        headers: const {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
}
