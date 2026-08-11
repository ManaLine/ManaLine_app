import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_016_profile.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// OW-016 loads straight from Supabase in `_load()` rather than through a
/// provider, so there is nothing to seed here — the screen lands in its
/// `_person == null` branch. That still exercises the two strings this
/// screen owns on that path (the AppBar title and the load-failure line),
/// which is what the wiring pass changed.
const _telugu = <String, Map<String, String>>{
  'my_profile': {'English': 'My Profile', 'Telugu': 'నా ప్రొఫైల్'},
  'could_not_load_profile_plain': {'English': 'Could not load profile.', 'Telugu': 'ప్రొఫైల్ లోడ్ కాలేదు.'},
  'address': {'English': 'Address', 'Telugu': 'చిరునామా'},
  'edit': {'English': 'Edit', 'Telugu': 'మార్చండి'},
  'businesses_owned': {'English': 'Businesses Owned', 'Telugu': 'స్వంత వ్యాపారాలు'},
  'no_businesses_found': {'English': 'No businesses found.', 'Telugu': 'వ్యాపారాలు కనుగొనబడలేదు.'},
  'no_address_on_file': {'English': 'No address on file.', 'Telugu': 'ఫైల్‌లో చిరునామా లేదు.'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('OW-016 profile survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, const OwnerProfileScreen(), textScale: scale);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-016 profile at ${scale}x');
    });

    testWidgets('OW-016 profile survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(tester, const OwnerProfileScreen(),
          textScale: scale, language: ManaLanguage.telugu, translations: _telugu);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-016 profile at ${scale}x in Telugu');
    });
  }
}
