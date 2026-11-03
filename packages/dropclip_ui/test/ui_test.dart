import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _hex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

void main() {
  group('DropClip UI Package', () {
    test('DropClipThemeTokens defines valid app name', () {
      expect(DropClipThemeTokens.appName, equals('DropClip'));
    });
  });

  group('contrastRatio (WCAG 2.x)', () {
    test('black on white is 21:1 and symmetric', () {
      const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
      expect(contrastRatio(black, white), closeTo(21, 0.01));
      expect(contrastRatio(white, black), contrastRatio(black, white));
    });

    test('identical colors are 1:1', () {
      expect(
          contrastRatio(DropClipColors.dark.accent, DropClipColors.dark.accent),
          closeTo(1, 0.0001));
    });
  });

  for (final colors in [DropClipColors.dark, DropClipColors.light]) {
    group('${colors.brightness.name} tokens (NFR-A01, T1.12 AC)', () {
      test('every foreground passes 4.5:1 on every surface', () {
        final failures = <String>[];
        for (final fg in colors.foregrounds) {
          for (final bg in colors.surfaces) {
            final r = contrastRatio(fg, bg);
            if (r < DropClipThemeTokens.minContrastRatio) {
              failures
                  .add('${_hex(fg)} on ${_hex(bg)} = ${r.toStringAsFixed(2)}');
            }
          }
        }
        expect(failures, isEmpty);
      });

      test('button label passes 4.5:1 on the accent fill', () {
        expect(contrastRatio(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(DropClipThemeTokens.minContrastRatio));
      });

      test('theme wires tokens into Material', () {
        final theme = buildDropClipTheme(colors.brightness);
        expect(theme.brightness, colors.brightness);
        expect(theme.scaffoldBackgroundColor, colors.canvas);
        expect(theme.colorScheme.primary, colors.accent);
        expect(theme.colorScheme.onSurface, colors.textPrimary);
        expect(theme.extension<DropClipColors>(), same(colors));
      });
    });
  }

  test('dark tokens match the UI design', () {
    const d = DropClipColors.dark;
    expect([d.canvas, d.surface, d.accent, d.cyan].map(_hex),
        ['#0b0b12', '#14141f', '#6e4ef5', '#22d3ee']);
  });

  test('lerp snaps between token sets', () {
    const d = DropClipColors.dark, l = DropClipColors.light;
    expect(d.lerp(l, 0.4), same(d));
    expect(d.lerp(l, 0.6), same(l));
    expect(d.lerp(null, 1), same(d));
    expect(d.copyWith(), same(d));
  });

  testWidgets('of(context) follows the platform brightness', (tester) async {
    late DropClipColors seen;
    late TextStyle mono;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(MaterialApp(
      theme: buildDropClipTheme(Brightness.light),
      darkTheme: buildDropClipTheme(Brightness.dark),
      home: Builder(builder: (context) {
        seen = DropClipColors.of(context);
        mono = dropClipMono(context, fontSize: 24);
        return const SizedBox();
      }),
    ));
    expect(seen, same(DropClipColors.light));
    expect(mono.fontFamily, DropClipFonts.mono);
    expect(mono.fontSize, 24);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(seen, same(DropClipColors.dark));
  });

  testWidgets('of(context) falls back when the extension is missing',
      (tester) async {
    late DropClipColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(builder: (context) {
        seen = DropClipColors.of(context);
        return const SizedBox();
      }),
    ));
    expect(seen, same(DropClipColors.dark));
  });
}
