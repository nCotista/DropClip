import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dropclip_protocol/dropclip_protocol.dart';

void main(List<String> args) {
  stdout.writeln('Running DropClip Protocol Fuzzer against attack vectors...');
  int blockedCount = 0;

  final attackVectors = [
    '../../etc/passwd',
    'photos/../../secret.txt',
    '/etc/passwd',
    'C:/Windows/System32/evil.dll',
    '//server/share/x',
    r'..\..\Windows\win.ini',
    'file\x00.txt',
    'CON',
    'report.',
    'a:b.txt',
    'bad\x1Bname.txt',
    'a//b',
    r'CONIN$',
    'invoice${String.fromCharCode(0x202E)}txt.exe', // RLO bidi override
  ];

  for (final vector in attackVectors) {
    try {
      PathSanitizer.sanitize(vector);
      stderr.writeln('FAILED TO BLOCK: $vector');
    } on InvalidPathException {
      blockedCount++;
    }
  }

  final rng = Random(42);
  final totalFrames = args.contains('--pentest') ? 100000 : 10000;
  int fuzzCaught = 0;
  for (var i = 0; i < totalFrames; i++) {
    final bytes = List<int>.generate(rng.nextInt(96), (_) => rng.nextInt(256));
    try {
      Envelope.decodeWire(utf8.decode(bytes, allowMalformed: true));
    } on ProtocolException {
      fuzzCaught++;
    }
  }

  stdout.writeln(
    'Fuzzer finished: Blocked $blockedCount / ${attackVectors.length} vectors; '
    'survived $fuzzCaught / $totalFrames random parser frames.',
  );
  if (blockedCount != attackVectors.length || fuzzCaught != totalFrames) {
    exitCode = 1;
  }
}
