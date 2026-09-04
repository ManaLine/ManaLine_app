import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A PIN search that reads `locations` alone finds nothing on a new book.
///
/// THE BUG THIS EXISTS FOR: `locations` is not a directory. It holds only the
/// villages some business already operates in — a handful of rows for the whole
/// app, and NONE at all for a business being set up. Every village picker that
/// searched it alone therefore answered "No villages found for that PIN" for
/// every PIN on earth, including 517536, where the LGD reference carries fifty
/// villages, and 524129, where it carries Punabaka.
///
/// That was not a cosmetic failure. No village means no operating area; no area
/// means no customers; no customers means no loans and no collections. A single
/// lookup against the wrong table gated the entire app, and it read as missing
/// DATA rather than as a bug — the obvious next move was to go and find a
/// village directory, when one with 768,529 rows was already sitting in
/// `lgd_villages` behind `app.suggest_villages`.
///
/// THE RULE: a file that filters `locations` by `pin_code` is offering somebody
/// a choice of villages. It must also reach the reference — directly through
/// `suggest_villages`, or through `LocationApiService`, which merges the two.
///
/// Counted in FILES, like the consumer census, and matched on source text
/// because the alternative is a live database.
const _pinFilter = "eq('pin_code'";

/// Reaching the reference, by either route.
const _referenceMarkers = ['suggest_villages', 'locationApiServiceProvider'];

/// The four address editors that still search `locations` alone.
///
/// NOT an exemption on the merits — they have the same defect, and somebody
/// editing their own address still cannot find a village nobody has used yet.
/// They are listed rather than fixed because each degrades to `manaAddVillage
/// IfMissing`, the manual entry path: the person types mandal, district and
/// state by hand and still gets a real row at the end. That is friction, not a
/// wall, and the pickers that had NO fallback were the ones that had to be
/// fixed first.
///
/// Removing a name from this list is the goal. Adding one needs a reason worth
/// writing down, and "it was easier" is not one.
const _knownManualOnly = <String>{
  'cw_006_my_profile_memberships.dart',
  'iw_005_my_profile_memberships.dart',
  'ow_014_profile_completion.dart',
  'ow_016_profile.dart',
};

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  List<File> pinSearchers() => [
        for (final f in files)
          if (f.readAsStringSync().contains(_pinFilter)) f,
      ];

  test('the guard is looking at something', () {
    // If this hits zero the matcher has drifted and every assertion below
    // passes vacuously — the failure mode this whole file exists to prevent.
    expect(pinSearchers(), isNotEmpty,
        reason: 'No file filters locations by pin_code any more. Either the '
            'query style changed and $_pinFilter needs updating, or these '
            'searches moved somewhere this test cannot see.');
  });

  test('every PIN village search reaches the LGD reference', () {
    final offenders = <String>[];
    for (final f in pinSearchers()) {
      final name = f.uri.pathSegments.last;
      if (_knownManualOnly.contains(name)) continue;
      final source = f.readAsStringSync();
      if (_referenceMarkers.any(source.contains)) continue;
      offenders.add(f.path);
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These search `locations` by PIN without reaching the LGD '
          'reference, so they find nothing on a business that has no villages '
          'yet — which is every new business:\n  ${offenders.join('\n  ')}\n\n'
          'Merge app.suggest_villages in (see searchLocations in '
          'business_management_state.dart) or go through LocationApiService, '
          'and materialise the pick with add_location_if_missing.',
    );
  });

  test('the manual-only list names files that exist and still qualify', () {
    // A stale exemption is worse than none: it silently covers a file that was
    // fixed, or one that was renamed and is no longer being checked at all.
    final searching = {for (final f in pinSearchers()) f.uri.pathSegments.last};
    final stale = _knownManualOnly.difference(searching);
    expect(
      stale,
      isEmpty,
      reason: 'Listed as manual-only but no longer doing a PIN search — fixed, '
          'renamed or deleted. Remove from _knownManualOnly:\n  '
          '${stale.join('\n  ')}',
    );
  });
}
