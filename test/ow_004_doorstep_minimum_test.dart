import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';
import 'package:mana_line/features/owner_workspace/state/customer_state.dart';
import 'package:mana_line/shared/location_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// Same fake-http-client technique as village_search_field_test.dart: no
/// mocking package in this repo, so a real SupabaseClient is given a fake
/// http client rather than reaching the network.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._responder);
  final List<Map<String, dynamic>> Function(Uri url) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.encode(jsonEncode(_responder(request.url)));
    return http.StreamedResponse(
      Stream.value(body),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// One village, 'Palasa', found by PIN — just enough to drive
/// ManaVillageSearchField's PIN mode to a real pick. PIN mode queries
/// `locations` (searchByPin), not `lgd_villages` (the cascade).
LocationApiService _oneVillageService() {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: _FakeClient((url) {
      if (url.path.endsWith('/locations')) {
        return const [
          {
            'location_id': 'loc-1',
            'village_town_name': 'Palasa',
            'pin_code': '532221',
            'mandal': 'Palasa',
            'district': 'Srikakulam',
            'state': 'Andhra Pradesh',
          },
        ];
      }
      return const [];
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  return LocationApiService(client);
}

/// What this pins: how much a person has to type before a customer can be
/// created at a doorstep.
///
/// The form used to demand seven fields -- name, father/husband, gender,
/// mobile, PIN, door number and village. register_new_customer requires
/// three. persons is NOT NULL on full_name, father_husband_name and
/// gender_digit and nothing else; mobile and door_no are NULLIF'd inside the
/// RPC, and the whole person_addresses INSERT sits behind
/// `IF p_village_id IS NOT NULL`.
///
/// So the form was refusing registrations the database would have taken. At a
/// doorstep that means the customer is not created, the loan is not issued,
/// and the round moves on without them.
///
/// If someone tightens this again, this test says what it costs.
class _SeededCustomerList extends CustomerListNotifier {
  @override
  CustomerListState build() => const CustomerListState(customers: []);

  @override
  Future<void> load(String businessId) async {}

  /// No match, which is what puts the sheet on the Create New stage -- the
  /// doorstep case: somebody who is not in the book yet.
  @override
  Future<List<CustomerSummary>> searchIdentity({
    String? mlid,
    String? aadhaar,
    String? phone,
    String? fullName,
  }) async =>
      const [];
}

void main() {
  // The Add Customer draft is static on purpose -- it is what survives a back
  // press -- so it also survives from one test to the next, and test two would
  // open on the half-filled form test one left behind.
  setUp(() => ManaAddCustomerDraft.clear('b1'));

  // Everything is scoped to the sheet. The screen BEHIND it has its own
  // search box, so an unscoped find.byType(TextField) types into the wrong
  // one and the sheet never leaves its first stage.
  Finder inSheet(Finder f) =>
      find.descendant(of: find.byType(BottomSheet), matching: f);

  /// The sheet ends with two choices now -- Add Only, and Add & Issue Loan --
  /// because adding somebody and lending to them are two decisions. Both are
  /// gated by the same field rules, so either one answers "is the form
  /// satisfied"; Add Only is the closer analogue of the single button this
  /// used to be.
  Finder createButton() =>
      inSheet(find.widgetWithText(OutlinedButton, 'Add Only'));

  Future<void> openSheet(WidgetTester tester, {List<Override> extraOverrides = const []}) async {
    await pumpManaScreen(
      tester,
      const CustomerManagementScreen(businessId: 'b1', initialAction: 'register'),
      overrides: [
        customerListProvider.overrideWith(_SeededCustomerList.new),
        // EVERY test needs this now, not just the one that picks a village:
        // the sheet asks which villages this business works the moment it
        // opens, and without the override that reaches a Supabase client no
        // test has initialised.
        locationApiServiceProvider.overrideWithValue(_oneVillageService()),
        ...extraOverrides,
      ],
      surfaceSize: const Size(360, 900),
    );
    await tester.pumpAndSettle();
  }


  /// The sheet scrolls, so the create button is not built until it is reached.
  Future<Finder> revealCreate(WidgetTester tester) async {
    final btn = createButton();
    if (btn.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        btn,
        200,
        scrollable: inSheet(find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
    }
    return btn;
  }

  /// The sheet opens on search, and Create New is reached only by searching
  /// for somebody who is not there. That is the doorstep case exactly.
  Future<void> gotoCreateNew(WidgetTester tester) async {
    await tester.enterText(
        inSheet(find.byType(TextField)).first, 'Somebody Not In The Book');
    await tester.pumpAndSettle();
    // The box does not submit on its own -- there is a Search button beside it.
    await tester.tap(inSheet(find.widgetWithText(ElevatedButton, 'Search')).first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(inSheet(find.byType(TextField)), findsWidgets,
        reason: 'the tap must have landed and opened the create-new stage');
  }

  /// Was 'three fields are enough to create a customer' -- true of the
  /// server (register_new_customer accepts a null village), but never true
  /// of this screen: createNewReturningId's villageId parameter is
  /// non-nullable (customer_state.dart:948) and _createNew force-unwraps
  /// _villageId regardless. Before this fix, _canCreateNew did not check
  /// _villageId, so this test's own assertion (button enabled with no
  /// village) was pinning a state that crashed the instant it was tapped --
  /// the doorstep-minimum test was itself the doorstep-crash test in
  /// disguise. A village pick is now required, and that also supplies the
  /// PIN, so all four are checked together here.
  testWidgets('name + father/husband + gender + a picked village creates a customer',
      (tester) async {
    await openSheet(tester);
    await gotoCreateNew(tester);

    final fields = inSheet(find.byType(TextField));
    expect(fields, findsWidgets, reason: 'the create-new form did not open');

    await tester.enterText(fields.at(0), 'Nagabhushanam Venkata Subba Reddy');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Garikipati Venkata Subba Rami Reddy');
    await tester.pumpAndSettle();

    final gender = inSheet(find.byType(DropdownButtonFormField<String>));
    expect(gender, findsWidgets, reason: 'no gender control');
    await tester.tap(gender.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<String>>(gender.first).initialValue, '1',
        reason: 'the gender pick must have landed');

    // No mobile, no Aadhaar -- still optional. Only the village is picked,
    // via ManaVillageSearchField's PIN mode (defaults open, no mode switch
    // needed): PIN then village name, then tap the one result. Field order
    // on this stage is name(0), father/husband(1), mobile(2), aadhaar(3),
    // door no.(4), then the village field's own PIN(5) and name(6) boxes.
    final villagePin = inSheet(find.byType(TextField)).at(5);
    final villageName = inSheet(find.byType(TextField)).at(6);
    await tester.enterText(villagePin, '532221');
    await tester.enterText(villageName, 'pal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Palasa').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    final btn = await revealCreate(tester);
    expect(btn, findsOneWidget, reason: 'create button missing');
    expect(
      tester.widget<OutlinedButton>(btn).onPressed,
      isNotNull,
      reason: 'name + father/husband + gender + a picked village must be '
          'enough to create -- nothing else is required by the server',
    );
  });

  testWidgets('no village picked keeps Add Only disabled, however complete the rest of the form',
      (tester) async {
    await openSheet(tester);
    await gotoCreateNew(tester);

    final fields = inSheet(find.byType(TextField));
    await tester.enterText(fields.at(0), 'Nagabhushanam Venkata Subba Reddy');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Garikipati Venkata Subba Rami Reddy');
    await tester.pumpAndSettle();

    final gender = inSheet(find.byType(DropdownButtonFormField<String>));
    await tester.tap(gender.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButtonFormField<String>>(gender.first).initialValue, '1',
        reason: 'the gender pick must have landed');

    await tester.enterText(fields.at(2), '9493509919');
    await tester.pumpAndSettle();

    // No village picked. Before the FIRST fix here, _canCreateNew did not
    // check _villageId at all, so tapping force-unwrapped a null and crashed.
    //
    // THIS TEST CHANGED SHAPE ON 2026-09-17 and did not loosen. It asserted
    // the button was DISABLED, which was how the rule was enforced then --
    // and a disabled button at a doorstep turned out to be its own bug:
    // reported from a handset as "both on tap not working, not showing any
    // error why it's not happening". The button is pressable now and REFUSES
    // out loud. The rule it guards -- an incomplete form never reaches
    // _createNew -- is unchanged, and pressing is a sharper way to prove it
    // than reading a null onPressed, because it exercises the refusal.
    final btn = await revealCreate(tester);
    expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull,
        reason: 'the way out of this form must never be a dead control');

    await tester.tap(btn, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    // THE KEY, NOT THE ENGLISH. The harness carries a vendored translation
    // fixture (for width, deliberately) which does not hold keys added after
    // it was captured, so ref.t returns the key itself here. That the key
    // RESOLVES in production is translation_keys_exist_test's job, and it
    // checks every migration for it.
    expect(find.text('village_required'), findsOneWidget,
        reason: 'a village must be picked before Add Only can act -- '
            '_createNew force-unwraps _villageId unconditionally -- and the '
            'Owner has to be told which field it is');
    // Let the snackbar's own dismiss timer run out. A SnackBar schedules one,
    // and a Timer still pending when the tree is disposed fails the test on
    // its way out -- with an error about timers rather than about the thing
    // being tested.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('a half-typed mobile is still refused', (tester) async {
    await openSheet(tester);
    await gotoCreateNew(tester);

    final fields = inSheet(find.byType(TextField));
    await tester.enterText(fields.at(0), 'Chalasani Ramana');
    await tester.pumpAndSettle();
    await tester.enterText(fields.at(1), 'Chalasani Rao');
    await tester.pumpAndSettle();

    final gender = inSheet(find.byType(DropdownButtonFormField<String>));
    await tester.tap(gender.first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Male').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    // CHECKED, because both taps above are allowed to miss in silence and a
    // gender that never landed would make this test refuse for the wrong
    // reason -- silent_tap_guard_test exists for exactly that.
    expect(
        tester.widget<DropdownButtonFormField<String>>(gender.first).initialValue,
        '1',
        reason: 'the gender pick must have landed');

    // A VILLAGE IS PICKED FIRST, which this test did not used to need.
    //
    // The refusal names the FIRST missing thing, reading the form top to
    // bottom, and the village sits above the mobile number. Without one this
    // test would assert the mobile rule and be shown the village rule --
    // passing or failing for the wrong reason either way.
    await tester.enterText(inSheet(find.byType(TextField)).at(5), '532221');
    await tester.enterText(inSheet(find.byType(TextField)).at(6), 'pal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Palasa').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    // CHECKED, and it doubles as the autofill assertion: since 2026-09-17 the
    // village box shows what was PICKED rather than what was typed on the way
    // to it, so "Palasa" in a box that was typed "pal" proves both that the
    // tap landed and that the box followed it.
    expect(
        tester.widget<TextField>(inSheet(find.byType(TextField)).at(6)).controller?.text,
        'Palasa',
        reason: 'the village pick must have landed, and the box must show it');

    // Optional does not mean unvalidated: four digits is a typo, not a
    // decision to leave it blank.
    await tester.enterText(fields.at(2), '9493');
    await tester.pumpAndSettle();

    // Same change of shape as the village test above, same reason.
    final btn = await revealCreate(tester);
    expect(tester.widget<OutlinedButton>(btn).onPressed, isNotNull);

    await tester.tap(btn, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(find.text('mobile_must_be_ten_digits'), findsOneWidget,
        reason: 'a partial mobile number must still block the save, and say '
            'that it is the mobile number doing the blocking');
    // Let the snackbar's own dismiss timer run out. A SnackBar schedules one,
    // and a Timer still pending when the tree is disposed fails the test on
    // its way out -- with an error about timers rather than about the thing
    // being tested.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });
}
