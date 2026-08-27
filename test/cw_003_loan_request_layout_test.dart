import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_003_request_new_loan.dart';
import 'package:mana_line/features/customer_workspace/state/loan_request_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// CW-003 is where a customer asks for money. Nine phases, each drawing a
/// different body, and none of them had ever been laid out at text scale.
class _SeededLoanRequest extends LoanRequestNotifier {
  _SeededLoanRequest(this._seed);
  final LoanRequestState _seed;

  @override
  LoanRequestState build() => _seed;

  // The screen loads its gate in initState. Seeded here instead, per the
  // harness rule: left to reach the network it would lay out an empty state
  // and prove nothing.
  @override
  Future<void> loadGateAndTemplates({
    required String businessId,
    required bool customerLoanRequestsAllowed,
    required bool businessAllowsCustomAmount,
  }) async {}
}

/// Returns no prior requests, so the cooldown recovery in initState is a
/// no-op and the seeded phase is what gets laid out.
class _NoRequestsApi extends LoanRequestApiService {
  _NoRequestsApi(Ref ref) : super(ref: ref);

  @override
  Future<List<LoanRequestResult>> fetchOwnRequests({required String customerId}) async => [];
}

void main() {
  final template = LoanTemplateSummary(
    templateId: 't1',
    templateName: 'Weekly Vaddi — Ten Thousand, Twenty Weeks',
    defaultAmount: 1284500,
    durationValue: 20,
    repaymentFrequency: 'Weekly',
  );

  final result = LoanRequestResult(
    requestId: 'r1',
    status: 'Pending',
    requestedAmount: 1284500,
    purposeRemark: 'Seed, fertiliser and labour for the groundnut season',
    preferredFrequency: 'Weekly',
    rejectionReason: 'Outstanding balance on an existing loan is still above the limit',
    cooldownUntil: DateTime(2026, 8, 28),
    createdAt: DateTime(2026, 8, 26),
  );

  for (final phase in LoanRequestPhase.values) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('CW-003 ${phase.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const RequestNewLoanScreen(
              businessId: 'b1',
              customerId: 'c1',
              customerLoanRequestsAllowed: true,
              businessAllowsCustomAmount: true,
            ),
            textScale: scale,
            language: lang,
            overrides: [
              loanRequestApiServiceProvider.overrideWith((ref) => _NoRequestsApi(ref)),
              loanRequestProvider.overrideWith(
                () => _SeededLoanRequest(LoanRequestState(
                  phase: phase,
                  customerLoanRequestsAllowed: true,
                  businessOffersTemplates: true,
                  businessAllowsCustomAmount: true,
                  templates: [template],
                  selectedTemplate: template,
                  requestedAmountText: '1284500',
                  purposeRemark: 'Seed, fertiliser and labour for the groundnut season',
                  lastResult: result,
                )),
              ),
            ],
          );
          expectNoLayoutFault(tester, 'CW-003 ${phase.name} at ${scale}x$tag');
        });
      }
    }
  }
}
