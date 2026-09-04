import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/business_management_state.dart';
import 'package:mana_line/shared/location_api_service.dart';

/// PIN plus at least three letters of the village name, sorted A to Z.
///
/// WHY THE RULE EXISTS: a PIN on its own is not a shortlist. 517536 carries
/// fifty villages and 524129 twenty-four, and answering a six-digit PIN with
/// the whole directory makes the Owner scroll for a name they already know.
///
/// WHY THIS TEST EXISTS: the rule lives in three places — the operating-area
/// search, the shared LocationApiService, and the setup wizard's own inline
/// search. Three copies of one number is exactly the drift this repo keeps
/// meeting, and two of them agreeing while the third quietly uses 2 would be
/// invisible on screen: the odd one out would simply search sooner.
///
/// The wizard's copy is a private constant on a State class and cannot be
/// reached from here. It is checked by reading it — `_minVillageLetters` in
/// ow_000_first_business_setup.dart — and the comment there says so.
void main() {
  test('the threshold is the same wherever it is enforced', () {
    expect(BusinessManagementApiService.minVillageLetters, 3);
    expect(LocationApiService.minVillageLetters, 3);
    expect(
      BusinessManagementApiService.minVillageLetters,
      LocationApiService.minVillageLetters,
      reason: 'One picker would start searching before the others, for the '
          'same typing. Keep them equal or give each a written reason.',
    );
  });

  group('needsVillageName tells the two silences apart', () {
    // "Nothing searched yet" and "searched, found nothing" must not share a
    // message. Conflating them is how "No villages found for that PIN" came to
    // be shown for a PIN with fifty villages behind it.
    test('a complete PIN with no name is asking for the name', () {
      const s = OperatingAreaSearchState(pinCode: '517536');
      expect(s.needsVillageName, isTrue);
    });

    test('a complete PIN with too few letters is still asking', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'do');
      expect(s.needsVillageName, isTrue);
    });

    test('three letters is enough to have searched', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'dom');
      expect(s.needsVillageName, isFalse);
    });

    test('whitespace is not a letter', () {
      const s = OperatingAreaSearchState(pinCode: '517536', villageQuery: 'd  ');
      expect(s.needsVillageName, isTrue,
          reason: 'Trimmed length decides, or two spaces would trigger a '
              'search for one letter.');
    });

    test('an incomplete PIN is not asking for a village name yet', () {
      // The prompt would be premature: the PIN field is still being typed, and
      // a screen nagging for a village before it has a PIN reads as broken.
      const s = OperatingAreaSearchState(pinCode: '5175', villageQuery: '');
      expect(s.needsVillageName, isFalse);
    });
  });
}
