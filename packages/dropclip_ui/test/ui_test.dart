import 'package:dropclip_ui/dropclip_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropClip UI Package', () {
    test('DropClipThemeTokens defines valid app name', () {
      expect(DropClipThemeTokens.appName, equals('DropClip'));
    });
  });
}
