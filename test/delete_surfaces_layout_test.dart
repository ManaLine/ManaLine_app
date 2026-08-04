import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_007_loan_distribution.dart';
import 'package:mana_line/features/agent_workspace/state/loan_distribution_state.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_009_daily_record_book.dart';
import 'package:mana_line/features/owner_workspace/state/record_book_state.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_004_customer_management.dart';
import 'package:mana_line/features/agent_workspace/state/agent_customer_state.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/document_viewer.dart';

import 'support/mana_harness.dart';

/// Layout cover for the surfaces that gained a delete control.
///
/// Every one of them took the same edit: an icon was added beside something
/// that was already there. That is precisely the shape this repo's overflow
/// bug arrives in — a bare unflexible child acquiring a sibling — and it has
/// now shipped five times, so these are measured rather than eyeballed.
///
/// OW-019's cheti card and its instalment list are covered in
/// cheti_screen_layout_test.dart, which already owns that screen.
void main() {
  // ==========================================================================
  // Documents list — the delete icon sits beside the chevron, and the row
  // title is a translated document-type label.
  // ==========================================================================
  group('Documents list', () {
    const types = [
      'Aadhaar Card',
      'PAN Card',
      'Bank Passbook',
      'Guarantor Documents',
      'Other Documents',
    ];

    Widget docs({required bool uploaded}) => Scaffold(
          body: DocumentsListView(
            expectedTypes: types,
            fetchDocuments: () async => uploaded
                ? [
                    // documentId non-null => customer document => deletable,
                    // so the delete icon renders. This is the wide case.
                    DocumentSummary(
                      documentId: 'doc-1',
                      documentType: 'Aadhaar Card',
                      fileUrl: 'https://example.invalid/a.jpg',
                      uploadedAt: DateTime(2026, 8, 1),
                    ),
                    // documentId null => agent document => no delete action.
                    DocumentSummary(
                      documentType: 'PAN Card',
                      fileUrl: 'https://example.invalid/p.jpg',
                      uploadedAt: DateTime(2026, 8, 2),
                    ),
                  ]
                : const [],
          ),
        );

    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(tester, docs(uploaded: true), textScale: scale);
        await tester.pump(); // resolve the fetch future
        expectNoLayoutFault(tester, 'DocumentsListView at ${scale}x');
      });
    }

    testWidgets('offers delete only for documents that carry an id',
        (tester) async {
      await pumpManaScreen(tester, docs(uploaded: true));
      await tester.pump();

      // Exactly one: the customer document. The agent document has no id,
      // so no delete path exists and none is offered — a button there would
      // always fail.
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('shows no delete actions when nothing is uploaded',
        (tester) async {
      await pumpManaScreen(tester, docs(uploaded: false), textScale: 2.0);
      await tester.pump();

      expectNoLayoutFault(tester, 'DocumentsListView empty at 2.0x');
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  // ==========================================================================
  // AG-007 cash transfers — the delete icon was added beside a Confirm
  // button on one list and a "Pending" pill on the other. Both are the
  // trailing slot of a ListTile, which is width-constrained.
  // ==========================================================================
  group('AG-007 cash transfer list', () {
    const agentId = 'agent-self';

    CashTransfer transfer({
      required String id,
      required bool incoming,
      int amount = 125000,
    }) =>
        CashTransfer(
          transferId: id,
          fromAgentId: incoming ? 'agent-other' : agentId,
          // Long, real-shaped names: the tile title is "From <name>".
          fromAgentName: incoming ? 'Venkata Subrahmanyam' : 'Self',
          toAgentId: incoming ? agentId : 'agent-other',
          toAgentName: incoming ? 'Self' : 'Lakshmi Narasimha Rao',
          amount: amount,
          businessDate: '2026-08-04',
          createdAt: DateTime(2026, 8, 4),
          // Neither side confirmed: the incoming list shows Confirm, the
          // outgoing one shows the Pending pill. Both render a delete icon.
          fromAgentConfirmedAt: incoming ? DateTime(2026, 8, 4) : null,
        );

    List<Override> overrides() => [
          loanDistributionProvider.overrideWith(() => _SeededTransfers([
                transfer(id: 't1', incoming: true),
                transfer(id: 't2', incoming: false),
              ])),
        ];

    for (final scale in kManaTextScales) {
      testWidgets('survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const Ag007LoanDistributionScreen(
              agentId: agentId, businessId: 'b1'),
          textScale: scale,
          overrides: overrides(),
        );
        await tester.pump();

        expectNoLayoutFault(tester, 'AG-007 transfers at ${scale}x');
      });
    }
  });

  group('OW-009 day details', () {
    List<Override> overrides() =>
        [recordBookProvider.overrideWith(_SeededRecordBook.new)];

    for (final scale in kManaTextScales) {
      testWidgets('entry tiles survive text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const DailyRecordBookScreen(businessId: 'b1'),
          textScale: scale,
          overrides: overrides(),
        );

        // The entries live in a bottom sheet opened by tapping a ledger row.
        await tester.tap(find.byType(InkWell).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expectNoLayoutFault(tester, 'OW-009 day details at ${scale}x');
      });
    }
  });

  group('Remarks tabs', () {
    for (final scale in kManaTextScales) {
      testWidgets('AG-004 remarks survive text scale ${scale}x',
          (tester) async {
        await pumpManaScreen(
          tester,
          const AgentCustomerProfileScreen(
            businessId: 'b1',
            agentMembershipId: 'm1',
            customerId: 'cust-1',
            customerName: 'Venkata Subrahmanyam',
          ),
          textScale: scale,
          overrides: [
            agentCustomerProfileProvider
                .overrideWith(_SeededAgentProfile.new),
          ],
        );
        // The profile is an AsyncNotifier: one pump still shows the
        // spinner, so the tab bar is not tappable yet.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Remarks is the FOURTH tab. Without this the test measures the
        // Summary tab and proves nothing about the row that changed.
        // The TabBar is isScrollable with four tabs, so on a 360dp surface
        // 'Remarks' starts off-screen and a bare tap never lands on it.
        await tester.ensureVisible(find.text('Remarks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remarks'));
        // pumpAndSettle, not a fixed budget: the TabBarView slide plus the
        // tab-indicator animation together outlast any guess, and this
        // screen has no perpetual shimmer to hang on.
        await tester.pumpAndSettle();

        expectNoLayoutFault(tester, 'AG-004 remarks at ${scale}x');
        expect(find.textContaining('revised collection time'), findsOneWidget);
        // findsWidgets, not a count: at larger scales the second remark is
        // below the fold and the sliver never builds it.
        expect(find.byIcon(Icons.delete_outline), findsWidgets);
      });
    }

    for (final scale in kManaTextScales) {
      testWidgets('OW-004 remarks survive text scale ${scale}x',
          (tester) async {
        await pumpManaScreen(
          tester,
          CustomerProfileScreen(
            businessId: 'b1',
            customer: _profileWithRemarks().summary,
          ),
          textScale: scale,
          overrides: [
            customerProfileProvider.overrideWith(_SeededOwnerProfile.new),
          ],
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Seven tabs here, so 'Remarks' is even further off-screen than on
        // AG-004's four.
        await tester.ensureVisible(find.text('Remarks'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remarks'));
        await tester.pumpAndSettle();

        expectNoLayoutFault(tester, 'OW-004 remarks at ${scale}x');
        expect(find.textContaining('revised collection time'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsWidgets);
      });
    }
  });
}

// ============================================================================
// OW-009 day details — the delete icon was added to the trailing Row of
// every entry tile, beside an amount that already shared the slot with a
// Correction pill and an open-source button.
// ============================================================================
DayLedgerRow _ledgerRow() => DayLedgerRow(
      businessDate: DateTime(2026, 8, 4),
      openingBalance: 250000,
      totalCollections: 187500,
      totalLoanDistribution: 120000,
      investorDeposits: 0,
      investorWithdrawals: 0,
      totalExpenses: 4750,
      shortAmount: 0,
      excessAmount: 0,
      closingBalance: 312750,
      status: 'Open',
    );

DayDetailEntry _entry(String id, String label, int amount,
        {bool isCorrection = false, String? sourceLoanId}) =>
    DayDetailEntry(
      id: id,
      label: label,
      amount: amount,
      timestamp: DateTime(2026, 8, 4, 10, 30),
      isCorrection: isCorrection,
      sourceLoanId: sourceLoanId,
    );

/// The worst case the tile can hold at once: a long borrower name, a
/// six-figure amount, the Correction pill AND the open-source button, plus
/// the new delete icon.
DayDetail _dayDetail() => DayDetail(
      ledger: _ledgerRow(),
      collections: [
        _entry('c1', 'Venkata Subrahmanyam — RCT-20260804-a1b2c3', 125000,
            isCorrection: true, sourceLoanId: 'loan-1'),
        _entry('c2', 'Lakshmi Narasimha Rao', 62500, sourceLoanId: 'loan-2'),
      ],
      expenses: [_entry('e1', 'Fuel', 4750)],
      adjustments: [_entry('a1', 'Short — settlement 4 Aug', 250)],
    );

class _SeededRecordBook extends RecordBookNotifier {
  @override
  RecordBookState build() => RecordBookState(
        rows: [_ledgerRow()],
        selectedDate: DateTime(2026, 8, 4),
        dayDetail: _dayDetail(),
      );

  @override
  Future<void> load(String businessId,
      {DateTime? dateFrom, DateTime? dateTo, String? status}) async {}

  @override
  Future<void> openDayDetails(String businessId, DateTime date) async {}
}

/// Seeds the transfer list without touching the network. loadTransfers is
/// overridden to a no-op because the screen calls it from initState.
class _SeededTransfers extends LoanDistributionNotifier {
  final List<CashTransfer> _seed;
  _SeededTransfers(this._seed);

  @override
  LoanDistributionState build() => LoanDistributionState(transfers: _seed);

  @override
  Future<void> loadTransfers({required String agentId}) async {}
}

// ============================================================================
// Remarks tabs — Owner (OW-004) and Agent (AG-004) render the same shape: a
// priority pill that now shares ListTile.trailing with a delete icon. Both
// are exercised because they are separate files that drifted apart before.
// ============================================================================
CustomerProfile _profileWithRemarks() => CustomerProfile(
      summary: CustomerSummary(
        customerId: 'cust-1',
        fullName: 'Venkata Subrahmanyam',
        fatherHusbandName: 'Ramakrishna',
        village: 'Chintalapudi',
        phoneNumber: '9876543210',
        mlid: 'ML-000123',
        activeLoanCount: 2,
        todaysDue: 1250,
        outstandingBalance: 87500,
        lineRepaymentIndex: 0,
        customerStatus: 'Active',
        membershipStatus: 'Active',
      ),
      customerSince: DateTime(2025, 3, 1),
      remarks: [
        // High priority renders the red pill — the widest variant — and the
        // remark text is deliberately long enough to wrap.
        CustomerRemark(
          remarkId: 'r1',
          date: DateTime(2026, 8, 1),
          enteredBy: 'Lakshmi Narasimha Rao',
          remark: 'Customer requested a revised collection time; not at home '
              'before 6pm on weekdays.',
          priority: 'High',
        ),
        CustomerRemark(
          remarkId: 'r2',
          date: DateTime(2026, 7, 20),
          enteredBy: 'Self',
          remark: 'Paid in full.',
          priority: 'Normal',
        ),
      ],
    );

class _SeededAgentProfile extends AgentCustomerProfileNotifier {
  @override
  Future<CustomerProfile> build(String customerId) async =>
      _profileWithRemarks();
}

class _SeededOwnerProfile extends CustomerProfileNotifier {
  @override
  Future<CustomerProfile> build(String customerId) async =>
      _profileWithRemarks();
}
