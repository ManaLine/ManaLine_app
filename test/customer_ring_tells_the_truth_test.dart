import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_text.dart';
import 'package:mana_line/design/tokens/colors.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/customer_row.dart';

import 'support/mana_harness.dart';

/// The ring on a customer row said "verified" about everybody.
///
/// It was `ManaVerificationRing(isVerified: true)`, a literal, so all 99 people
/// on the live books wore a verified ring while only 8 are GREEN and 91 are
/// RED. This is the app's signature motif (BR-191/GC-002) and it was asserting
/// the opposite of the truth about 91 of them.
CustomerSummary _customer({bool? verified}) => CustomerSummary(
      customerId: 'c1',
      fullName: 'Venkata Subrahmanyam',
      fatherHusbandName: 'Satyanarayana Murthy',
      village: 'Pedanandipadu',
      phoneNumber: '9000000000',
      mlid: 'MLTI154467504',
      activeLoanCount: 1,
      todaysDue: 500,
      totalLoanAmount: 6000,
      outstandingBalance: 4500,
      lineRepaymentIndex: 0,
      customerStatus: 'Active',
      membershipStatus: 'Active',
      isVerified: verified,
    );

ManaVerificationRing _ringOf(WidgetTester tester) =>
    tester.widget<ManaVerificationRing>(find.byType(ManaVerificationRing));

void main() {
  testWidgets('a verified customer gets the verified ring', (tester) async {
    await pumpManaScreen(
      tester,
      Scaffold(body: ManaCustomerRow(customer: _customer(verified: true), onTap: () {})),
    );
    final ring = _ringOf(tester);
    expect(ring.isVerified, isTrue);
    expect(ring.ringColor, isNull, reason: 'the default colours apply');
  });

  testWidgets('an unverified customer gets the unverified ring',
      (tester) async {
    // 91 of 99 people on the live books. This is the case the old literal got
    // wrong every single time.
    await pumpManaScreen(
      tester,
      Scaffold(body: ManaCustomerRow(customer: _customer(verified: false), onTap: () {})),
    );
    final ring = _ringOf(tester);
    expect(ring.isVerified, isFalse);
    expect(ring.ringColor, isNull);
  });

  testWidgets('a customer whose ring was never loaded claims nothing',
      (tester) async {
    // Four paths build a CustomerSummary without verification_ring. Drawing
    // those as unverified would swap one confident lie for its opposite.
    await pumpManaScreen(
      tester,
      Scaffold(body: ManaCustomerRow(customer: _customer(), onTap: () {})),
    );
    expect(_ringOf(tester).ringColor, ManaColors.textSecondary);
  });

  test('the row no longer hardcodes a verification', () {
    final src = File('lib/shared/customer_row.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(src, isNot(contains('isVerified: true')),
        reason: 'a literal here is a claim about every customer at once');
  });

  test('both customer lists actually fetch the column', () {
    // A truthful widget fed by a query that never asked for the column would
    // draw every customer as not-loaded -- grey for everybody, which is a
    // quieter version of the same failure.
    for (final f in [
      'lib/features/owner_workspace/state/customer_state.dart',
      'lib/features/agent_workspace/state/agent_customer_state.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, contains('verification_ring'), reason: f);
      expect(src, contains("== 'GREEN'"), reason: f);
    }
  });

  test('no screen claims a verification it did not fetch', () {
    // Sixteen sites drew the ring from a literal `isVerified: true`. Fixing
    // one at a time is how the other fifteen survived, so this is the check
    // rather than the memory.
    //
    // TWO EXEMPTIONS, both real:
    //   design_showcase_screen draws a verified AND an unverified ring on
    //     purpose -- it is the page that shows what the component does.
    //   ow_012_business_management passes an explicit ringColor on that line,
    //     which wins over isVerified entirely, so the literal decides nothing.
    const exempt = {
      'design_showcase_screen.dart',
      'ow_012_business_management.dart',
    };

    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      // uri.pathSegments, not a regex on the path: the separator is a
      // backslash on Windows and a slash in CI, and a char class that
      // matched only one of them silently exempted nothing.
      final name = e.uri.pathSegments.last;
      if (exempt.contains(name)) continue;
      final lines = e.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].trim();
        if (code.startsWith('//') || code.startsWith('///')) continue;
        if (code.contains('isVerified: true')) {
          offenders.add('$name:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these assert that somebody is verified without having asked: '
            '$offenders');
  });

  test('the models that feed a ring can carry the answer', () {
    // A truthful widget fed by a model with nowhere to put the value would
    // render every person as not-loaded -- grey for everybody, which is the
    // same failure wearing a quieter colour.
    for (final f in [
      'lib/features/owner_workspace/state/customer_state.dart',
      'lib/features/owner_workspace/state/owner_api_service.dart',
      'lib/features/owner_workspace/state/investor_state.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, contains('final bool? isVerified;'), reason: f);
      expect(src, contains('verification_ring'), reason: f);
      expect(src, contains("== 'GREEN'"), reason: f);
    }
  });
}
