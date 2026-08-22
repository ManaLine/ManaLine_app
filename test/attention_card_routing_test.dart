import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/state/owner_api_service.dart';

/// "Attention Required leads to nothing on tap."
///
/// It DID navigate — to the agent roster — but the roster mentions no dispute
/// and offers no way to correct a float, so from the Owner's side it may as
/// well have done nothing. A card that flags a problem has to land on the
/// screen where that problem is fixed.
void main() {
  test('a card can name who it is about', () {
    final card = AttentionCard(
      type: 'Disputed Opening BF',
      count: 1,
      priority: 'High',
      lastUpdated: DateTime(2026, 8, 20),
      focusAgentId: 'agent-1',
    );

    expect(card.focusAgentId, 'agent-1');
  });

  test('a card about no one in particular still works', () {
    // Two agents disputing: the roster IS the right destination, because
    // jumping into one of them would hide the other.
    final card = AttentionCard(
      type: 'Disputed Opening BF',
      count: 2,
      priority: 'High',
      lastUpdated: DateTime(2026, 8, 20),
    );

    expect(card.focusAgentId, isNull);
  });
}
