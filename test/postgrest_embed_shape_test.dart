import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_api_service.dart';

/// This broke login for every user, so the shapes are pinned here.
///
/// PostgREST decides an embed's shape from the CONSTRAINTS, not the query:
/// one-to-many arrives as a List, one-to-one as the object itself or null.
/// `investors.membership_id` has a unique index, so `business_members ->
/// investors` is one-to-one and arrives as a Map — and `as List?` threw a
/// TypeError on every row, after a login that had already succeeded.
void main() {
  group('one-to-one embed (the real shape here)', () {
    test('an object means the row exists', () {
      expect(manaEmbedHasRow({'investor_id': 'abc'}), isTrue);
    });

    test('null means it does not', () {
      expect(manaEmbedHasRow(null), isFalse);
    });
  });

  group('one-to-many embed (the shape if the unique index were dropped)', () {
    test('a populated list means the row exists', () {
      expect(manaEmbedHasRow([
        {'investor_id': 'abc'}
      ]), isTrue);
    });

    test('an empty list means it does not', () {
      expect(manaEmbedHasRow(const []), isFalse);
    });
  });

  test('an empty object is treated as absent, not present', () {
    // PostgREST can return {} for a row the caller selected no columns from.
    expect(manaEmbedHasRow(const <String, dynamic>{}), isFalse);
  });
}
