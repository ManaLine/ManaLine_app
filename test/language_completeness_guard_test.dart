import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

/// The app offers only languages it can actually speak.
///
/// THE FAILURE THIS PREVENTS. `ui_translations` has five language columns and
/// `preferred_language_enum` has five values, but of ~1,600 keys: English
/// 1,600, Telugu 1,591, and Hindi / Tamil / Kannada 174 each — about 11%.
/// A picker that offered five would hand somebody an app in which roughly nine
/// screens in ten render as raw keys like `collected_amount_field`.
///
/// Worse than useless: an Owner who picks Hindi, cannot read the app, and
/// cannot find the setting to change it back, because that setting is now
/// also a raw key.
///
/// The claim itself has already cost something once. "5 languages" propagated
/// from CLAUDE.md into a plan and came within one implementer's diligence of
/// being printed on the public website as a promise to strangers.
///
/// Verified on 2026-09-15: the picker offers two, and all 98 people in
/// production are on English.
void main() {
  test('only English and Telugu are offered', () {
    expect(ManaLanguage.values.map((l) => l.enumValue).toList(),
        ['English', 'Telugu'],
        reason: 'a language here is a promise that the app can be READ in it. '
            'Hindi, Tamil and Kannada are ~11% translated; adding one back '
            'means finishing it first, not shipping raw keys to somebody who '
            'then cannot find the setting to undo it');
  });

  test('every offered language has a native label, not an English one', () {
    // Somebody choosing Telugu is, by definition, reading Telugu. A list that
    // says "Telugu" in Latin script to a Telugu reader is the same category of
    // mistake in miniature.
    expect(ManaLanguage.telugu.nativeLabel, isNot('Telugu'));
    for (final l in ManaLanguage.values) {
      expect(l.nativeLabel.trim(), isNotEmpty);
    }
  });

  test('the repo does not claim more languages than it has', () {
    // The stale figure reached a plan once, and this guard was built to stop
    // it reaching a stranger. It checked two files and the claim was sitting
    // in two others the whole time.
    //
    // `web/index.html` and `web/manifest.json` are Flutter's own scaffolding,
    // edited once to carry the product description and then never looked at
    // again -- so nobody thought of them as pages, and the guard's author
    // (me) listed the two files a HUMAN would read rather than the ones a
    // READER would receive. Both ship on every web deploy: the meta
    // description is what a search engine quotes, and the manifest
    // description is what an install prompt shows. They were live on
    // manaline.pages.dev, claiming five languages, for the several hours
    // between the first deploy and finding this.
    //
    // Added 2026-09-18. Scan what is SERVED, not what is authored.
    for (final path in [
      'README.md',
      'site/index.html',
      'web/index.html',
      'web/manifest.json',
    ]) {
      final text = File(path).readAsStringSync().toLowerCase();
      expect(text, isNot(contains('five languages')),
          reason: '$path claims five languages');
      expect(text, isNot(contains('5 languages')),
          reason: '$path claims five languages');
    }
  });
}
