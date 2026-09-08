// Guard: site/plans.html must stay in sync with kOwnerTiers, the tier data
// the app itself enforces (lib/features/owner_workspace/state/
// subscription_state.dart), and must never carry a price.
//
// Billing is not live. Showing a price on the public site would read as an
// offer this app cannot yet take payment against — see subscription_state's
// own `planned_prices_note` for why the app itself only ever shows figures
// to a signed-in Owner, never to a stranger. This test makes publishing a
// price something that fails a test, whether the price arrived by hand or
// by regenerating site/plans.html with tool/gen_site_plans.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/subscription_state.dart';

void main() {
  group('site/plans.html stays in sync with kOwnerTiers', () {
    late String html;

    setUpAll(() {
      final file = File('site/plans.html');
      if (!file.existsSync()) {
        fail('site/plans.html does not exist. Run '
            '`dart run tool/gen_site_plans.dart` after writing the static '
            'page shell.');
      }
      html = file.readAsStringSync();
    });

    test('every tier name in kOwnerTiers appears in the page', () {
      for (final tier in kOwnerTiers) {
        expect(html.contains(tier.name), isTrue,
            reason: 'Tier "${tier.name}" is missing from site/plans.html');
      }
    });

    test('every cap figure matches, including Enterprise\'s unlimited caps',
        () {
      // The page renders a finite cap with comma thousands separators (the
      // app's own convention for figures) — e.g. 1500 -> "1,500" — so this
      // reproduces that formatting rather than matching bare digits, which
      // would pass even if the separator were dropped or wrong.
      String withThousands(int value) {
        final digits = value.toString();
        final buffer = StringBuffer();
        for (var i = 0; i < digits.length; i++) {
          if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
          buffer.write(digits[i]);
        }
        return buffer.toString();
      }

      for (final tier in kOwnerTiers) {
        for (final cap in [tier.agents, tier.customers, tier.investors]) {
          final rendered = cap == null ? 'Unlimited' : withThousands(cap);
          expect(html.contains(rendered), isTrue,
              reason: 'Tier "${tier.name}" cap "$rendered" is missing from '
                  'site/plans.html');
        }
      }
    });

    test('no rupee symbol or price string appears anywhere in the file', () {
      expect(html.contains('₹'), isFalse,
          reason: 'site/plans.html contains a rupee symbol (₹) — billing is '
              'not live, so no price may be published.');

      // Word-bounded, not `contains` — Enterprise's price string is
      // "Custom", which is also a legitimate substring of "Customer"/
      // "Customers" elsewhere on the page. A bare `contains` check would
      // either false-positive on that word or have to be weakened in a way
      // that stops meaning anything.
      bool containsAsWord(String needle) => RegExp(
            '(?<![A-Za-z0-9])${RegExp.escape(needle)}(?![A-Za-z0-9])',
          ).hasMatch(html);

      for (final tier in kOwnerTiers) {
        expect(containsAsWord(tier.monthly), isFalse,
            reason: 'site/plans.html contains the "${tier.monthly}" price '
                'string for ${tier.name}.');
        expect(containsAsWord(tier.yearly), isFalse,
            reason: 'site/plans.html contains the "${tier.yearly}" price '
                'string for ${tier.name}.');
      }

      // Catches a price added straight into the HTML by hand, not just one
      // emitted by the generator — e.g. "$29/mo" or "Rs. 199" would not be
      // caught by the checks above, so also refuse common price shapes.
      final priceLike = RegExp(r'(?:Rs\.?|INR)\s?\d|\$\s?\d+(?:\.\d{2})?\b');
      expect(priceLike.hasMatch(html), isFalse,
          reason: 'site/plans.html contains what looks like a price string.');
    });
  });
}
