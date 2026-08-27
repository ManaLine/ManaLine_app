import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// What this pins: the tabbed Customer Profile drill-in had no test at all.
/// Only the landing list was covered, so the profile's own rows were never
/// laid out at scale by anything.
///
/// The Summary and Loans tabs build label/value rows as
/// `Row(children: [Expanded(label), value])` -- a bare unflexible child beside
/// a flexible one, which is the exact shape that has shipped as an overflow
/// four times in this project. AG-004 guards its identical rows with
/// maxLines/ellipsis; OW-004's do not, so the defect is visible only here.
///
/// The values that overflow are real: a father/husband name, a joined address,
/// a translated occupation. None of them are short in Telugu.
class _SeededProfileNotifier extends CustomerProfileNotifier {
  _SeededProfileNotifier(this._seed);
  final CustomerProfile _seed;

  @override
  Future<CustomerProfile> build(String customerId) async => _seed;
}

/// The profile drill-in's own keys, translated. Width is data -- see the note
/// in mana_translations_fixture.dart.
const _profileTelugu = <String, Map<String, String>>{
  'summary': {'English': 'Summary', 'Telugu': 'సారాంశం'},
  'loans': {'English': 'Loans', 'Telugu': 'రుణాలు'},
  'collections': {'English': 'Collections', 'Telugu': 'వసూళ్లు'},
  'documents': {'English': 'Documents', 'Telugu': 'పత్రాలు'},
  'remarks': {'English': 'Remarks', 'Telugu': 'వ్యాఖ్యలు'},
  'history': {'English': 'History', 'Telugu': 'చరిత్ర'},
  'audit': {'English': 'Audit', 'Telugu': 'ఆడిట్'},
  'father_husband_name': {'English': 'Father / Husband Name', 'Telugu': 'తండ్రి / భర్త పేరు'},
  'village': {'English': 'Village', 'Telugu': 'గ్రామం'},
  'phone_number': {'English': 'Phone Number', 'Telugu': 'ఫోన్ నంబర్'},
  'occupation': {'English': 'Occupation', 'Telugu': 'వృత్తి'},
  'address': {'English': 'Address', 'Telugu': 'చిరునామా'},
  'customer_since': {'English': 'Customer Since', 'Telugu': 'కస్టమర్ నుండి'},
  'current_agent': {'English': 'Current Agent', 'Telugu': 'ప్రస్తుత ఏజెంట్'},
  'current_status': {'English': 'Current Status', 'Telugu': 'ప్రస్తుత స్థితి'},
  'line_repayment_index': {'English': 'Line Repayment Index', 'Telugu': 'లైన్ చెల్లింపు సూచిక'},
  'loan_count': {'English': 'Loan Count', 'Telugu': 'రుణాల సంఖ్య'},
  'outstanding_balance': {'English': 'Outstanding Balance', 'Telugu': 'బాకీ నిల్వ'},
};

void main() {
  final customer = CustomerSummary(
    customerId: 'c1',
    fullName: 'Nagabhushanam Venkata Subba Reddy',
    fatherHusbandName: 'Garikipati Venkata Subba Rami Reddy',
    village: 'Srikalahasti — Uranduru Colony',
    phoneNumber: '9493509919',
    mlid: 'MLCU0000012345',
    activeLoanCount: 1,
    todaysDue: 1500,
    outstandingBalance: 84500,
    lineRepaymentIndex: 12,
    customerStatus: 'Active',
    membershipStatus: 'Active',
  );

  final profile = CustomerProfile(
    summary: customer,
    occupation: 'Agricultural Labour And Dairy',
    // A real address, joined the way the profile joins it.
    address: '2-114/A, Uranduru Colony, Srikalahasti, Chittoor, Andhra Pradesh, 517644',
    customerSince: DateTime(2024, 3, 14),
    currentAgent: 'Kandukuri Siva Rama Krishna',
    loans: [
      CustomerLoanSummary(
        loanId: 'l1',
        loanNumber: 'MLLN0000098765',
        issueDate: DateTime(2026, 1, 8),
        loanAmount: 24000,
        outstanding: 12000,
        todaysDue: 2000,
        progressPercent: 50,
        status: 'Active',
      ),
    ],
  );

  Widget screen() => CustomerProfileScreen(businessId: 'b1', customer: customer);

  // Seven tabs, and TabBarView lays out only the visible one. The first
  // version of this test pumped the screen once and reported green while six
  // of the seven bodies had never been laid out at all -- the same blind spot
  // that let the Summary tab's 136px overflow ship in the first place.
  const tabCount = 7;

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      for (var i = 0; i < tabCount; i++) {
        testWidgets('Customer Profile tab $i survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            screen(),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _profileTelugu : null,
            overrides: [
              customerProfileProvider.overrideWith(() => _SeededProfileNotifier(profile)),
            ],
          );
          await tester.pumpAndSettle();

          if (i > 0) {
            await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
            await tester.pumpAndSettle();
          }
          expectNoLayoutFault(tester, 'Customer Profile tab $i at ${scale}x$tag');
        });
      }
    }
  }
}
