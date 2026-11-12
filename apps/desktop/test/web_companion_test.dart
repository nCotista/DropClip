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

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dc_web_');
    written.clear();
    images.clear();
    web = WebCompanion(
        downloads: Directory('${dir.path}/Downloads'),
        page: '<title>DropClip</title>',
        onImage: (png, from) async => images.add(png.length),
        onText: (t, from) async {
          written.add(t);
          web.addClip(t, from);
        },
        now: () => clock);
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
    // Like Safari after "visit this website": no client cert, self-signed OK.
    browser = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (_, __, ___) => true;
  });

  tearDown(() async {
    browser.close(force: true);
    await server.close(force: true);
    await dir.delete(recursive: true).catchError((Object _) => dir);
  });

  Future<({int status, String body})> call(String method, String path,
      {String? token, Object? json, List<int>? bytes}) async {
    final req = await browser.openUrl(
        method, Uri.parse('https://127.0.0.1:${server.port}$path'));
    if (token != null) req.headers.set('x-dropclip-token', token);
    if (json != null) req.add(utf8.encode(jsonEncode(json)));
    if (bytes != null) req.add(bytes);
    final res = await req.close();
    return (
      status: res.statusCode,
      body: utf8.decode(await res.fold<List<int>>([], (a, b) => a..addAll(b)))
    );
  }

  Future<String> link() async {
    final r = await call('POST', '/web/api/claim',
        json: {'code': web.newCode(), 'name': 'iPhone'});
    expect(r.status, 200);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  test('the page loads without a client cert; the API needs a token', () async {
    expect((await call('GET', '/web')).body, contains('DropClip'));
    expect((await call('GET', '/web/api/state')).status, 401);
    expect((await call('GET', '/web/api/state', token: 'guess')).status, 401);
    // The rest of the server still demands a paired client cert.
    expect((await call('GET', '/api/v1/info')).status, 403);
  });

  test('a link code works once and expires', () async {
    final code = web.newCode();
    expect((await call('POST', '/web/api/claim', json: {'code': code})).status,
        200);
    expect((await call('POST', '/web/api/claim', json: {'code': code})).status,
        401);
    final late = web.newCode();
    clock = clock.add(const Duration(minutes: 3));
    expect((await call('POST', '/web/api/claim', json: {'code': late})).status,
        401);
  });

  test('phone ↔ PC: text, upload and download; revoke cuts it off', () async {
    final token = await link();
    expect(web.sessions.value.single.name, 'iPhone');

    await call('POST', '/web/api/clip', token: token, json: {'text': 'สวัสดี'});
    expect(written, ['สวัสดี']);

    web.addClip('from PC', 'Laptop');
    final state = jsonDecode(
            (await call('GET', '/web/api/state?after=1', token: token)).body)
        as Map;
    expect((state['clips'] as List).single['text'], 'from PC');

    final up = await call('POST', '/web/api/upload?name=../../evil.txt',
        token: token, bytes: utf8.encode('photo bytes'));
    expect(jsonDecode(up.body)['saved'], 'evil.txt');
    expect(File('${dir.path}/Downloads/evil.txt').readAsStringSync(),
        'photo bytes');

    final pcFile = File('${dir.path}/report.pdf')..writeAsStringSync('pdf');
    web.offer(web.sessions.value.single.id, [pcFile]);
    final files =
        (jsonDecode((await call('GET', '/web/api/state', token: token)).body)
            as Map)['files'] as List;
    final got =
        await call('GET', '/web/api/file/${files.single['id']}', token: token);
    expect(got.body, 'pdf');

    web.revoke(web.sessions.value.single.id);
    expect((await call('GET', '/web/api/state', token: token)).status, 401);
  });

  test('images: PNG goes to the PC clipboard, anything else is refused',
      () async {
    final token = await link();
    final png = encodePng(RgbaImage(4, 4, Uint8List(64)));
    expect(
        (await call('POST', '/web/api/image', token: token, bytes: png)).status,
        200);
    expect(images, [png.length]);
    expect(
        (await call('POST', '/web/api/image',
                token: token, bytes: utf8.encode('jpeg?')))
            .status,
        415);
    expect((await call('POST', '/web/api/image', bytes: png)).status, 401);
  });
}
