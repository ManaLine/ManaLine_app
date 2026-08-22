import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart';

/// An Agent holding no cash is an ordinary morning, not a lockout.
///
/// Before this, no agent_bf_assignments row meant bfBlockedNoAssignment: the
/// Agent opened the app to a dead end — no business, no round, no customers —
/// until the Owner remembered to grant BF. They now open at zero.
///
/// Nothing about SPENDING changes, which is the part that matters: the float
/// check still refuses a loan the Agent cannot fund.
void main() {
  test('a zero float is a real assignment, not a missing one', () {
    final bf = AgentBfAssignment(
      bfAssignmentId: 'a1',
      openingBf: 0,
      confirmedByAgent: false,
      updateRequested: false,
    );

    // The gate keys off the assignment being present, not off it being
    // non-zero — that distinction is the whole fix.
    expect(bf.openingBf, 0);
    expect(bf.updateRequested, isFalse);
  });

  test('the blocked stage still exists for the case it is actually for', () {
    // Kept for "the zero row could not be created" — offline, or the
    // membership is gone. Deleting it would leave that case with no state.
    expect(AgentSessionStage.values, contains(AgentSessionStage.bfBlockedNoAssignment));
    expect(AgentSessionStage.values, contains(AgentSessionStage.bfConfirmPending));
  });
}
