import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dropclip_clipboard/dropclip_clipboard.dart';
import 'package:dropclip_core/dropclip_core.dart';
import 'package:dropclip_desktop/src/web/web_companion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  late Directory dir;
  late WebCompanion web;
  late TlsTransportServer server;
  late HttpClient browser;
  final written = <String>[];
  final images = <int>[];
  var clock = DateTime(2026, 11, 12, 10);
  var enabled = true;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dc_web_');
    written.clear();
    images.clear();
    enabled = true;
    web = WebCompanion(
      downloads: Directory('${dir.path}/Downloads'),
      page: '<title>DropClip</title>',
      onImage: (png, from) async => images.add(png.length),
      onText: (t, from) async {
        written.add(t);
        web.addClip(t, from);
      },
      isEnabled: () => enabled,
      now: () => clock,
    );
    final id = P256.generate(commonName: 'dropclip-test');
    server = await TlsTransportServer.bind(
      context: buildTls13Context(certPem: id.certPem, keyPem: id.keyPem),
      isTrusted: (_) => false,
      pinnedHandler: (_) => Response.forbidden(null),
      webHandler: web.handler,
      address: InternetAddress.loopbackIPv4,
      firstPort: 0,
      lastPort: 0,
    );
    browser = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (_, __, ___) => true;
  });

  tearDown(() async {
    browser.close(force: true);
    await server.close(force: true);
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });

  Future<({int status, String body})> call(String method, String path,
      {String? token, Object? json, String? raw, List<int>? bytes}) async {
    final req = await browser.openUrl(
        method, Uri.parse('https://127.0.0.1:${server.port}$path'));
    if (token != null) req.headers.set('x-dropclip-token', token);
    if (json != null) req.add(utf8.encode(jsonEncode(json)));
    if (raw != null) req.add(utf8.encode(raw));
    if (bytes != null) req.add(bytes);
    final res = await req.close();
    return (
      status: res.statusCode,
      body: utf8.decode(await res.fold<List<int>>([], (a, b) => a..addAll(b))),
    );
  }

  Future<String> link() async {
    final r = await call('POST', '/web/api/claim',
        json: {'code': web.newCode(), 'name': 'iPhone'});
    expect(r.status, 200);
    return (jsonDecode(r.body) as Map<String, Object?>)['token'] as String;
  }

  test('opt-in off by default and refuses requests once disabled', () async {
    final off =
        WebCompanion(downloads: dir, page: 'x', onText: (_, __) async {});
    expect(off.isEnabled(), isFalse);
    expect(() => off.newCode(), throwsStateError);
    final r = await off.handler(Request('GET', Uri.parse('https://x/web')));
    expect(r.statusCode, 404);
    final token = await link();
    enabled = false;
    web.revokeAll();
    expect((await call('GET', '/web')).status, 404);
    expect((await call('GET', '/web/api/state', token: token)).status, 404);
  });

  test('auth, one-time codes, size caps and session expiry', () async {
    expect((await call('GET', '/web')).body, contains('DropClip'));
    expect((await call('GET', '/web/api/state')).status, 401);
    expect((await call('GET', '/api/v1/info')).status, 403);
    final code = web.newCode();
    expect((await call('POST', '/web/api/claim', json: {'code': code})).status,
        200);
    expect((await call('POST', '/web/api/claim', json: {'code': code})).status,
        401);
    final late = web.newCode();
    clock = clock.add(const Duration(minutes: 3));
    expect((await call('POST', '/web/api/claim', json: {'code': late})).status,
        401);
    final token = await link();
    final tooBig = '{"c":"${'x' * 5000}"}';
    expect((await call('POST', '/web/api/claim', raw: tooBig)).status, 413);
    clock = clock.add(const Duration(hours: 9));
    expect((await call('GET', '/web/api/state', token: token)).status, 401);
    expect(web.sessions.value, isEmpty);
  });

  test('phone <-> PC, validation, .part cleanup and missing files', () async {
    final token = await link();
    expect(web.sessions.value.single.name, 'iPhone');
    await call('POST', '/web/api/clip', token: token, json: {'text': 'สวัสดี'});
    expect(written, ['สวัสดี']);
    for (final c in [
      (raw: '{', status: 400),
      (raw: '[]', status: 400),
      (raw: '{"text":"${'a' * ((2 << 20) + 1)}"}', status: 413),
    ]) {
      final r = await call('POST', '/web/api/clip', token: token, raw: c.raw);
      expect(r.status, c.status);
    }
    web.addClip('from PC', 'Laptop');
    final st = await call('GET', '/web/api/state?after=1', token: token);
    final clips =
        (jsonDecode(st.body) as Map<String, Object?>)['clips'] as List<Object?>;
    final clip0 = clips.single as Map<String, Object?>;
    expect(clip0['text'], 'from PC');
    final up = await call('POST', '/web/api/upload?name=../../evil.txt',
        token: token, bytes: utf8.encode('photo bytes'));
    expect(jsonDecode(up.body), {'saved': 'evil.txt'});
    expect(File('${dir.path}/Downloads/evil.txt').readAsStringSync(),
        'photo bytes');
    for (final bad in ['CON', 'NUL.txt', 'a\u202Eb.exe', 'dot.', '..']) {
      final path = '/web/api/upload?name=${Uri.encodeQueryComponent(bad)}';
      final r = await call('POST', path, token: token, bytes: [1]);
      expect(r.status, 400);
    }
    final abort = await web.handler(Request(
      'POST',
      Uri.parse('https://x/web/api/upload?name=abort.bin'),
      headers: {'x-dropclip-token': token},
      body: Stream<List<int>>.error(StateError('drop')),
    ));
    expect(abort.statusCode, 500);
    final dlEntries = Directory('${dir.path}/Downloads').listSync();
    expect(dlEntries.where((e) => e.path.endsWith('.part')), isEmpty);
    final pcFile = File('${dir.path}/report.pdf')..writeAsStringSync('pdf');
    final gone = File('${dir.path}/gone.pdf')..writeAsStringSync('x');
    web.offer(web.sessions.value.single.id, [pcFile, gone]);
    gone.deleteSync();
    final stateRes = await call('GET', '/web/api/state', token: token);
    final files = (jsonDecode(stateRes.body) as Map<String, Object?>)['files']
        as List<Object?>;
    expect(files, hasLength(1));
    final fid = (files.single as Map<String, Object?>)['id'] as String;
    expect((await call('GET', '/web/api/file/$fid', token: token)).body, 'pdf');
    pcFile.deleteSync();
    expect((await call('GET', '/web/api/file/$fid', token: token)).status, 404);
    web.revoke(web.sessions.value.single.id);
    expect((await call('GET', '/web/api/state', token: token)).status, 401);
  });

  test('a freshly linked browser never sees pre-link clipboard history',
      () async {
    // Copied before the user scanned the QR: must stay on the PC.
    web.addClip('old password', 'Laptop');
    final token = await link();
    web.addClip('copied after linking', 'Laptop');

    final st = await call('GET', '/web/api/state?after=0', token: token);
    final clips =
        (jsonDecode(st.body) as Map<String, Object?>)['clips'] as List<Object?>;
    expect([for (final c in clips) (c as Map<String, Object?>)['text']],
        ['copied after linking']);
  });

  test('unlink revokes the token on the desktop, not only in the browser',
      () async {
    final token = await link();
    expect((await call('GET', '/web/api/state', token: token)).status, 200);
    expect((await call('POST', '/web/api/unlink', token: token)).status, 200);
    expect((await call('GET', '/web/api/state', token: token)).status, 401);
    expect(web.sessions.value, isEmpty);
  });

  test('images: PNG goes to the PC clipboard, anything else is refused',
      () async {
    final token = await link();
    final png = encodePng(RgbaImage(4, 4, Uint8List(64)));
    final ok = await call('POST', '/web/api/image', token: token, bytes: png);
    expect(ok.status, 200);
    expect(images, [png.length]);
    final bad = await call('POST', '/web/api/image',
        token: token, bytes: utf8.encode('jpeg?'));
    expect(bad.status, 415);
    final corrupt = await call('POST', '/web/api/image',
        token: token, bytes: [...png]..[16] ^= 1);
    expect(corrupt.status, 415);
    expect(images, [png.length]);
    final noTok = await call('POST', '/web/api/image', bytes: png);
    expect(noTok.status, 401);
  });
}
