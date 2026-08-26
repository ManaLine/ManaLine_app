import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/agent_workspace/state/agent_settlement_state.dart';
import '../../features/owner_workspace/state/owner_workspace_state.dart';
import '../../features/login_registration/state/auth_flow_state.dart';
import '../mana_time.dart';
import 'record_expense_sheet.dart';

/// Recording an expense, from wherever the person is standing.
///
/// RecordExpenseSheet already existed and already did the right thing for both
/// roles -- it was simply buried. The Owner could reach it only from Day
/// Closure, the Agent only from Settlement: both end-of-day screens, for
/// something that happens mid-round when petrol is paid for. This is the same
/// sheet, reachable from home.
///
/// Which service records it is the whole of the role difference, and it is not
/// cosmetic: an Owner's expense comes off the business, an Agent's comes off
/// the cash in their hand and changes what they hand over at settlement. The
/// sheet says which, in the payer note, because somebody paying for petrol
/// should know whose money it was.
///
/// No client-side permission gate. can_record_expenses is enforced inside
/// record_expense, and a button hidden by a stale local copy of a permission
/// is worse than one that returns the server's real refusal.
Future<bool> showQuickExpense(
  BuildContext context,
  WidgetRef ref, {
  required String businessId,

  /// The Agent's agents.agent_id. Null means the Owner is recording, and the
  /// expense belongs to the business rather than to anybody's float.
  String? agentId,
}) async {
  if (agentId != null) {
    final api = ref.read(agentSettlementApiServiceProvider);
    return RecordExpenseSheet.show(
      context,
      payerNote: 'Paid from your own cash in hand. This reduces what you '
          'hand over at settlement.',
      onSubmit: ({required category, required amount, remarks}) async {
        await api.recordExpense(
          agentId: agentId,
          businessId: businessId,
          category: category,
          amount: amount,
          businessDate: manaBusinessDate(),
          remarks: remarks,
        );
      },
    );
  }

  final personId = ref.read(authFlowProvider).personId;
  if (personId == null) return false;
  final api = ref.read(ownerApiServiceProvider);
  return RecordExpenseSheet.show(
    context,
    payerNote: 'Paid from your own balance (Owner BF).',
    onSubmit: ({required category, required amount, remarks}) async {
      final membershipId =
          await api.ownerMembershipId(businessId: businessId, personId: personId);
      await api.recordExpense(
        businessId: businessId,
        category: category,
        amount: amount,
        businessDate: manaBusinessDate(),
        membershipId: membershipId,
        remarks: remarks,
      );
    },
  );
}
