import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';

import 'support/mana_harness.dart';

/// One person, two memberships, one slot.
///
/// On this book the Owner is also an Agent: Karri Siri Manikanta Reddy holds
/// membership 901db2ba as Owner and fddb1acf as Agent in the same business.
/// ManaSession kept a single lastMembershipId, written by whichever role was
/// resolved last — so after a spell in the Owner workspace, every /ag- route
/// handed the Owner's membership to an Agent screen. AG-010 asked for "my
/// agent ledger" and was given the Owner's, which is how the Agent's history
/// came to show the Owner's history.
///
/// The role-specific ids beside it (agentId, customerId, investorId) were
/// already kept apart for exactly this reason. The membership was the one
/// that was not.
const _ownerMembership = '901db2ba-9f28-4c76-8c72-8199cadeca72';
const _agentMembership = 'fddb1acf-7aa1-4952-8cfc-1a54b5715976';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    seedSecureStorage();
    await ManaSession.instance.clear();
  });

  test('resolving Agent then Owner leaves the Agent membership intact',
      () async {
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _agentMembership, role: 'Agent');
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _ownerMembership, role: 'Owner');

    expect(ManaSession.instance.lastAgentMembershipId, _agentMembership,
        reason: 'the Agent screens must not be handed the Owner membership');
    expect(ManaSession.instance.lastMembershipId, _ownerMembership,
        reason: 'the generic slot still follows the most recent role');
  });

  test('the order does not matter', () async {
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _ownerMembership, role: 'Owner');
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _agentMembership, role: 'Agent');

    expect(ManaSession.instance.lastAgentMembershipId, _agentMembership);
  });

  test('an Owner who has never been an Agent falls back to the one slot',
      () async {
    // Not an Agent at all: there is no agent screen for them to reach, and
    // the fallback keeps a single-role person working exactly as before.
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _ownerMembership, role: 'Owner');

    expect(ManaSession.instance.lastAgentMembershipId, _ownerMembership);
  });

  test('logging out forgets both', () async {
    await ManaSession.instance
        .rememberResolvedIds(membershipId: _agentMembership, role: 'Agent');
    await ManaSession.instance.clear();

    expect(ManaSession.instance.lastAgentMembershipId, isNull);
    expect(ManaSession.instance.lastMembershipId, isNull);
  });
}
