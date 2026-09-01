import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/stored_file.dart';

/// Every `*_url` column held a signed URL good for a year.
///
/// The upload helpers signed for 60*60*24*365 seconds and stored the whole
/// URL. A Supabase signed URL carries its own authorisation, so each of those
/// rows was a working link to a private file — no login, no RLS, no way to
/// revoke it short of deleting the object. The live photos are pictures of
/// people's faces taken as fraud evidence at their doorstep, and
/// customer_documents holds identity documents.
///
/// The column holds the object path now. These tests pin the parsing, because
/// the backfill migration and the display path both depend on recovering a
/// path from the old shape exactly.
void main() {
  const signed =
      'https://vjhxssqgqlvyesndubor.supabase.co/storage/v1/object/sign/'
      'live-photos/0b726425-2338-49e5-bea1-6856624995b4/loans/abc-123.jpg'
      '?token=eyJraWQiOiI1NWY4NmZiNyJ9.signature';

  group('pathOf', () {
    test('recovers the path from a legacy signed URL', () {
      expect(ManaStoredFile.pathOf(signed),
          '0b726425-2338-49e5-bea1-6856624995b4/loans/abc-123.jpg');
    });

    test('drops the token, which is the whole point', () {
      expect(ManaStoredFile.pathOf(signed), isNot(contains('token')));
    });

    test('a path is already a path', () {
      const path = '148/photo.jpg';
      expect(ManaStoredFile.pathOf(path), path);
    });

    test('a nested path survives intact', () {
      expect(
          ManaStoredFile.pathOf(
              'https://x.supabase.co/storage/v1/object/sign/b/a/b/c/d.jpg?token=t'),
          'a/b/c/d.jpg');
    });

    test('the migrated sentinel is not a file', () {
      // Written by the importer for loans from the paper book, where no photo
      // was ever taken. Resolving it would sign a path that does not exist.
      expect(ManaStoredFile.pathOf(ManaStoredFile.migratedSentinel), isNull);
    });

    test('nothing is nothing', () {
      expect(ManaStoredFile.pathOf(null), isNull);
      expect(ManaStoredFile.pathOf(''), isNull);
      expect(ManaStoredFile.pathOf('   '), isNull);
    });

    test('a URL that is not a signed object URL yields nothing', () {
      // Better to show a placeholder than to sign a guess.
      expect(ManaStoredFile.pathOf('https://example.com/photo.jpg'), isNull);
    });
  });

  group('the display link', () {
    test('is minutes, not a year', () {
      // 31,536,000 seconds was the old value, stored in the database.
      expect(ManaStoredFile.displayTtl.inMinutes, lessThanOrEqualTo(15));
      expect(ManaStoredFile.displayTtl.inSeconds, greaterThan(60),
          reason: 'long enough to load an image on a bad rural connection');
    });
  });

  group('signedUrl', () {
    test('resolves nothing for nothing, without touching the network',
        () async {
      expect(
          await ManaStoredFile.signedUrl(bucket: 'live-photos', stored: null),
          isNull);
      expect(
          await ManaStoredFile.signedUrl(
              bucket: 'live-photos', stored: ManaStoredFile.migratedSentinel),
          isNull);
    });
  });
}
