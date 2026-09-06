import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web shell is a file nobody looks at after the first day, which is
/// exactly why it ships wrong. Flutter's default index.html titles the tab
/// `mana_line` and describes the product as "A new Flutter project." — text
/// that reaches a bookmark, a browser tab and a shared link preview.
void main() {
  test('index.html carries no Flutter boilerplate', () {
    final html = File('web/index.html').readAsStringSync();

    expect(html, isNot(contains('A new Flutter project')),
        reason: 'The default description is still in web/index.html.');
    expect(html, isNot(contains('<title>mana_line</title>')),
        reason: 'The browser tab still says mana_line.');
    expect(html, contains('<title>MANA LINE</title>'));
    expect(html, contains(r'<base href="$FLUTTER_BASE_HREF">'),
        reason: 'The base href placeholder must survive — --base-href=/app/ '
            'substitutes it at build time, and every asset path depends on it.');
  });

  test('the manifest names the product, not the package', () {
    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, isNot(contains('A new Flutter project')));
    expect(manifest, contains('MANA LINE'));
  });
}
