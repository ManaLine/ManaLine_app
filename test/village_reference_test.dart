import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_location.dart';
import 'package:mana_line/shared/widgets/reference_field.dart';

/// PIN 517620, as `app.suggest_villages` actually returns it: the column is
/// `village`, not `village_town_name`. Reading the wrong key is why every
/// directory suggestion came back empty and was skipped, so a real village
/// never appeared in the search and the only way forward on screen was Add New
/// Village — with three empty boxes under it.
const _pin517620 = <Map<String, dynamic>>[
  {
    'village': 'Dharmapuram Khandriga',
    'mandal': 'Renigunta',
    'district': 'Chittoor',
    'state': 'Andhra Pradesh'
  },
  {
    'village': 'Erragunta',
    'mandal': 'Renigunta',
    'district': 'Chittoor',
    'state': 'Andhra Pradesh'
  },
  {
    'village': 'Ammacheruvu',
    'mandal': 'Srikalahasti',
    'district': 'Chittoor',
    'state': 'Andhra Pradesh'
  },
];

/// A PIN that straddles a district boundary — 3,451 of the 17,183 PINs in the
/// reference do.
const _split = <Map<String, dynamic>>[
  {'village': 'A', 'mandal': 'M1', 'district': 'D1', 'state': 'S1'},
  {'village': 'B', 'mandal': 'M2', 'district': 'D2', 'state': 'S1'},
  {'village': 'C', 'mandal': 'M3', 'district': 'D2', 'state': 'S2'},
];

void main() {
  group('reference options', () {
    test('a PIN that can only mean one state and district says so', () {
      expect(manaReferenceOptions(_pin517620, 'state'), ['Andhra Pradesh']);
      expect(manaReferenceOptions(_pin517620, 'district'), ['Chittoor']);
    });

    test('an ambiguous mandal is offered rather than guessed', () {
      // Mandal is ambiguous for 9,931 of 17,183 PINs, so "fill it in only when
      // the PIN agrees" leaves the commonest field blank most of the time.
      expect(manaReferenceOptions(_pin517620, 'mandal'),
          ['Renigunta', 'Srikalahasti']);
    });

    test('a chosen state narrows the districts', () {
      expect(manaReferenceOptions(_split, 'district'), ['D1', 'D2']);
      expect(manaReferenceOptions(_split, 'district', state: 'S2'), ['D2']);
    });

    test('a chosen district narrows the mandals', () {
      expect(manaReferenceOptions(_split, 'mandal', state: 'S1'), ['M1', 'M2']);
      expect(
          manaReferenceOptions(_split, 'mandal', state: 'S1', district: 'D2'),
          ['M2']);
    });

    test('the state list is never narrowed by what is below it', () {
      expect(manaReferenceOptions(_split, 'state', district: 'D1'),
          ['S1', 'S2']);
    });

    test('the same place under two district names is listed once', () {
      // The reference carries post-2022 splits under both the old and the new
      // name, so a PIN answers twice for every village in it.
      const dupes = <Map<String, dynamic>>[
        {'village': 'X', 'mandal': 'M', 'district': 'Old', 'state': 'S'},
        {'village': 'X', 'mandal': 'M', 'district': 'New', 'state': 'S'},
      ];
      expect(manaReferenceOptions(dupes, 'mandal'), ['M']);
    });

    test('an unknown PIN offers nothing, which is a plain text field', () {
      expect(manaReferenceOptions(const [], 'mandal'), isEmpty);
    });

    test('blank values are not offered as a choice', () {
      const ragged = <Map<String, dynamic>>[
        {'village': 'X', 'mandal': '  ', 'district': 'D', 'state': 'S'},
        {'village': 'Y', 'mandal': 'M', 'district': 'D', 'state': 'S'},
      ];
      expect(manaReferenceOptions(ragged, 'mandal'), ['M']);
    });
  });

  group('a cached position', () {
    test('is a position, and says it is not fresh', () {
      const fix = ManaFix(
          status: ManaFixStatus.ok,
          latitude: 13.6,
          longitude: 79.4,
          accuracyM: 12,
          fromCache: true);

      expect(fix.hasPosition, isTrue,
          reason: 'coordinates outrank labels — this still gets recorded');
      expect(fix.isTooRoughToJudge, isTrue,
          reason: 'its accuracy describes where the phone WAS, not where it '
              'is, so it must not be used to verify an address');
      expect(fix.message, contains('last known'));
    });

    test('a fresh accurate fix still reads as captured', () {
      const fix = ManaFix(
          status: ManaFixStatus.ok,
          latitude: 13.6,
          longitude: 79.4,
          accuracyM: 12);

      expect(fix.isTooRoughToJudge, isFalse);
      expect(fix.message, 'Location captured.');
    });

    test('a rough fresh fix is still judged too rough', () {
      const fix = ManaFix(
          status: ManaFixStatus.ok,
          latitude: 13.6,
          longitude: 79.4,
          accuracyM: 250);

      expect(fix.isTooRoughToJudge, isTrue);
      expect(fix.message, contains('250m'));
    });

    test('a place built on a cached fix still fills the form', () {
      const place = ManaPlace(
        fix: ManaFix(
            status: ManaFixStatus.ok,
            latitude: 13.6,
            longitude: 79.4,
            accuracyM: 12,
            fromCache: true),
        pinCode: '517620',
        village: 'Erragunta',
      );

      expect(place.hasPosition, isTrue);
      expect(place.filledAnything, isTrue);
    });
  });
}
