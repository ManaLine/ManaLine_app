import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_014_global_workflow.dart';
import 'package:mana_line/features/owner_workspace/state/global_workflow_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

class _Seeded extends GlobalWorkflowNotifier {
  _Seeded(this._seed);
  final GlobalWorkflowState _seed;

  @override
  GlobalWorkflowState build() => _seed;

  @override
  void initWithType(MemberType? type) {}
}

final _found = GlobalWorkflowState(
  memberType: MemberType.customer,
  stage: WizardStage.found,
  searchResult: PersonSearchResult(
    personId: 'p1',
    fullName: 'Karri Siri Manikanta Reddy',
    mlid: 'MLCU0000012345',
    mobileNumber: '9493509919',
  ),
);

const _selectType = GlobalWorkflowState(stage: WizardStage.selectType);
const _searchMlid = GlobalWorkflowState(memberType: MemberType.agent, stage: WizardStage.searchMlid);
const _notFound = GlobalWorkflowState(memberType: MemberType.customer, stage: WizardStage.notFound);
const _incomplete = GlobalWorkflowState(
  memberType: MemberType.customer,
  stage: WizardStage.incomplete,
  createdPersonId: 'p1',
  createdMembershipId: 'm1',
);

const _telugu = <String, Map<String, String>>{
  'add_existing_member': {'English': 'Add Existing Member', 'Telugu': 'ఇప్పటికే ఉన్న సభ్యుడిని జోడించండి'},
  'select_member_type': {'English': 'Select Member Type', 'Telugu': 'సభ్య రకాన్ని ఎంచుకోండి'},
  'search_existing_mlid': {'English': 'Search Existing MLID', 'Telugu': 'ఇప్పటికే ఉన్న MLID శోధించండి'},
  'type_note': {'English': 'Type: {type}', 'Telugu': 'రకం: {type}'},
  'mobile_number_field': {'English': 'Mobile Number', 'Telugu': 'మొబైల్ నంబర్'},
  'or_separator': {'English': '— OR —', 'Telugu': '— లేదా —'},
  'mlid_field': {'English': 'MLID', 'Telugu': 'MLID'},
  'search': {'English': 'Search', 'Telugu': 'శోధించండి'},
  'identity_found': {'English': 'Identity Found', 'Telugu': 'గుర్తింపు కనుగొనబడింది'},
  'mlid_colon_note': {'English': 'MLID: {mlid}', 'Telugu': 'MLID: {mlid}'},
  'request_business_membership': {'English': 'Request Business Membership', 'Telugu': 'వ్యాపార సభ్యత్వం అభ్యర్థించండి'},
  'minimum_information': {'English': 'Minimum Information', 'Telugu': 'కనీస సమాచారం'},
  'full_name_field': {'English': 'Full Name *', 'Telugu': 'పూర్తి పేరు *'},
  'father_husband_name_field': {'English': 'Father / Husband Name *', 'Telugu': 'తండ్రి / భర్త పేరు *'},
  'village_required_field': {'English': 'Village *', 'Telugu': 'గ్రామం *'},
  'mobile_number_optional_field': {'English': 'Mobile Number (optional)', 'Telugu': 'మొబైల్ నంబర్ (ఐచ్ఛికం)'},
  'area_locality_optional_field': {'English': 'Area / Locality (optional)', 'Telugu': 'ప్రాంతం / స్థానికత (ఐచ్ఛికం)'},
  'remarks_optional_field': {'English': 'Remarks (optional)', 'Telugu': 'వ్యాఖ్యలు (ఐచ్ఛికం)'},
  'save': {'English': 'Save', 'Telugu': 'సేవ్ చేయండి'},
  'incomplete_profile': {'English': 'Incomplete Profile', 'Telugu': 'అసంపూర్ణ ప్రొఫైల్'},
  'incomplete_profile_note': {
    'English': 'This member exists as an internal record only, usable for manual/offline collection and record-keeping. Cannot receive SMS, receive OTP, accept agreements, or request online services until profile completion.',
    'Telugu': 'ఈ సభ్యుడు అంతర్గత రికార్డుగా మాత్రమే ఉన్నారు, మాన్యువల్/ఆఫ్‌లైన్ వసూలు మరియు రికార్డు నిర్వహణకు ఉపయోగపడతారు. ప్రొఫైల్ పూర్తయ్యే వరకు SMS, OTP అందుకోలేరు, ఒప్పందాలు అంగీకరించలేరు, లేదా ఆన్‌లైన్ సేవలు అభ్యర్థించలేరు.',
  },
  'complete_profile': {'English': 'Complete Profile', 'Telugu': 'ప్రొఫైల్ పూర్తి చేయండి'},
  'complete_profile_note': {
    'English': 'Capture Photo, Password, Address, PIN Code, Village, Identity Documents, OTP Verification, Terms Acceptance.',
    'Telugu': 'ఫోటో, పాస్‌వర్డ్, చిరునామా, పిన్ కోడ్, గ్రామం, గుర్తింపు పత్రాలు, OTP ధృవీకరణ, నిబంధనల అంగీకారం తీసుకోండి.',
  },
};

void main() {
  for (final stage in [
    ('select type', _selectType),
    ('search mlid', _searchMlid),
    ('found', _found),
    ('not found', _notFound),
    ('incomplete', _incomplete),
  ]) {
    for (final scale in kManaTextScales) {
      testWidgets('OW-014 ${stage.$1} survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const GlobalWorkflowScreen(businessId: 'b1', currentOwnerPersonId: '1'),
          textScale: scale,
          overrides: [globalWorkflowProvider.overrideWith(() => _Seeded(stage.$2))],
        );
        expectNoLayoutFault(tester, 'OW-014 ${stage.$1} at ${scale}x');
      });

      testWidgets('OW-014 ${stage.$1} survives text scale ${scale}x in Telugu', (tester) async {
        await pumpManaScreen(
          tester,
          const GlobalWorkflowScreen(businessId: 'b1', currentOwnerPersonId: '1'),
          textScale: scale,
          language: ManaLanguage.telugu,
          translations: _telugu,
          overrides: [globalWorkflowProvider.overrideWith(() => _Seeded(stage.$2))],
        );
        expectNoLayoutFault(tester, 'OW-014 ${stage.$1} at ${scale}x in Telugu');
      });
    }
  }

  testWidgets('OW-014 shows the found identity', (tester) async {
    await pumpManaScreen(
      tester,
      const GlobalWorkflowScreen(businessId: 'b1', currentOwnerPersonId: '1'),
      overrides: [globalWorkflowProvider.overrideWith(() => _Seeded(_found))],
    );
    expect(find.textContaining('Karri Siri Manikanta Reddy'), findsOneWidget);
  });
}
