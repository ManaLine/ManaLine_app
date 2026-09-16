import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mana_line/shared/mana_location.dart';

/// The app asks for GPS, and this is what stops that being "optimised" away.
///
/// THE FAILURE THIS PREVENTS, reported from a village on 2026-09-16: "Use My
/// Location" said "Could not get a location in time" on a handset showing full
/// 5G signal. Signal bars are data connectivity and say nothing about
/// positioning, which is what made it look impossible.
///
/// The cause was one enum. From geolocator_android's own source:
///
///   case medium: return Priority.PRIORITY_BALANCED_POWER_ACCURACY;
///   default:     return Priority.PRIORITY_HIGH_ACCURACY;
///
/// BALANCED_POWER does not use the GPS radio at all — it positions from WiFi
/// access points and cell towers. In rural India both are effectively absent,
/// while GPS works BETTER there than in a city. The app spent twenty seconds
/// asking the only two sources that could not answer.
///
/// WHY A TEST AND NOT A COMMENT. "medium" reads like a sensible middle setting
/// and "high" reads like waste, so the next person tuning battery life has
/// every reason to change it back — and the bug it reintroduces appears only in
/// the field, on somebody else's handset, as a timeout with no cause attached.
/// Nothing else in this suite can see it: a widget test has no GPS, and an
/// emulator answers instantly from a mock provider regardless of priority.
void main() {
  test('location is requested at an accuracy that switches the GPS radio on', () {
    expect(
      kManaLocationAccuracy,
      LocationAccuracy.high,
      reason: 'anything below `high` maps to PRIORITY_BALANCED_POWER_ACCURACY, '
          'which positions from WiFi and cell towers and never turns on GPS. '
          'That is what failed in a village with full signal. `best` is also '
          'acceptable if somebody wants it; `medium`, `low` and `lowest` are '
          'not, and neither is passing an accuracy inline at the call site '
          'where this test cannot see it',
    );
  });

  test('the accuracy is at least high, stated as the floor rather than the value', () {
    // `best` would also be fine — it is a tighter target on the same radio.
    // The floor is what matters, and writing it this way says so: the defect
    // was never "not precise enough", it was "wrong sensor".
    expect(
      kManaLocationAccuracy.index,
      greaterThanOrEqualTo(LocationAccuracy.high.index),
      reason: 'LocationAccuracy is ordered lowest..best; anything below high '
          'drops off the GPS radio',
    );
  });
}
