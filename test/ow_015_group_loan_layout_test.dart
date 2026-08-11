import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_015_group_loan_management.dart';
import 'package:mana_line/features/owner_workspace/state/group_loan_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _SeededList extends GroupLoanListNotifier {
  _SeededList(this._seed);
  final GroupLoanListState _seed;

  @override
  GroupLoanListState build() => _seed;

  @override
  Future<void> load(String businessId) async {}
}

class _SeededDetail extends GroupLoanDetailNotifier {
  @override
  Future<GroupLoanDetail> build(String groupId) async => _detail;
}

final _detail = GroupLoanDetail(
  summary: GroupSummary(groupId: 'g1', groupName: 'Srikalahasti Womens Group', memberCount: 2),
  members: [
    GroupMemberLoan(
      loanId: 'l1',
      customerName: 'Peddireddy Venkata Subbamma',
      loanNumber: 'MLLN0000012345',
      remainingBalance: 22000,
      installmentAmount: 500,
      status: 'Active',
    ),
    GroupMemberLoan(
      loanId: 'l2',
      customerName: 'Lakshmi Narasimha Rao',
      loanNumber: 'MLLN0000012346',
      remainingBalance: 0,
      installmentAmount: 0,
      status: 'Closed',
    ),
  ],
);

final _withGroups = GroupLoanListState(groups: [
  GroupSummary(groupId: 'g1', groupName: 'Srikalahasti Womens Group', memberCount: 2),
]);
const _empty = GroupLoanListState();

const _telugu = <String, Map<String, String>>{
  'group_loan_management': {'English': 'Group Loan Management', 'Telugu': 'గ్రూప్ రుణ నిర్వహణ'},
  'create_group': {'English': 'Create Group', 'Telugu': 'గ్రూప్ సృష్టించండి'},
  'no_groups_yet': {'English': 'No groups yet', 'Telugu': 'ఇంకా గ్రూపులు లేవు'},
  'no_groups_yet_detail': {
    'English': 'A group is formed from customers who already have a loan — it groups them for collection only, and does not merge their money. Create the loans first, then come back and group them.',
    'Telugu': 'ఇప్పటికే రుణం ఉన్న కస్టమర్ల నుండి గ్రూప్ ఏర్పడుతుంది — ఇది వసూలు కోసం మాత్రమే వారిని కలుపుతుంది, వారి డబ్బును కలపదు. ముందుగా రుణాలు సృష్టించి, తర్వాత వాటిని గ్రూప్ చేయండి.',
  },
  'members_count_note': {'English': '{count} members', 'Telugu': '{count} సభ్యులు'},
  'group_detail': {'English': 'Group Detail', 'Telugu': 'గ్రూప్ వివరాలు'},
  'group_balance': {'English': 'Group Balance', 'Telugu': 'గ్రూప్ నిల్వ'},
  'group_emi': {'English': 'Group EMI', 'Telugu': 'గ్రూప్ EMI'},
  'computed_live_note': {'English': 'Computed live from member loans — never stored.', 'Telugu': 'సభ్య రుణాల నుండి ప్రత్యక్షంగా లెక్కించబడుతుంది — ఎప్పుడూ నిల్వ చేయబడదు.'},
  'members': {'English': 'Members', 'Telugu': 'సభ్యులు'},
  'balance_emi_note': {'English': 'Balance {balance} · EMI {emi}', 'Telugu': 'నిల్వ {balance} · EMI {emi}'},
  'membership_fixed_note': {
    'English': 'Membership is fixed permanently at creation — no additions or removals.',
    'Telugu': 'సభ్యత్వం సృష్టి సమయంలో శాశ్వతంగా నిర్ణయించబడుతుంది — జోడింపులు లేదా తొలగింపులు లేవు.',
  },
};

void main() {
  for (final c in [('list', _withGroups), ('empty', _empty)]) {
    for (final scale in kManaTextScales) {
      testWidgets('OW-015 ${c.$1} survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(tester, const GroupLoanManagementScreen(businessId: 'b1'),
            textScale: scale, overrides: [groupLoanListProvider.overrideWith(() => _SeededList(c.$2))]);
        expectNoLayoutFault(tester, 'OW-015 ${c.$1} at ${scale}x');
      });

      testWidgets('OW-015 ${c.$1} survives text scale ${scale}x in Telugu', (tester) async {
        await pumpManaScreen(tester, const GroupLoanManagementScreen(businessId: 'b1'),
            textScale: scale,
            language: ManaLanguage.telugu,
            translations: _telugu,
            overrides: [groupLoanListProvider.overrideWith(() => _SeededList(c.$2))]);
        expectNoLayoutFault(tester, 'OW-015 ${c.$1} at ${scale}x in Telugu');
      });
    }
  }

  for (final scale in kManaTextScales) {
    testWidgets('OW-015 group detail survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(tester, const GroupLoanDetailScreen(groupId: 'g1'),
          textScale: scale, overrides: [groupLoanDetailProvider.overrideWith(_SeededDetail.new)]);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-015 detail at ${scale}x');
    });

    testWidgets('OW-015 group detail survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(tester, const GroupLoanDetailScreen(groupId: 'g1'),
          textScale: scale,
          language: ManaLanguage.telugu,
          translations: _telugu,
          overrides: [groupLoanDetailProvider.overrideWith(_SeededDetail.new)]);
      await tester.pump();
      expectNoLayoutFault(tester, 'OW-015 detail at ${scale}x in Telugu');
    });
  }

  testWidgets('OW-015 shows the group', (tester) async {
    await pumpManaScreen(tester, const GroupLoanManagementScreen(businessId: 'b1'),
        overrides: [groupLoanListProvider.overrideWith(() => _SeededList(_withGroups))]);
    expect(find.textContaining('Srikalahasti Womens Group'), findsOneWidget);
  });
}
