import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_014_profile_completion.dart';
import 'package:mana_line/features/owner_workspace/state/global_workflow_state.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// `implements`, not `extends` — GlobalWorkflowApiService's constructor
/// builds an AuthApiService, which reaches Supabase.instance and asserts
/// in a widget test. noSuchMethod covers the rest of the surface.
class _FakeApi implements GlobalWorkflowApiService {
  _FakeApi(this._checklist);
  final MemberProfileChecklist _checklist;

  @override
  Future<MemberProfileChecklist> fetchProfileChecklist({required String personId}) async => _checklist;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _incomplete = MemberProfileChecklist(
  fullName: 'Karri Siri Manikanta Reddy',
  mlid: 'MLCU0000012345',
  profileStatus: 'Incomplete',
  hasPhoto: false,
  hasAddress: false,
  hasDocument: false,
  hasMobile: false,
  hasCredential: false,
  termsAccepted: false,
);

const _mostlyDone = MemberProfileChecklist(
  fullName: 'Peddireddy Venkata Subbamma',
  mlid: 'MLCU0000012346',
  profileStatus: 'Complete',
  hasPhoto: true,
  hasAddress: true,
  hasDocument: true,
  hasMobile: true,
  hasCredential: true,
  termsAccepted: true,
  addressSummary: 'Door 12-34, Uranduru Colony, Srikalahasti 517644',
);

const _telugu = <String, Map<String, String>>{
  'complete_profile': {'English': 'Complete Profile', 'Telugu': 'ప్రొఫైల్ పూర్తి చేయండి'},
  'owner_captured': {'English': 'Owner Captured', 'Telugu': 'యజమాని తీసుకున్నవి'},
  'profile_photo': {'English': 'Profile Photo', 'Telugu': 'ప్రొఫైల్ ఫోటో'},
  'captured_tap_retake': {'English': 'Captured — tap to retake', 'Telugu': 'తీసుకోబడింది — మళ్లీ తీయడానికి నొక్కండి'},
  'required_label': {'English': 'Required', 'Telugu': 'తప్పనిసరి'},
  'address_pin_village': {'English': 'Address · PIN Code · Village', 'Telugu': 'చిరునామా · పిన్ కోడ్ · గ్రామం'},
  'identity_documents': {'English': 'Identity Documents', 'Telugu': 'గుర్తింపు పత్రాలు'},
  'on_file_tap_add_another': {'English': 'On file — tap to add another', 'Telugu': 'ఫైల్‌లో ఉంది — మరొకటి జోడించడానికి నొక్కండి'},
  'mobile_dob_aadhaar': {'English': 'Mobile · DOB · Aadhaar', 'Telugu': 'మొబైల్ · పుట్టిన తేదీ · ఆధార్'},
  'mobile_on_file_tap_edit': {'English': 'Mobile on file — tap to edit', 'Telugu': 'మొబైల్ ఫైల్‌లో ఉంది — మార్చడానికి నొక్కండి'},
  'optional_needed_for_sms': {'English': 'Optional, but needed for SMS/OTP', 'Telugu': 'ఐచ్ఛికం, కానీ SMS/OTP కోసం అవసరం'},
  'member_completes_these': {'English': 'Member Completes These', 'Telugu': 'సభ్యుడు వీటిని పూర్తి చేస్తారు'},
  'member_completes_note': {
    'English': "These cannot be done on the member's behalf — the credential is theirs to set and the OTP goes to their phone.",
    'Telugu': 'ఇవి సభ్యుడి తరపున చేయలేరు — క్రెడెన్షియల్ వారు సెట్ చేయాలి మరియు OTP వారి ఫోన్‌కు వెళ్తుంది.',
  },
  'password_pin': {'English': 'Password / PIN', 'Telugu': 'పాస్‌వర్డ్ / పిన్'},
  'set_by_member': {'English': 'Set by the member', 'Telugu': 'సభ్యుడు సెట్ చేసారు'},
  'member_sets_at_first_login': {'English': 'Member sets this at First Login', 'Telugu': 'సభ్యుడు మొదటి లాగిన్‌లో దీన్ని సెట్ చేస్తారు'},
  'otp_terms_acceptance': {'English': 'OTP Verification · Terms Acceptance', 'Telugu': 'OTP ధృవీకరణ · నిబంధనల అంగీకారం'},
  'accepted_by_member': {'English': 'Accepted by the member', 'Telugu': 'సభ్యుడు అంగీకరించారు'},
  'requires_member_own_otp': {'English': "Requires the member's own verified OTP", 'Telugu': 'సభ్యుడి స్వంత ధృవీకరించిన OTP అవసరం'},
  'mark_profile_complete': {'English': 'Mark Profile Complete', 'Telugu': 'ప్రొఫైల్ పూర్తయినట్లు గుర్తించండి'},
  'owner_steps_required_note': {
    'English': 'Photo, address and at least one identity document are required first.',
    'Telugu': 'ముందుగా ఫోటో, చిరునామా మరియు కనీసం ఒక గుర్తింపు పత్రం అవసరం.',
  },
};

void main() {
  for (final c in [('incomplete', _incomplete), ('complete', _mostlyDone)]) {
    for (final scale in kManaTextScales) {
      testWidgets('OW-014 profile completion (${c.$1}) survives text scale ${scale}x', (tester) async {
        await pumpManaScreen(
          tester,
          const ProfileCompletionScreen(personId: 'p1', membershipId: 'm1'),
          textScale: scale,
          overrides: [globalWorkflowApiServiceProvider.overrideWithValue(_FakeApi(c.$2))],
        );
        await tester.pump();
        expectNoLayoutFault(tester, 'OW-014 profile completion ${c.$1} at ${scale}x');
      });

      testWidgets('OW-014 profile completion (${c.$1}) survives text scale ${scale}x in Telugu', (tester) async {
        await pumpManaScreen(
          tester,
          const ProfileCompletionScreen(personId: 'p1', membershipId: 'm1'),
          textScale: scale,
          language: ManaLanguage.telugu,
          translations: _telugu,
          overrides: [globalWorkflowApiServiceProvider.overrideWithValue(_FakeApi(c.$2))],
        );
        await tester.pump();
        expectNoLayoutFault(tester, 'OW-014 profile completion ${c.$1} at ${scale}x in Telugu');
      });
    }
  }

  testWidgets('OW-014 profile completion shows the member', (tester) async {
    await pumpManaScreen(
      tester,
      const ProfileCompletionScreen(personId: 'p1', membershipId: 'm1'),
      overrides: [globalWorkflowApiServiceProvider.overrideWithValue(_FakeApi(_incomplete))],
    );
    await tester.pump();
    expect(find.textContaining('Karri Siri Manikanta Reddy'), findsOneWidget);
  });
}
