import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_site.dart';

/// The app must not send anybody to a domain that does not exist.
///
/// TWO LINKS DID. The handset signpost — the whole point of which is to send
/// an Owner to the website for bulk onboarding — pointed at
/// `https://manaline.in/app/`, and the sign-in page's "About MANA LINE" link
/// at `https://manaline.in/`. That domain is NOT REGISTERED: NXDOMAIN from
/// two independent resolvers, while a known-good `.in` resolves fine from the
/// same query. Both shipped, one of them inside an APK on a real phone.
///
/// It was an easy mistake to make and a very hard one to see. The name is in
/// every plan and every design document; the deploy guide is literally titled
/// "Deploying manaline.in". Nobody had cause to type it into a browser until
/// somebody followed the link.
void main() {
  test('nothing in lib/ hardcodes the unregistered domain', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // The URL, not the word. `manaline.in@gmail.com` is a real address and
      // appears legitimately on the About screen — the mail account is not
      // the website and does not care whether the domain resolves.
      if (RegExp(r'https?://manaline\.in').hasMatch(src)) {
        offenders.add(f.uri.pathSegments.last);
      }
    }
    expect(offenders, isEmpty,
        reason: 'these link to a domain that is not registered: $offenders. '
            'Use manaSiteUrl from shared/mana_site.dart, which defaults to '
            'the origin actually serving and takes the real domain through '
            '--dart-define=MANA_SITE_URL the day it exists.');
  });

  test('the default points somewhere that resolves today', () {
    // A link that works and is not yet the final address beats a link to an
    // address that does not exist.
    expect(manaSiteUrl, startsWith('https://'));
    expect(manaSiteUrl, isNot(contains('manaline.in')),
        reason: 'until the domain is registered and attached, the default '
            'must be the live origin');
    expect(manaSiteUrl, isNot(endsWith('/')),
        reason: 'callers append their own path; a double slash works in four '
            'browsers and not the fifth');
  });

  test('the app URL is derived, not configured separately', () {
    // Both halves are one deployment — they upload together and share one
    // _headers file — so allowing them to be set apart would permit a
    // combination that has never existed.
    expect(manaSiteAppUrl, '$manaSiteUrl/app/');
  });

  test('the signpost and the sign-in page both read the constant', () {
    for (final path in const [
      'lib/features/owner_workspace/screens/ow_bulk_onboarding_on_web.dart',
      'lib/features/web/widgets/mana_auth_shell.dart',
    ]) {
      expect(File(path).readAsStringSync(), contains('manaSite'),
          reason: '$path should not know the address itself');
    }
  });
}
