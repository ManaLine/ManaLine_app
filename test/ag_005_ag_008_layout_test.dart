import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_005_draft_transactions.dart';
import 'package:mana_line/features/agent_workspace/screens/ag_008_notifications.dart';
import 'package:mana_line/features/agent_workspace/state/agent_notifications_state.dart';
import 'package:mana_line/features/agent_workspace/state/draft_transactions_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededDrafts extends DraftTransactionsNotifier {
  @override
  DraftTransactionsState build() => _draftSeed;

  @override
  Future<void> load({required String businessId, required String membershipId}) async {}
}

class _SeededNotifications extends AgentNotificationsNotifier {
  @override
  AgentNotificationsState build() => _notifSeed;

  @override
  Future<void> load({required String businessId}) async {}
}

final _draftSeed = DraftTransactionsState(drafts: [
  DraftTransaction(
    draftId: 'd1',
    draftType: DraftType.collection,
    status: DraftStatus.draft,
    customerName: 'Peddireddy Venkata Subbamma',
    loanNumber: 'MLLN0000012345',
    createdAt: DateTime(2026, 8, 7, 10, 30),
    updatedAt: DateTime(2026, 8, 7, 10, 30),
  ),
]);

final _notifSeed = AgentNotificationsState(notifications: [
  AgentNotification(
    notificationId: 'n1',
    notificationType: AgentNotificationType.accountPeriodOverdue,
    message: 'Your Srikalahasti round account period is overdue for submission.',
    relatedEntityType: RelatedEntityType.accountPeriod,
    createdAt: DateTime(2026, 8, 7, 9, 0),
  ),
  AgentNotification(
    notificationId: 'n2',
    notificationType: AgentNotificationType.penaltyApplied,
    message: 'A penalty was applied to loan MLLN0000012345.',
    relatedEntityType: RelatedEntityType.loan,
    createdAt: DateTime(2026, 8, 6, 18, 0),
    isRead: true,
  ),
]);

const _telugu = <String, Map<String, String>>{
  'draft_transactions': {'English': 'Draft Transactions', 'Telugu': 'ముసాయిదా లావాదేవీలు'},
  'loan_number_note': {'English': 'Loan {number}', 'Telugu': 'రుణం {number}'},
  'created_note': {'English': 'Created {when}', 'Telugu': '{when}న సృష్టించబడింది'},
  'continue_draft': {'English': 'Continue Draft', 'Telugu': 'ముసాయిదా కొనసాగించండి'},
  'submit_label': {'English': 'Submit', 'Telugu': 'సమర్పించండి'},
  'discard': {'English': 'Discard', 'Telugu': 'విస్మరించండి'},
  'notifications': {'English': 'Notifications', 'Telugu': 'నోటిఫికేషన్‌లు'},
  'mark_all_read': {'English': 'Mark All Read', 'Telugu': 'అన్నీ చదివినట్లు గుర్తించండి'},
  'clear_all': {'English': 'Clear All', 'Telugu': 'అన్నీ క్లియర్ చేయండి'},
  'all': {'English': 'All', 'Telugu': 'అన్నీ'},
  'unread_count_note': {'English': 'Unread ({count})', 'Telugu': 'చదవనివి ({count})'},
  'unread': {'English': 'Unread', 'Telugu': 'చదవనివి'},
};

void main() {
  for (final scale in kManaTextScales) {
    testWidgets('AG-005 drafts survive text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const DraftTransactionsScreen(businessId: 'b1', membershipId: 'm1'),
        textScale: scale,
        overrides: [draftTransactionsProvider.overrideWith(_SeededDrafts.new)],
      );
      expectNoLayoutFault(tester, 'AG-005 at ${scale}x');
    });

    testWidgets('AG-005 drafts survive text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const DraftTransactionsScreen(businessId: 'b1', membershipId: 'm1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _telugu,
        overrides: [draftTransactionsProvider.overrideWith(_SeededDrafts.new)],
      );
      expectNoLayoutFault(tester, 'AG-005 at ${scale}x in Telugu');
    });

    testWidgets('AG-008 notifications survive text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const Ag008NotificationsScreen(agentId: 'a1', businessId: 'b1'),
        textScale: scale,
        overrides: [agentNotificationsProvider.overrideWith(_SeededNotifications.new)],
      );
      expectNoLayoutFault(tester, 'AG-008 at ${scale}x');
    });

    testWidgets('AG-008 notifications survive text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const Ag008NotificationsScreen(agentId: 'a1', businessId: 'b1'),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _telugu,
        overrides: [agentNotificationsProvider.overrideWith(_SeededNotifications.new)],
      );
      expectNoLayoutFault(tester, 'AG-008 at ${scale}x in Telugu');
    });
  }
}
