import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_001_owner_home_dashboard.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Universal Search used to be a bottom sheet: the field opened at the bottom
/// of the display under the keyboard, and the results grew downwards out of a
/// plain non-scrolling Column, so a name matching twenty people ran off the
/// screen rather than scrolling.
///
/// It is a pushed screen now, with the field pinned in the app bar. These pin
/// the part that was wrong — the field is at the top and the body scrolls —
/// plus the usual scale sweep, because a hint string in an AppBar.bottom of
/// fixed height is this app's recurring overflow shape.
const _searchTelugu = <String, Map<String, String>>{
  'search': {'English': 'Search', 'Telugu': 'వెతకండి'},
  'search_by_phone_mlid_aadhaar_name': {
    'English': 'Search by Phone, MANA LINE ID, Aadhaar, or Name.',
    'Telugu': 'ఫోన్, మానా లైన్ ఐడీ, ఆధార్ లేదా పేరుతో వెతకండి.',
  },
  'no_identity_found': {
    'English': 'No identity found.',
    'Telugu': 'గుర్తింపు కనుగొనబడలేదు.',
  },
  'not_a_member_of_business': {
    'English': 'Not a member of this business.',
    'Telugu': 'ఈ వ్యాపారంలో సభ్యులు కాదు.',
  },
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('Universal Search survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const UniversalSearchScreen(businessId: 'b1'),
        textScale: scale,
      );
      expectNoLayoutFault(tester, 'Universal Search at ${scale}x');
    });

    testWidgets('Universal Search survives text scale ${scale}x in Telugu',
        (tester) async {
      await pumpManaScreen(
        tester,
        const UniversalSearchScreen(businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _searchTelugu,
      );
      expectNoLayoutFault(tester, 'Universal Search at ${scale}x in Telugu');
    });
  }

  testWidgets('the field is above the results area', (tester) async {
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'));

    final field = tester.getRect(find.byType(TextField));
    final body = tester.getRect(find.byType(Scaffold));

    // The whole point of the change: the thing you type into is near the top
    // of the screen, not sitting at the bottom under the keyboard.
    expect(field.top, lessThan(body.height / 2),
        reason: 'the search field must sit in the top half of the screen');
  });

  testWidgets('before searching it prompts rather than claiming no match',
      (tester) async {
    await pumpManaScreen(tester, const UniversalSearchScreen(businessId: 'b1'));

    // Saying "no identity found" to someone who has not typed anything yet
    // reads as a broken search.
    expect(find.text('No identity found.'), findsNothing);
  });
}
