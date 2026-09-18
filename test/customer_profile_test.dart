import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/shared/customer_profile_screen.dart';
import 'package:mana_line/shared/customer_profile_state.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// What this pins: what a profile is allowed to change, and what it is not.
///
/// The screen's editable set is not a design choice — it is the set of things
/// the server already accepts. `app.owner_update_member_identity` takes a
/// mobile, a date of birth, an Aadhaar and a photo; `owner_update_customer_
/// address` takes a door number, a PIN and a village. NOTHING updates
/// full_name, father_husband_name or gender_digit, and gender is worse than
/// merely unwritable: the MLID is minted from the digit, so a form that
/// changed it would leave an ID that no longer describes its owner.
///
/// Both RPCs COALESCE, which is what makes a partial edit safe — and it is
/// only safe if the screen sends NULL for what was not touched. Sending the
/// unchanged value back is harmless today and a silent overwrite the day two
/// people edit the same person. That is the third test here.
class _FakeClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(const []))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

SupabaseClient _stubClient() => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: _FakeClient(),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

/// Records what the screen asked the server to write, which is the whole
/// point: a test that only looked at the form could not tell a field left
/// alone from a field overwritten with its own value.
class _RecordingApi extends CustomerProfileApiService {
  _RecordingApi(this.profile) : super(_stubClient());

  final ManaCustomerProfile profile;
  Map<String, Object?>? identityCall;
  Map<String, Object?>? addressCall;

  @override
  Future<ManaCustomerProfile?> fetch(String customerId) async => profile;

  @override
  Future<void> updateIdentity({
    required int personId,
    String? mobileNumber,
    String? dob,
    String? aadhaarNumber,
    String? profilePhotoUrl,
  }) async {
    identityCall = {
      'mobile': mobileNumber,
      'dob': dob,
      'aadhaar': aadhaarNumber,
      'photo': profilePhotoUrl,
    };
  }

  @override
  Future<void> updateAddress({
    required int personId,
    required String doorNo,
    required String pinCode,
    required String villageId,
  }) async {
    addressCall = {'door': doorNo, 'pin': pinCode, 'village': villageId};
  }
}

ManaCustomerProfile _person({
  String mlidType = 'MLPI',
  String mlid = 'MLPI112345678',
}) =>
    ManaCustomerProfile(
      personId: 7,
      customerId: 'c-1',
      mlid: mlid,
      mlidType: mlidType,
      fullName: 'Lakshmi Devi',
      careOf: 'Ramana Rao',
      genderDigit: '0',
      mobile: '9876543210',
      dob: '1985-04-09',
      aadhaarLast4: '4321',
      photoUrl: null,
      village: 'Palasa',
      villageId: 'loc-1',
      doorNo: '3-14',
      pinCode: '532221',
      addressLine: '3-14, Palasa, 532221',
    );

void main() {
  Future<_RecordingApi> open(
    WidgetTester tester, {
    ManaCustomerProfile? profile,
    String? businessId,
  }) async {
    final api = _RecordingApi(profile ?? _person());
    await pumpManaScreen(
      tester,
      ManaCustomerProfileScreen(customerId: 'c-1', businessId: businessId),
      overrides: [
        customerProfileApiServiceProvider.overrideWithValue(api),
        locationApiServiceProvider.overrideWithValue(
          LocationApiService(_stubClient()),
        ),
      ],
      surfaceSize: const Size(360, 900),
    );
    await tester.pumpAndSettle();
    return api;
  }

  /// Bring something into view before tapping it.
  ///
  /// The edit body is a ListView, so a widget below the fold is not merely
  /// off-screen -- it has not been built, and `widgetWithText` finds nothing
  /// at all. A tap that misses in silence is the mistake
  /// `silent_tap_guard_test` exists for.
  Future<Finder> reveal(WidgetTester t, Finder f) async {
    await t.scrollUntilVisible(f, 120,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    return f;
  }

  testWidgets('a profile opens on what is known, not on a form', (t) async {
    await open(t);

    expect(find.text('Lakshmi Devi'), findsWidgets);
    expect(find.text('Ramana Rao'), findsOneWidget);
    expect(find.text('Palasa'), findsOneWidget);
    // A DATE SOMEBODY CAN READ. The column is YYYY-MM-DD; view mode used to
    // print it raw while edit mode printed DD/MM/YYYY, so the same date
    // changed shape when Edit was pressed.
    expect(find.text('09/04/1985'), findsOneWidget);
    // Only the last four are kept in the clear — the rest is a hash, so a
    // screen printing the whole number would be printing something the
    // database deliberately does not hold.
    expect(find.text('•••• •••• 4321'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    // Looking is not editing: nothing is typeable until Edit is pressed.
    expect(find.byType(TextField), findsNothing);
    expectNoLayoutFault(t, 'customer profile, view mode');
  });

  testWidgets('name, care-of and gender have no field to change them',
      (t) async {
    await open(t);
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    final labels = t
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.decoration?.labelText)
        .toList();
    expect(labels, contains('Mobile Number'));
    expect(labels, isNot(contains('Full Name')));
    expect(labels, isNot(contains('Father / Husband Name')));
    expect(labels, isNot(contains('Gender')));
    // And the reason is on screen rather than left to be discovered — a form
    // that simply omits three fields reads as an oversight.
    expect(find.textContaining('MLID is built from the gender'), findsOneWidget);
    expectNoLayoutFault(t, 'customer profile, edit mode');
  });

  testWidgets('an untouched field is sent as null, not as its own value',
      (t) async {
    final api = await open(t);
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    await t.tap(
        await reveal(t, find.widgetWithText(FilledButton, 'Save changes')));
    await t.pumpAndSettle();

    expect(api.identityCall, isNotNull);
    // THE COALESCE CONTRACT. Nothing was typed, so nothing may be written.
    expect(api.identityCall!['mobile'], isNull);
    expect(api.identityCall!['photo'], isNull);
    // The address still goes, because the village it is written against is
    // the one already stored — it is not a change, it is the same address.
    expect(api.addressCall!['village'], 'loc-1');
    expect(api.addressCall!['door'], '3-14');
  });

  testWidgets('a mobile number that was typed does get written', (t) async {
    final api = await open(t);
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    await t.enterText(
      await reveal(t, find.widgetWithText(TextField, '9876543210')),
      '9000000001',
    );
    await t.tap(
        await reveal(t, find.widgetWithText(FilledButton, 'Save changes')));
    await t.pumpAndSettle();

    expect(api.identityCall!['mobile'], '9000000001');
  });

  testWidgets('a permanent ID will not let its Aadhaar be edited', (t) async {
    await open(t);
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    // An MLPI is `MLPI + gender digit + the last eight of the Aadhaar`,
    // derived once and then printed on receipts and quoted down a phone.
    // Editing the Aadhaar does not re-mint it.
    expect(find.textContaining('Aadhaar is locked'), findsOneWidget);
    final labels = t
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.decoration?.labelText ?? '')
        .join(' ');
    expect(labels.toLowerCase(), isNot(contains('aadhaar')));
  });

  testWidgets('a temporary ID is offered the conversion, a permanent one is not',
      (t) async {
    await open(t, profile: _person(mlidType: 'MLTI', mlid: 'MLTI012345678'),
        businessId: 'b1');
    await reveal(t, find.text('Make Permanent'));
    expect(find.text('Make Permanent'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await open(t, businessId: 'b1');
    expect(find.text('Make Permanent'), findsNothing);
  });

  testWidgets('without a business there is nothing to convert against',
      (t) async {
    // businessId is what the conversion is scoped to. A profile opened from
    // somewhere that has none is still worth reading; it just cannot mint.
    await open(t, profile: _person(mlidType: 'MLTI', mlid: 'MLTI012345678'));
    expect(find.text('Make Permanent'), findsNothing);
  });
}
