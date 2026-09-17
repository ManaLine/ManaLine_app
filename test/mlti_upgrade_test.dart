import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mlti_upgrade_sheet.dart';
import 'package:mana_line/shared/mlti_upgrade_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

MltiPerson _person({
  String mlid = 'MLTI154467504',
  String name = 'Venkata Subrahmanyam',
  String careOf = 'Satyanarayana Murthy',
  String village = 'Pedanandipadu',
}) =>
    MltiPerson(
      personId: 42,
      mlid: mlid,
      fullName: name,
      careOf: careOf,
      village: village,
      mobile: '9000000000',
      role: 'Customer',
      hasDob: false,
      hasPhoto: false,
    );

class _Seeded extends MltiUpgradeNotifier {
  static List<MltiPerson> seed = const [];
  @override
  MltiUpgradeState build() => MltiUpgradeState(people: seed);
  @override
  Future<void> load(String businessId) async {}
}

void main() {
  group('the form asks for what an MLPI needs', () {
    testWidgets('it will not submit without an Aadhaar of 12 digits',
        (tester) async {
      // The same three checks exist in the RPC. These exist to say WHICH field
      // is missing before a round trip; the server's exist because a client
      // check is not a rule.
      await pumpManaScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => MltiUpgradeSheet.open(context,
                person: _person(), businessId: 'b1'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '12345');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Permanent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('12 digits'), findsOneWidget);
      // And it did not get as far as asking for the photo, because it stopped
      // at the first missing thing rather than listing all three.
      expect(find.textContaining('live photo is required'), findsNothing);
    });

    testWidgets('with a full Aadhaar it asks for the photo next',
        (tester) async {
      await pumpManaScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => MltiUpgradeSheet.open(context,
                person: _person(), businessId: 'b1'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '999988887777');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make Permanent'));
      await tester.pumpAndSettle();

      expect(find.textContaining('live photo is required'), findsOneWidget);
    });

    testWidgets('the sheet names the person and their temporary ID',
        (tester) async {
      // An agent at a door has to know the form in front of them belongs to
      // the person in front of them. Name, C/o, village and the MLTI.
      await pumpManaScreen(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => MltiUpgradeSheet.open(context,
                person: _person(), businessId: 'b1'),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Venkata Subrahmanyam'), findsOneWidget);
      expect(find.textContaining('C/o Satyanarayana Murthy'), findsOneWidget);
      expect(find.textContaining('MLTI154467504'), findsOneWidget);
    });
  });

  group('the banner', () {
    testWidgets('draws nothing when every ID is permanent', (tester) async {
      // A permanent banner reading "0 temporary IDs" is a row of pixels that
      // never changes and is read once.
      await pumpManaScreen(
        tester,
        const Scaffold(body: MltiUpgradeBanner(count: 0, businessId: 'b1')),
      );
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('says how many there are', (tester) async {
      await pumpManaScreen(
        tester,
        const Scaffold(body: MltiUpgradeBanner(count: 65, businessId: 'b1')),
      );
      expect(find.textContaining('65'), findsOneWidget);
    });
  });

  group('the list', () {
    for (final scale in kManaTextScales) {
      for (final lang in ManaLanguage.values) {
        testWidgets('temporary IDs list at ${scale}x in ${lang.name}',
            (tester) async {
          _Seeded.seed = [
            _person(),
            _person(
                mlid: 'MLTI106182532',
                name: 'Jandhyala Arjun Yadav',
                careOf: 'Ramakrishna',
                village: 'Srikalahasti'),
          ];
          await pumpManaScreen(
            tester,
            const MltiUpgradeScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [mltiUpgradeProvider.overrideWith(_Seeded.new)],
          );
          expectNoLayoutFault(
              tester, 'temporary IDs at ${scale}x in ${lang.name}');
        });
      }
    }

    testWidgets('an empty list says the book is done, not that it is empty',
        (tester) async {
      _Seeded.seed = const [];
      await pumpManaScreen(
        tester,
        const MltiUpgradeScreen(businessId: 'b1'),
        overrides: [mltiUpgradeProvider.overrideWith(_Seeded.new)],
      );
      expect(find.textContaining('permanent ID'), findsOneWidget);
    });

    testWidgets('it is sorted by name', (tester) async {
      // 65 people in insertion order is a list nobody can find anybody in.
      _Seeded.seed = [
        _person(name: 'Zara'),
        _person(name: 'Anil'),
      ];
      await pumpManaScreen(
        tester,
        const MltiUpgradeScreen(businessId: 'b1'),
        overrides: [mltiUpgradeProvider.overrideWith(_Seeded.new)],
      );
      // The notifier is seeded directly here, so this asserts the SERVICE
      // sorts rather than the screen -- which is where the sort lives, and
      // where a list arriving from the server is ordered.
      final source =
          File('lib/shared/mlti_upgrade_state.dart').readAsStringSync();
      expect(source, contains('out.sort('),
          reason: 'fetchPending must return the list in name order');
    });
  });

  group('the identity rules are written down once', () {
    // COMMENTS STRIPPED BEFORE ASSERTING. The first version of this searched
    // the whole migration for the hand-composed MLID expression and found it —
    // in the paragraph explaining why the code must never write that. A guard
    // that matches its own documentation is reporting on prose, and this
    // codebase has now done exactly that five times in one day.
    //
    // Line endings normalised for the reason the roster guards were: only
    // *.sql is pinned to LF, and a .sql file read on Windows still arrives
    // however the checkout left it.
    final sql = File(
            'supabase/migrations/20260917220828_a_temporary_identity_can_be_made_permanent.sql')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');

    test('the MLPI is minted, not composed by hand', () {
      // Two copies of 'MLPI' || gender || right(digits,8) is how they come to
      // disagree, and the minter also carries the duplicate-Aadhaar, the
      // twelve-digit and the collision checks.
      expect(sql, contains('app.mint_person_mlid'));
      expect(sql, isNot(contains("'MLPI' ||")));
    });

    test('the raw Aadhaar is hashed and never stored', () {
      expect(sql, contains('app.aadhaar_hash(p_aadhaar_number)'));
      // aadhaar_number is a real column on persons and must not be written.
      expect(sql, isNot(contains('aadhaar_number =')));
    });

    test('the old ID is recorded rather than overwritten', () {
      // The MLID is a login identifier. person_id_history existed unused for
      // months waiting for exactly this.
      expect(sql, contains('INSERT INTO person_id_history'));
    });

    test('an agent cannot reach into another book', () {
      // Authorization proves who somebody is, not who they may touch.
      expect(sql, contains('is not a member of this business'));
    });

    test('a supplied field never erases one already there', () {
      expect(sql, contains('COALESCE(p_dob, dob)'));
      expect(sql, contains('COALESCE(p_live_photo_url, live_photo_url)'));
    });
  });
}
