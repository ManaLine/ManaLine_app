import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What this pins: OW-011 and AG-006 now share how a money line LOOKS, and
/// nothing else.
///
/// They are the two ends of one handover -- the Owner closing the business
/// day, the Agent handing over what they hold -- and it is tempting to read
/// that as one screen. It is not. close_business_day and
/// record_day_closure_adjustment are the Owner's operations. If either ever
/// becomes reachable from the Agent's file, an Agent can close the business
/// day, and no layout test would notice.
///
/// A source-level assertion rather than a widget test, because the thing
/// being protected is which RPC a file can name at all.
void main() {
  String read(String path) => File(path).readAsStringSync();

  const agentSettlement =
      'lib/features/agent_workspace/screens/ag_006_owner_settlement.dart';
  const agentSettlementState =
      'lib/features/agent_workspace/state/agent_settlement_state.dart';
  const ownerDayClosure =
      'lib/features/owner_workspace/screens/ow_011_day_closure.dart';

  const ownerOnlyRpcs = [
    'close_business_day',
    'record_day_closure_adjustment',
    'day_closure_expected',
  ];

  test('the agent settlement path cannot reach an owner day-closure RPC', () {
    for (final path in [agentSettlement, agentSettlementState]) {
      final src = read(path);
      for (final rpc in ownerOnlyRpcs) {
        expect(src.contains(rpc), isFalse,
            reason: '$path names $rpc — an Agent must not be able to close '
                'the business day');
      }
    }
  });

  test('the owner day closure still owns those RPCs', () {
    // The other half of the assertion: if these moved somewhere else, the
    // test above would pass for the wrong reason.
    final src = read(ownerDayClosure) +
        read('lib/features/owner_workspace/state/day_closure_state.dart');
    for (final rpc in ownerOnlyRpcs) {
      expect(src.contains(rpc), isTrue, reason: '$rpc went missing');
    }
  });

  test('both screens still exist as separate screens', () {
    // The shared money row is presentation. Consolidating the SCREENS would
    // mean one file holding both operations, which is the thing this whole
    // test file exists to prevent.
    expect(File(agentSettlement).existsSync(), isTrue);
    expect(File(ownerDayClosure).existsSync(), isTrue);
  });
}
