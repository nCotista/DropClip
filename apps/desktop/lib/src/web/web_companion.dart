import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// A phone browser linked by scanning the desktop's web QR.
class WebSession {
  final String id;
  final String name;
  final DateTime since;
  DateTime lastSeen;

  WebSession(this.id, this.name, this.since) : lastSeen = since;
}

/// A clip shown to linked browsers.
typedef WebClip = ({int id, String text, String from, int at});

/// Browser companion for phones without the app, e.g. iPhone without a Mac
/// to build it (Tier 3 web). Served at `/web` on the desktop's TLS server.
///
/// Browsers cannot do the §4 mTLS, so a QR carries a one-time code (valid
/// [codeTtl]) that `POST /web/api/claim` swaps for a random 256-bit token;
/// only its SHA-256 is kept here and every API call sends it in
/// `x-dropclip-token`. Removing a session revokes its token at once.
class WebCompanion {
  final Directory downloads;
  final String page;

  /// Text a browser sent, with the browser's name (onto the PC clipboard,
  /// its history and paired peers; the host also echoes it back via
  /// [addClip]).
  final Future<void> Function(String text, String from) onText;
  final void Function(String text, String from)? onReceived;
  final Duration codeTtl;
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
    required this.onText,
    this.onReceived,
    this.codeTtl = const Duration(minutes: 2),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// A new one-time link code for the QR.
  String newCode() {
    final code = _random(12);
    _codes[code] = now().add(codeTtl);
    return code;
  }

  /// Shows [text] in linked browsers (clipboard history, newest last).
  void addClip(String text, String from) {
    _clips.add((
      id: _nextClip++,
      text: text,
      from: from,
      at: now().millisecondsSinceEpoch
    ));
    if (_clips.length > 50) _clips.removeAt(0);
  }

  /// Makes [files] downloadable by browser [sessionId].
  void offer(String sessionId, List<File> files) {
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

  Handler get handler => (Request r) async {
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
          ('GET', 'web/api/state') => _state(r, s),
          ('POST', 'web/api/clip') => await _clip(r, s),
          ('POST', 'web/api/upload') => await _upload(r, s),
          ('GET', _) when path.startsWith('web/api/file/') =>
            _download(path.substring('web/api/file/'.length), s),
          _ => _json(404, {'error': 'unknown'}),
        };
      };

  Future<Response> _claim(Request r) async {
    final t = now();
    _claims.removeWhere((c) => t.difference(c) > const Duration(minutes: 1));
    if (_claims.length >= 10) return _json(429, {'error': 'slow down'});
    _claims.add(t);
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final expiry = _codes.remove(body['code']);
    if (expiry == null || t.isAfter(expiry)) {
      return _json(401, {'error': 'code expired, scan again'});
    }
    final token = _random(32);
    final name = (body['name'] as String? ?? 'Phone').trim();
    final s = WebSession(_random(8), name.isEmpty ? 'Phone' : name, t);
    _tokens[sha256.convert(utf8.encode(token)).toString()] = s;
    _publish();
    return _json(200, {'token': token, 'session': s.id});
  }

  Response _state(Request r, WebSession s) {
    final after = int.tryParse(r.url.queryParameters['after'] ?? '') ?? 0;
    return _json(200, {
      'clips': [
        for (final c in _clips)
          if (c.id > after)
            {'id': c.id, 'text': c.text, 'from': c.from, 'at': c.at}
      ],
      'files': [
        for (final e in _outbox.entries)
          if (e.value.session == s.id)
            {
              'id': e.key,
              'name': e.value.name,
              'size': e.value.file.lengthSync()
            }
      ],
    });
  }

  Future<Response> _clip(Request r, WebSession s) async {
    final body = jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    final text = body['text'] as String? ?? '';
    if (text.isEmpty || text.length > 1 << 20) {
      return _json(400, {'error': 'empty or too long'});
    }
    await onText(text, s.name);
    return _json(200, {'ok': true});
  }

  /// Streams the body into Downloads/DropClip (never held in memory).
  Future<Response> _upload(Request r, WebSession s) async {
    final raw = r.url.queryParameters['name'] ?? 'file';
    final base = raw
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
    final name = base.isEmpty || base.startsWith('.') ? 'file$base' : base;
    await downloads.create(recursive: true);
    var target = File('${downloads.path}/$name');
    for (var i = 1; await target.exists(); i++) {
      target = File('${downloads.path}/($i) $name');
    }
    final sink = target.openWrite();
    try {
      await sink.addStream(r.read());
    } finally {
      await sink.close();
    }
    onReceived?.call('📎 ${target.uri.pathSegments.last}', s.name);
    return _json(200, {'saved': target.uri.pathSegments.last});
  }

  Response _download(String id, WebSession s) {
    final o = _outbox[id];
    if (o == null || o.session != s.id) return _json(404, {'error': 'gone'});
    return Response.ok(o.file.openRead(), headers: {
      'content-type': 'application/octet-stream',
      'content-length': '${o.file.lengthSync()}',
      'content-disposition':
          "attachment; filename*=UTF-8''${Uri.encodeComponent(o.name)}",
    });
  }

  void _publish() => sessions.value = _tokens.values.toList();

  String _random(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _rng.nextInt(256)))
      .replaceAll('=', '');

  static Response _json(int status, Map<String, dynamic> body) => Response(
        status,
        body: jsonEncode(body),
        headers: const {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
}
