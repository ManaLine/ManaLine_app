import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every form that asks a person their gender must offer the three values
/// the database allows, spelled with the right digits.
///
/// `persons_gender_digit_check` is `CHECK (gender_digit = ANY (ARRAY['0',
/// '1','2']))` -- read off the live constraint 2026-09-19 -- and the
/// canonical mapping is 1 Male, 0 Female, 2 Others, written down in
/// `bulk_onboarding_service.dart`'s `_genderDigits`, which accepts M/F/O in
/// English and Telugu. So a spreadsheet could always carry an Others person
/// while the three one-at-a-time forms could not:
///
///   - OW-004 and LR-004 offered Male and Female only.
///   - OW-014 offered three and got two of them wrong -- Female stored '2'
///     (which IS Others) and Others stored '3' (which the CHECK rejects, so
///     it was a 23514 on every call). Its own test pinned those digits.
///
/// The digit is not a display detail. `app.mint_person_mlid` builds the MLID
/// as `'MLPI' || p_gender_digit || RIGHT(aadhaar, 8)` (and MLTI the same way
/// with a random tail), so a wrong digit is minted into a permanent
/// identifier that the person then carries.
///
/// A widget test would be the stronger check, but the thing that broke here
/// was the literal digit beside the literal label, and that is exactly what
/// a text assertion pins. What it deliberately also pins is the PAIRING:
/// asserting only that three values are present is what let '2' sit under
/// Female for as long as it did.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// The dropdown items between the gender field's label and its onChanged.
  String genderItems(String source, String labelAnchor) {
    final from = source.indexOf(labelAnchor);
    expect(from, isNot(-1), reason: 'gender field anchor $labelAnchor moved');
    final picker = source.substring(from);
    return picker.substring(0, picker.indexOf('onChanged:'));
  }

  void expectTheThreeDigits(String items, {required String where}) {
    expect(items, contains("value: '1', child: ManaText.raw(ref.t('male'))"),
        reason: '$where: 1 is Male');
    expect(items, contains("value: '0', child: ManaText.raw(ref.t('female'))"),
        reason: '$where: 0 is Female');
    expect(items, contains("value: '2', child: ManaText.raw(ref.t('others'))"),
        reason: '$where: 2 is Others -- bulk import has minted these all '
            'along; a form that cannot offer it sends somebody away or makes '
            'them lie');
    expect(items.contains("value: '3'"), isFalse,
        reason: '$where: there is no gender digit 3; the CHECK rejects it');
  }

  test('OW-004 Add Customer offers all three', () {
    expectTheThreeDigits(
      genderItems(
        read('lib/features/owner_workspace/screens/ow_004_customer_management.dart'),
        '\${ref.t("gender")} *',
      ),
      where: 'OW-004',
    );
  });

  test('OW-014 register a pre-existing person offers all three', () {
    expectTheThreeDigits(
      genderItems(
        read('lib/features/owner_workspace/screens/ow_014_global_workflow.dart'),
        "ref.t('gender_field')",
      ),
      where: 'OW-014',
    );
  });

  test('LR-004 self-registration offers all three, in the person\'s language',
      () {
    final lr004 = read(
        'lib/features/login_registration/screens/lr_004_registration_form.dart');
    expectTheThreeDigits(
      genderItems(lr004, "labelText: 'Gender *'"),
      where: 'LR-004',
    );
    // The other sixteen field labels on this screen are still English on
    // purpose (see the comment beside Date of Birth). The VALUES are not a
    // label: a person picking their own gender on a Telugu handset was being
    // asked to choose between two English words.
    expect(lr004.contains("Text('Male')"), isFalse);
    expect(lr004.contains("Text('Female')"), isFalse);
  });

  test('LR-004 does not default an unanswered gender', () {
    // `_gender ?? '0'` recorded Female for a question nobody answered. It was
    // unreachable behind _missingRequirements, and it is still the wrong
    // shape: the fallback is a permanent MLID digit, not a display default.
    expect(
        read('lib/features/login_registration/screens/lr_004_registration_form.dart')
            .contains("_gender ?? '0'"),
        isFalse);
  });

  group('the server accepts what the forms now offer', () {
    // LR-004 and OW-014 both register through the auth-register Edge
    // Function, not through app.register_new_customer. Until this pass it
    // rejected '2' outright -- so widening the pickers alone would have
    // turned every Others registration into a 400 that named the field.
    // OW-004 goes through the RPC, whose mint_person_mlid only concatenates
    // the digit and is indifferent to which one it is.
    test('auth-register validates against all three digits', () {
      final fn = read('supabase/functions/auth-register/index.ts');
      expect(fn, contains('body.gender_digit !== "2"'));
      expect(fn.contains('errors.push("gender_digit must be \'0\' or \'1\'")'),
          isFalse);
    });

    test('mlid.ts mints an MLID for all three digits', () {
      final mlid = read('supabase/functions/_shared/mlid.ts');
      expect(mlid, contains('genderDigit !== "2"'));
      // The narrowed return type was the other half of the refusal: it fed
      // buildMlpi and buildMltiCandidate, which would not have compiled on a
      // '2' even once the check above let one through.
      expect(mlid, contains('"0" | "1" | "2"'));
      expect(RegExp(r'"0" \| "1"(?! \| "2")').hasMatch(mlid), isFalse,
          reason: 'a signature left at two digits still refuses Others');
    });
  });
}
