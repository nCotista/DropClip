import 'package:dropclip_desktop/src/web/web_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the phone page is self-contained and never renders text as HTML', () {
    // Works on the LAN with no internet; nothing third-party can load.
    expect(webCompanionPage,
        isNot(matches(RegExp(r'''(src|href)=["']https?:'''))));
    expect(webCompanionPage, isNot(contains('@import')));
    // Clips come from other devices: set as text only.
    expect(webCompanionPage, isNot(contains('innerHTML')));
    expect(webCompanionPage, contains('textContent'));
    // The link code is read from the fragment, then wiped from the URL.
    expect(webCompanionPage,
        contains("history.replaceState(null, '', location.pathname)"));
    expect(webCompanionPage, contains('x-dropclip-token'));
    // Session token carries server expiry and is cleared once expired.
    expect(webCompanionPage, contains('expires_at'));
    expect(webCompanionPage, contains('Date.now() >= exp'));
    expect(webCompanionPage,
        isNot(contains('localStorage.setItem(KEY, token)')));
  });
}
