import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_012_business_management.dart';
import 'package:mana_line/features/owner_workspace/state/business_management_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

final _business1 = BusinessSummary(
  businessId: 'b1',
  mlbi: 'MLBI0000012345',
  businessName: 'Sri Lakshmi Finance',
  businessStatus: 'Active',
  operatingAreaCount: 3,
  activeCustomers: 42,
  activeAgents: 2,
  activeInvestors: 1,
);

final _business2 = BusinessSummary(
  businessId: 'b2',
  mlbi: 'MLBI0000012346',
  businessName: 'Venkata Subrahmanyam Finance',
  businessStatus: 'Not Started',
  operatingAreaCount: 0,
  activeCustomers: 0,
  activeAgents: 0,
  activeInvestors: 0,
);

class _SeededBusinessListNotifier extends BusinessListNotifier {
  @override
  BusinessListState build() => BusinessListState(businesses: [_business1, _business2]);

  @override
  Future<void> load() async {}
}

final _area1 = OperatingAreaSummary(
  operatingAreaId: 'a1',
  name: 'Srikalahasti Round',
  villages: [
    AreaVillage(operatingAreaLocationId: 'ol1', locationId: 'l1', pinCode: '517644', villageTownName: 'Srikalahasti'),
  ],
  status: 'Active',
  accountCycleDuration: 3,
  accountCycleUnit: 'Days',
  submissionTime: '21:00',
  assignedAgents: [AreaAgent(agentId: 'ag1', membershipId: 'm1', fullName: 'Chalasani Ramana')],
);

final _area2 = OperatingAreaSummary(
  operatingAreaId: 'a2',
  name: 'Uranduru Round',
  villages: [
    AreaVillage(operatingAreaLocationId: 'ol2', locationId: 'l2', pinCode: '517644', villageTownName: 'Uranduru Colony'),
  ],
  status: 'Inactive',
  assignedAgents: const [],
);

final _agreement1 = AgreementSummary(
  agreementId: 'ag1',
  agreementType: 'Customer',
  sourceType: 'In-App',
  version: 1,
  effectiveDate: '2026-01-01',
);

final _member1 = MemberSummary(
  membershipId: 'm1',
  personId: 'p1',
  fullName: 'Chalasani Ramana',
  role: 'Agent',
  membershipStatus: 'Active',
);

final _membershipRequest1 = MembershipRequestSummary(
  requestId: 'r1',
  personId: 'p2',
  fullName: 'Peddireddy Venkata Subbamma',
  requestedRole: 'Investor',
  proposedInvestmentAmount: 50000,
);

final _accountPeriod1 = AccountPeriodSummary(
  accountPeriodId: 'ap1',
  operatingAreaId: 'a1',
  operatingAreaLabel: 'Srikalahasti Round',
  agentName: 'Chalasani Ramana',
  businessStartDate: DateTime(2026, 8, 1),
  plannedBusinessEndDate: DateTime(2026, 8, 3),
  status: 'Submitted',
);

class _SeededBusinessDetailNotifier extends BusinessDetailNotifier {
  @override
  BusinessDetailState build(String businessId) => BusinessDetailState(
        detail: BusinessDetail(
          summary: _business1,
          registeredFinanceName: 'Sri Lakshmi Finance Pvt Ltd',
          acceptingNewCustomers: true,
          acceptingNewInvestors: true,
          customerLoanRequestsAllowed: true,
          migrationLocked: false,
        ),
        operatingAreas: [_area1, _area2],
        agreements: [_agreement1],
        members: [_member1],
        membershipRequests: [_membershipRequest1],
        accountPeriods: [_accountPeriod1],
      );

  @override
  Future<void> load() async {}
}

/// The real ui_translations rows this screen was wired against (migration
/// 20260808060000 + reused earlier keys).
const _ow012TeluguTranslations = <String, Map<String, String>>{
  'business_management': {'English': 'Business Management', 'Telugu': 'వ్యాపార నిర్వహణ'},
  'create_business': {'English': 'Create Business', 'Telugu': 'వ్యాపారం సృష్టించండి'},
  'areas_count_note': {'English': '{count} Areas', 'Telugu': '{count} ప్రాంతాలు'},
  'customers_count_note': {'English': '{count} Customers', 'Telugu': '{count} కస్టమర్లు'},
  'agents_count_note': {'English': '{count} Agents', 'Telugu': '{count} ఏజెంట్లు'},
  'investors_count_note': {'English': '{count} Investors', 'Telugu': '{count} పెట్టుబడిదారులు'},
  'create_business_repeat_note': {
    'English': 'This is the same Create Business step covered in first-time setup — use it here to add another business, or to start one you skipped earlier.',
    'Telugu': 'ఇది మొదటిసారి సెటప్‌లో కవర్ చేసిన అదే వ్యాపారం సృష్టించే దశ — మరో వ్యాపారాన్ని జోడించడానికి, లేదా ముందు వదిలేసిన దాన్ని ప్రారంభించడానికి దీన్ని ఉపయోగించండి.',
  },
  'add_business_photo': {'English': 'Add Business Photo', 'Telugu': 'వ్యాపార ఫోటో జోడించండి'},
  'business_name_field': {'English': 'Business Name *', 'Telugu': 'వ్యాపార పేరు *'},
  'registered_finance_name_field': {'English': 'Registered Finance Name *', 'Telugu': 'నమోదిత ఫైనాన్స్ పేరు *'},
  'business_type_field': {'English': 'Business Type', 'Telugu': 'వ్యాపార రకం'},
  'business_address_field': {'English': 'Business Address', 'Telugu': 'వ్యాపార చిరునామా'},
  'business_phone_field': {'English': 'Business Phone', 'Telugu': 'వ్యాపార ఫోన్'},
  'business_email_field': {'English': 'Business Email', 'Telugu': 'వ్యాపార ఇమెయిల్'},
  'save_business': {'English': 'Save Business', 'Telugu': 'వ్యాపారం సేవ్ చేయండి'},
  'pre_existing_business': {'English': 'Pre-Existing Business', 'Telugu': 'ముందుగా ఉన్న వ్యాపారం'},
  'cheti': {'English': 'Cheti', 'Telugu': 'చేతి'},
  'operating_areas': {'English': 'Operating Areas', 'Telugu': 'పని ప్రాంతాలు'},
  'agreements': {'English': 'Agreements', 'Telugu': 'ఒప్పందాలు'},
  'members': {'English': 'Members', 'Telugu': 'సభ్యులు'},
  'account_periods': {'English': 'Account Periods', 'Telugu': 'ఖాతా వ్యవధులు'},
  'operating_area_intro_note': {
    'English': 'An operating area is one round, covering as many villages as the round actually walks. Name it, add its first village here, then attach the rest from the area itself.',
    'Telugu': 'పని ప్రాంతం అంటే ఒక రౌండ్, అది నిజంగా నడిచే గ్రామాలన్నింటినీ కవర్ చేస్తుంది. దానికి పేరు పెట్టి, ఇక్కడ మొదటి గ్రామాన్ని జోడించి, తర్వాత మిగిలినవి ఆ ప్రాంతం నుండే జోడించండి.',
  },
  'area_name_field': {'English': 'Area Name', 'Telugu': 'ప్రాంతం పేరు'},
  'area_name_helper': {'English': 'Leave blank to name it after the first village', 'Telugu': 'ఖాళీగా వదిలితే మొదటి గ్రామం పేరుతో పేరు పెట్టబడుతుంది'},
  'pin_code_field': {'English': 'PIN Code', 'Telugu': 'పిన్ కోడ్'},
  'add_area': {'English': 'Add Area', 'Telugu': 'ప్రాంతం జోడించండి'},
  'current_operating_areas': {'English': 'Current Operating Areas', 'Telugu': 'ప్రస్తుత పని ప్రాంతాలు'},
  'inactive': {'English': 'Inactive', 'Telugu': 'నిష్క్రియం'},
  'cycle_configured_note': {'English': 'Cycle: {duration} {unit}, submits {time}', 'Telugu': 'చక్రం: {duration} {unit}, సమర్పణ {time}'},
  'account_cycle_not_configured': {'English': 'Account cycle not yet configured', 'Telugu': 'ఖాతా చక్రం ఇంకా కాన్ఫిగర్ చేయలేదు'},
  'area_options': {'English': 'Area Options', 'Telugu': 'ప్రాంతం ఎంపికలు'},
  'add_village': {'English': 'Add Village', 'Telugu': 'గ్రామం జోడించండి'},
  'agent_colon_note': {'English': 'Agent: {names}', 'Telugu': 'ఏజెంట్: {names}'},
  'manage_agents': {'English': 'Manage Agents', 'Telugu': 'ఏజెంట్లను నిర్వహించండి'},
  'assign_agent': {'English': 'Assign Agent', 'Telugu': 'ఏజెంట్ కేటాయించండి'},
  'no_agent_assigned_not_worked': {'English': 'No agent assigned — not being worked', 'Telugu': 'ఏ ఏజెంట్ కేటాయించలేదు — పని జరగడం లేదు'},
  'business_agreements_note': {
    'English': 'Business Agreements are business-specific — a multi-business Owner sets these independently per MLBI; they do not carry over.',
    'Telugu': 'వ్యాపార ఒప్పందాలు వ్యాపారానికే ప్రత్యేకం — బహుళ వ్యాపారాలున్న యజమాని వీటిని ప్రతి MLBIకి విడిగా సెట్ చేస్తారు; ఇవి బదిలీ కావు.',
  },
  'create_agreement': {'English': 'Create Agreement', 'Telugu': 'ఒప్పందం సృష్టించండి'},
  'add_existing_agent': {'English': 'Add Existing Agent', 'Telugu': 'ఇప్పటికే ఉన్న ఏజెంట్‌ను జోడించండి'},
  'add_existing_customer': {'English': 'Add Existing Customer', 'Telugu': 'ఇప్పటికే ఉన్న కస్టమర్‌ను జోడించండి'},
  'request_queue_investors': {'English': 'Request Queue (Investors)', 'Telugu': 'అభ్యర్థన క్యూ (పెట్టుబడిదారులు)'},
  'proposed_amount_note': {'English': 'Proposed: ₹{amount}', 'Telugu': 'ప్రతిపాదించినది: ₹{amount}'},
  'active_members': {'English': 'Active Members', 'Telugu': 'యాక్టివ్ సభ్యులు'},
  'reactivate': {'English': 'Reactivate', 'Telugu': 'తిరిగి యాక్టివేట్ చేయండి'},
  'suspend': {'English': 'Suspend', 'Telugu': 'సస్పెండ్ చేయండి'},
  'remove': {'English': 'Remove', 'Telugu': 'తీసివేయండి'},
  'go_to_operating_areas': {'English': 'Go To Operating Areas', 'Telugu': 'పని ప్రాంతాలకు వెళ్లండి'},
  'review': {'English': 'Review', 'Telugu': 'సమీక్షించండి'},
};

void main() {
  List<Override> listOverrides() => [businessListProvider.overrideWith(_SeededBusinessListNotifier.new)];
  List<Override> detailOverrides() => [
        ...listOverrides(),
        businessDetailProvider.overrideWith(_SeededBusinessDetailNotifier.new),
      ];

  Future<void> openDetail(WidgetTester tester) async {
    await tester.tap(find.textContaining('Sri Lakshmi Finance').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Proof it actually opened. Every test below calls this and then only
    // checks layout -- and the LIST also lays out fine, so without this a
    // tap that missed would report green for a detail nobody reached.
    expect(find.byType(TabBar), findsWidgets,
        reason: 'the business detail did not open');
  }

  for (final scale in kManaTextScales) {
    testWidgets('OW-012 business list survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: scale,
        overrides: listOverrides(),
      );
      expectNoLayoutFault(tester, 'OW-012 business list at ${scale}x');
    });

    testWidgets('OW-012 business list survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow012TeluguTranslations,
        overrides: listOverrides(),
      );
      expectNoLayoutFault(tester, 'OW-012 business list at ${scale}x in Telugu');
    });

    testWidgets('OW-012 operating areas tab survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: scale,
        overrides: detailOverrides(),
      );
      await openDetail(tester);
      expectNoLayoutFault(tester, 'OW-012 operating areas at ${scale}x');
    });

    testWidgets('OW-012 operating areas tab survives text scale ${scale}x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: scale,
        language: ManaLanguage.telugu,
        translations: _ow012TeluguTranslations,
        overrides: detailOverrides(),
      );
      await openDetail(tester);
      expectNoLayoutFault(tester, 'OW-012 operating areas at ${scale}x in Telugu');
    });

    // The detail has five tabs and TabBarView lays out only the visible one,
    // so the two tests above covered Operating Areas and nothing else. The
    // other four are walked here.
    for (var i = 1; i < 5; i++) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
        testWidgets('OW-012 detail tab $i survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const BusinessManagementScreen(),
            textScale: scale,
            language: lang,
            translations: lang == ManaLanguage.telugu ? _ow012TeluguTranslations : null,
            overrides: detailOverrides(),
          );
          await openDetail(tester);
          // ensureVisible first: the TabBar scrolls, so a later tab sits
          // off-screen and a tap with warnIfMissed off lands on nothing
          // in silence -- which is how these walks reported every tab
          // clean while never leaving the first one.
          await tester.ensureVisible(find.byType(Tab).at(i));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(Tab).at(i), warnIfMissed: false);
          await tester.pumpAndSettle();
          expectNoLayoutFault(tester, 'OW-012 detail tab $i at ${scale}x$tag');
        });
      }
    }
  }

  // Lighter single-scale smoke coverage for Create Business and the
  // remaining three tabs — same ref.t()/translation pattern already
  // exercised above, fewer distinct text combinations to prove.
  testWidgets('OW-012 create business screen survives text scale 2.0x', (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessManagementScreen(),
      textScale: 2.0,
      overrides: listOverrides(),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectNoLayoutFault(tester, 'OW-012 create business at 2.0x');
  });

  testWidgets('OW-012 create business screen survives text scale 2.0x in Telugu', (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessManagementScreen(),
      textScale: 2.0,
      language: ManaLanguage.telugu,
      translations: _ow012TeluguTranslations,
      overrides: listOverrides(),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectNoLayoutFault(tester, 'OW-012 create business at 2.0x in Telugu');
  });

  for (final tab in [
    ('Agreements', 1),
    ('Members', 2),
    ('Account Periods', 3),
  ]) {
    testWidgets('OW-012 ${tab.$1} tab survives text scale 2.0x', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: 2.0,
        overrides: detailOverrides(),
      );
      await openDetail(tester);
      final tabText = find.text(tab.$1);
      await tester.ensureVisible(tabText);
      await tester.pumpAndSettle();
      await tester.tap(tabText);
      await tester.pumpAndSettle();
      expectNoLayoutFault(tester, 'OW-012 ${tab.$1} at 2.0x');
    });

    testWidgets('OW-012 ${tab.$1} tab survives text scale 2.0x in Telugu', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessManagementScreen(),
        textScale: 2.0,
        language: ManaLanguage.telugu,
        translations: _ow012TeluguTranslations,
        overrides: detailOverrides(),
      );
      await openDetail(tester);
      // TabBar labels are translated too, so find by index via ensureVisible
      // on the TabBar itself rather than the (now-Telugu) English label text.
      final tabBar = find.byType(Tab).at(tab.$2);
      await tester.ensureVisible(tabBar);
      await tester.pumpAndSettle();
      await tester.tap(tabBar);
      await tester.pumpAndSettle();
      expectNoLayoutFault(tester, 'OW-012 ${tab.$1} at 2.0x in Telugu');
    });
  }

  testWidgets('OW-012 shows the businesses', (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessManagementScreen(),
      overrides: listOverrides(),
    );
    expect(find.textContaining('Sri Lakshmi Finance'), findsOneWidget);
    expect(find.textContaining('Venkata Subrahmanyam Finance'), findsOneWidget);
  });
  // The Configure Cycle dialog, on the Operating Areas tab. One of the
  // dialogs that took scrollable: true in a sweep with no test opening it.
  //
  // Reached through a PopupMenuButton on an area row, which is two taps the
  // test has to make honestly -- and it asserts the dialog is on screen,
  // because a menu tap that lands on nothing is silent.
  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';
      testWidgets('OW-012 configure cycle dialog survives ${scale}x$tag', (tester) async {
        await pumpManaScreen(
          tester,
          const BusinessManagementScreen(),
          textScale: scale,
          language: lang,
          translations: lang == ManaLanguage.telugu ? _ow012TeluguTranslations : null,
          overrides: detailOverrides(),
        );
        await openDetail(tester);

        // Below the fold from 1.3x, so it is not built until scrolled to --
        // and the first version of this test returned early when it could not
        // find it, which is to say it proved nothing at any scale but 1.0x.
        //
        // Dragged rather than scrollUntilVisible: that helper resolves its
        // `scrollable` to exactly one element, and this tab's content does not
        // always present one.
        final menu = find.byType(PopupMenuButton<String>);
        for (var i = 0; i < 6 && menu.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(TabBarView), const Offset(0, -220));
          await tester.pumpAndSettle();
        }
        expect(menu, findsWidgets, reason: 'no area menu on the detail');
        // Present is not the same as reachable: at 2.0x it sits past the
        // bottom edge, and a tap that lands on nothing is silent.
        await tester.ensureVisible(menu.first);
        await tester.pumpAndSettle();
        await tester.tap(menu.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        final item = find.byType(PopupMenuItem<String>);
        expect(item, findsWidgets, reason: 'the area menu did not open');
        await tester.tap(item.first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget,
            reason: 'configure cycle dialog did not open');
        expectNoLayoutFault(tester, 'OW-012 configure cycle at ${scale}x$tag');
      });
    }
  }
}
