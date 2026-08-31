import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/state/agent_dashboard_state.dart';

/// The BF dispute had no way out.
///
/// An agent who disputed their opening BF landed on _BfUpdateRequestedBlock,
/// a panel with an icon and two lines of text and nothing else. The only thing
/// that clears the flag agent-side is confirm_bf_assignment, which is reached
/// from the BF gate — the screen this one replaces. So the agent was parked
/// behind a button the state itself hid, and app.grant_agent_bf did not touch
/// the flag either.
///
/// One agent on the live book sat there with Rs 10,000 already granted into
/// their float, unable to collect.
///
/// The gate is derived from the assignment on every load, so what has to hold
/// is: disputed outranks unconfirmed, and clearing the dispute drops the agent
/// onto the confirm gate rather than straight into work — because the Owner
/// changing the number does not mean the agent has agreed to it.
AgentSessionStage _stageFor({
  required bool updateRequested,
  required bool confirmedByAgent,
}) {
  // Mirrors AgentDashboardNotifier.enter's ordering.
  if (updateRequested) return AgentSessionStage.bfUpdateRequested;
  if (!confirmedByAgent) return AgentSessionStage.bfConfirmPending;
  return AgentSessionStage.areaSelection;
}

void main() {
  test('a disputed float blocks, whatever the confirmed flag says', () {
    expect(_stageFor(updateRequested: true, confirmedByAgent: false),
        AgentSessionStage.bfUpdateRequested);
    expect(_stageFor(updateRequested: true, confirmedByAgent: true),
        AgentSessionStage.bfUpdateRequested,
        reason: 'a dispute outranks an earlier confirmation');
  });

  test('the Owner answering drops the agent on the confirm gate, not into work',
      () {
    // This is what app.grant_agent_bf now writes: dispute over, agreement not
    // assumed. Landing straight in areaSelection would have the app decide on
    // the agent's behalf that they are satisfied with a number they said was
    // wrong.
    expect(_stageFor(updateRequested: false, confirmedByAgent: false),
        AgentSessionStage.bfConfirmPending);
  });

  test('confirming the corrected figure is what unblocks', () {
    expect(_stageFor(updateRequested: false, confirmedByAgent: true),
        AgentSessionStage.areaSelection);
  });

  test('the whole loop terminates', () {
    // dispute -> Owner grants -> agent confirms -> collecting. Every step
    // moves, which is precisely what the old flow could not do: the first
    // state had no exit at all.
    var stage = _stageFor(updateRequested: true, confirmedByAgent: false);
    expect(stage, AgentSessionStage.bfUpdateRequested);

    // Owner grants BF: update_requested FALSE, confirmed_by_agent FALSE.
    stage = _stageFor(updateRequested: false, confirmedByAgent: false);
    expect(stage, AgentSessionStage.bfConfirmPending);

    // Agent confirms: confirm_bf_assignment sets confirmed_by_agent TRUE.
    stage = _stageFor(updateRequested: false, confirmedByAgent: true);
    expect(stage, AgentSessionStage.areaSelection,
        reason: 'the agent can work again');
  });
}
