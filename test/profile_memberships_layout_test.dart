import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_006_my_profile_memberships.dart' as cw;
import 'package:mana_line/features/customer_workspace/state/customer_profile_state.dart' as cws;
import 'package:mana_line/features/investor_workspace/screens/iw_005_my_profile_memberships.dart' as iw;
import 'package:mana_line/features/investor_workspace/state/investor_profile_state.dart' as iws;
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// CW-006 and IW-005 -- the two "My Profile & Memberships" screens -- had no
/// layout coverage. Both stack an identity card over a membership list, and
/// both draw a loading state, a loaded state and an error state.
///
/// The seeded person carries a long name and a full address, and belongs to
/// several businesses: the membership list is unbounded in principle, and a
/// person who deals with three lenders is ordinary here.
class _SeededCwProfile extends cws.CustomerProfileNotifier {
  _SeededCwProfile(this._seed);
  final cws.CustomerProfileState _seed;

  @override
  cws.CustomerProfileState build() => _seed;

  @override
  Future<void> load(String personId) async {}
}

class _SeededIwProfile extends iws.InvestorProfileNotifierIW005 {
  _SeededIwProfile(this._seed);
  final iws.InvestorProfileState _seed;

  @override
  iws.InvestorProfileState build() => _seed;

  @override
  Future<void> load(String personId) async {}
}

void main() {
  const name = 'Nagabhushanam Venkata Subba Reddy';

  final cwAddress = cws.CustomerAddress(
    addressId: 'a1',
    villageName: 'Srikalahasti — Uranduru Colony',
    mandal: 'Srikalahasti',
    district: 'Chittoor',
    pinCode: '517644',
    doorNo: '2-114/A',
  );

  final iwAddress = iws.InvestorAddress(
    addressId: 'a1',
    villageName: 'Srikalahasti — Uranduru Colony',
    mandal: 'Srikalahasti',
    district: 'Chittoor',
    pinCode: '517644',
    doorNo: '2-114/A',
  );

  final cwProfile = cws.CustomerProfileSummary(
    fullName: name,
    mlid: 'MLCU0000012345',
    phoneNumber: '9493509919',
    aadhaarLast4: '4821',
    verificationRing: cws.VerificationRing.green,
    currentAddress: cwAddress,
  );

  final iwProfile = iws.InvestorProfileSummary(
    fullName: name,
    mlid: 'MLIN0000012345',
    phoneNumber: '9493509919',
    aadhaarLast4: '4821',
    verificationRing: iws.VerificationRing.green,
    currentAddress: iwAddress,
  );

  final businesses = [
    'Sri Satyanarayana Swamy Finance Corporation',
    'Venkateswara Chit Funds And Finance',
    'Lakshmi Narasimha Enterprises',
  ];

  final cwMemberships = [
    for (var i = 0; i < businesses.length; i++)
      cws.CustomerBusinessMembership(
        businessId: 'b$i',
        businessName: businesses[i],
        role: cws.MembershipRole.investor,
        membershipStatus: i == 1 ? 'Pending Invitation' : 'Active',
      ),
  ];

  final iwMemberships = [
    for (var i = 0; i < businesses.length; i++)
      iws.BusinessMembership(
        businessId: 'b$i',
        businessName: businesses[i],
        role: iws.MembershipRole.investor,
        membershipStatus: i == 1 ? 'Pending Invitation' : 'Active',
      ),
  ];

  final cwStates = <String, cws.CustomerProfileState>{
    'loaded': cws.CustomerProfileState(profile: cwProfile, memberships: cwMemberships),
    'loading': const cws.CustomerProfileState(loading: true),
    'error': const cws.CustomerProfileState(
        error: 'Could not reach the server. Check your connection and try again.'),
  };

  final iwStates = <String, iws.InvestorProfileState>{
    'loaded': iws.InvestorProfileState(profile: iwProfile, memberships: iwMemberships),
    'loading': const iws.InvestorProfileState(loading: true),
    'error': const iws.InvestorProfileState(
        error: 'Could not reach the server. Check your connection and try again.'),
  };

  for (final scale in kManaTextScales) {
    for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
      final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

      cwStates.forEach((label, seed) {
        testWidgets('CW-006 $label survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const cw.MyProfileMembershipsScreen(personId: 'p1'),
            textScale: scale,
            language: lang,
            overrides: [
              cws.customerProfileProvider.overrideWith(() => _SeededCwProfile(seed)),
            ],
          );
          expectNoLayoutFault(tester, 'CW-006 $label at ${scale}x$tag');
        });
      });

      iwStates.forEach((label, seed) {
        testWidgets('IW-005 $label survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const iw.MyProfileMembershipsScreen(personId: 'p1'),
            textScale: scale,
            language: lang,
            overrides: [
              iws.investorProfileProviderIW005.overrideWith(() => _SeededIwProfile(seed)),
            ],
          );
          expectNoLayoutFault(tester, 'IW-005 $label at ${scale}x$tag');
        });
      });
    }
  }
}
