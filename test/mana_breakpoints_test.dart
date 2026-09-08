import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// The width classes, and the one property that protects Android.
///
/// `compact` is 600 because every handset this app targets sits under it —
/// that is what makes every desktop branch incapable of firing on a phone.
/// It is asserted here rather than assumed, because the whole safety argument
/// for the web work rests on it.
void main() {
  test('a handset is compact', () {
    expect(ManaBreakpoints.of(360), ManaWidthClass.compact);
    expect(ManaBreakpoints.of(599.9), ManaWidthClass.compact);
  });

  test('a tablet is medium', () {
    expect(ManaBreakpoints.of(600), ManaWidthClass.medium);
    expect(ManaBreakpoints.of(1023.9), ManaWidthClass.medium);
  });

  test('a desk is expanded', () {
    expect(ManaBreakpoints.of(1024), ManaWidthClass.expanded);
    expect(ManaBreakpoints.of(1920), ManaWidthClass.expanded);
  });

  test('the boundaries are the documented numbers', () {
    // Guards against someone "tidying" these into round-ish numbers that no
    // longer match the comment explaining why 600 protects Android.
    expect(ManaBreakpoints.compact, 600.0);
    expect(ManaBreakpoints.medium, 600.0);
    expect(ManaBreakpoints.expanded, 1024.0);
  });
}
