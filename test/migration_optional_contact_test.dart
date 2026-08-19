import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_018_business_migration.dart';

/// The pre-existing-business path is the one place a person may be registered
/// without a phone number — `persons.mobile_number` is nullable and
/// `app.register_new_customer` NULLIFs an empty string. The form used to
/// demand ten digits anyway, which left inventing a number as the only way to
/// enter an old customer, and an invented number collides with its real owner
/// under uq_persons_mobile_number.
void main() {
  group('mobile number on the migration path', () {
    test('blank is allowed — the old book often has none', () {
      expect(migrationMobileAcceptable(''), isTrue);
      expect(migrationMobileAcceptable('   '), isTrue);
    });

    test('a full ten digits is allowed', () {
      expect(migrationMobileAcceptable('9465341213'), isTrue);
      expect(migrationMobileAcceptable(' 9465341213 '), isTrue);
    });

    test('a partial number is refused — that is a typo, not an omission', () {
      expect(migrationMobileAcceptable('94653'), isFalse);
      expect(migrationMobileAcceptable('946534121'), isFalse);
      expect(migrationMobileAcceptable('94653412134'), isFalse);
    });
  });
}
