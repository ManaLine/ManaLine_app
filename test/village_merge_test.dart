import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/shared/location_api_service.dart';
import 'package:mana_line/shared/village_merge_screen.dart';
import 'package:mana_line/shared/village_merge_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/mana_harness.dart';

/// What this pins: a merge moves an address and nothing else, and the screen
/// never offers one the server would refuse.
///
/// THE OWNER'S RULE, verbatim: "their loans, collections and account history
/// follow silently - just their address village name changes to the new one,
/// remaining all stays." That is provable rather than hopeful, because exactly
/// three tables reference `locations` -- person_addresses.village_id,
/// operating_area_locations.location_id, route_locations.location_id -- and
/// none of them is money. It was also measured against the live book inside a
/// rolled-back transaction: 91 customers, 0 balances moved, 0 collecting
/// agents moved.
///
/// What CAN move is who collects, because an agent's reach is derived
/// village -> operating area -> assignment. The server refuses a merge whose
/// two villages are worked by different areas, and these tests pin that the
/// screen shows the refusal as a sentence instead of a dead button -- the
/// refusal names an action the Owner can take, and a greyed-out control with
/// nothing beside it reads as a broken screen.
class _FakeClient extends http.BaseClient {
  _FakeClient(this.villages);
  final List<Map<String, dynamic>> villages;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request.url.path.contains('operating_area_locations')
        ? villages
        : const [];
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

SupabaseClient _stubClient([List<Map<String, dynamic>> villages = const []]) =>
    SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: _FakeClient(villages),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

/// The village as businessVillages reads it -- through operating_area_locations
/// with the `locations` row embedded.
List<Map<String, dynamic>> _oneVillage() => [
      {
        'locations': {
          'location_id': 'loc-keep',
          'village_town_name': 'Panagallu (Rural)',
          'pin_code': '517640',
          'mandal': 'Srikalahasti',
          'district': 'Chittoor',
          'state': 'Andhra Pradesh',
        }
      }
    ];

class _FakeMergeApi extends VillageMergeApiService {
  _FakeMergeApi(this.rows) : super(_stubClient());

  final List<ManaVillageDuplicate> rows;

  /// Every merge this fake was asked to perform, as (loser, survivor).
  final List<(String, String)> merges = [];

  /// What blockedReason() answers next. Empty means "allowed"; null makes the
  /// call THROW, which is the network-failure case.
  String? nextReason = '';
  int reasonCalls = 0;

  @override
  Future<List<ManaVillageDuplicate>> candidates(String businessId) async => rows;

  @override
  Future<String> blockedReason({
    required String businessId,
    required String loserId,
    required String survivorId,
  }) async {
    reasonCalls++;
    final r = nextReason;
    if (r == null) throw Exception('network');
    return r;
  }

  /// What the correction sheet will offer, most-used first, as the server
  /// returns it: mandals and districts in one list.
  List<ManaPlaceOption> places = const [
    ManaPlaceOption(
        kind: 'mandal', value: 'Srikalahasti', usedHere: 3, inDirectory: true),
    ManaPlaceOption(
        kind: 'mandal', value: 'Thottambedu', usedHere: 0, inDirectory: true),
    ManaPlaceOption(
        kind: 'district', value: 'Chittoor', usedHere: 3, inDirectory: true),
    ManaPlaceOption(
        kind: 'district', value: 'Tirupati', usedHere: 1, inDirectory: true),
  ];

  /// The mandal each placeOptions() call was made with, so a test can prove
  /// the districts were re-asked for after the mandal changed.
  final List<String?> optionCallsForMandal = [];

  /// Every correction asked for, as (locationId, mandal, district).
  final List<(String, String, String)> corrections = [];

  @override
  Future<List<ManaPlaceOption>> placeOptions({
    required String businessId,
    required String locationId,
    String? mandal,
  }) async {
    optionCallsForMandal.add(mandal);
    return places;
  }

  @override
  Future<Map<String, dynamic>> correctPlace({
    required String businessId,
    required String locationId,
    required String mandal,
    required String district,
  }) async {
    corrections.add((locationId, mandal, district));
    return {
      'village': 'Panagallu (Rural)',
      'was_mandal': mandal,
      'was_district': 'Chittoor',
      'now_mandal': mandal,
      'now_district': district,
    };
  }

  @override
  Future<Map<String, dynamic>> merge({
    required String businessId,
    required String loserId,
    required String survivorId,
  }) async {
    merges.add((loserId, survivorId));
    return {
      'kept': rows.first.keepName,
      'dropped': rows.first.dropName,
      // DELIBERATELY NOT the count the screen was showing. The server moves
      // past addresses too, and the snackbar must quote what actually moved.
      'addresses_moved': 5,
      'area_links_removed': 1,
      'route_links_moved': 0,
      'still_in_use_elsewhere': false,
    };
  }
}

/// The real pair from this book: same PIN, same mandal, two spellings, and the
/// customers split 19 / 2 between them.
ManaVillageDuplicate _panagal({String? blocked}) => ManaVillageDuplicate(
      keepId: 'loc-keep',
      keepName: 'Panagallu (Rural)',
      keepMandal: 'Srikalahasti',
      keepDistrict: 'Chittoor',
      keepPeople: 19,
      dropId: 'loc-drop',
      dropName: 'Panagal',
      dropMandal: 'Srikalahasti',
      dropDistrict: 'Tirupati',
      dropPeople: 2,
      pinCode: '517640',
      blockedReason: blocked,
    );

void main() {
  Future<_FakeMergeApi> open(
    WidgetTester tester, {
    List<ManaVillageDuplicate> rows = const [],
    List<Map<String, dynamic>> villages = const [],
  }) async {
    final api = _FakeMergeApi(rows);
    await pumpManaScreen(
      tester,
      const ManaVillageMergeScreen(businessId: 'b1'),
      overrides: [
        villageMergeApiServiceProvider.overrideWithValue(api),
        // The screen lists this book's villages so a wrong district can be
        // put right, and it asks for them in initState -- seeded rather than
        // left to reach the network, which is the harness rule.
        locationApiServiceProvider.overrideWithValue(
          LocationApiService(_stubClient(villages)),
        ),
      ],
      surfaceSize: const Size(360, 900),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('a book with no duplicates says so rather than showing nothing',
      (t) async {
    await open(t);
    expect(find.textContaining('No village on this book'), findsOneWidget);
    expectNoLayoutFault(t, 'village merge, nothing to merge');
  });

  testWidgets('a pair shows both names, both counts and which one survives',
      (t) async {
    await open(t, rows: [_panagal()]);

    expect(find.text('Panagallu (Rural)'), findsOneWidget);
    expect(find.text('Panagal'), findsOneWidget);
    expect(find.text('19 people'), findsOneWidget);
    expect(find.text('2 people'), findsOneWidget);
    // Labels, not a from/to arrow: the decision is which NAME survives on
    // every receipt from now on.
    expect(find.text('Keep this one'), findsOneWidget);
    expect(find.text('Move these people'), findsOneWidget);
    expectNoLayoutFault(t, 'village merge, one pair');
  });

  testWidgets('the money promise is on screen, not just in a migration',
      (t) async {
    await open(t, rows: [_panagal()]);
    expect(
      find.textContaining('loans, collections and account history are not'),
      findsOneWidget,
    );
  });

  testWidgets('a blocked pair states the reason and offers no Merge button',
      (t) async {
    await open(t, rows: [
      _panagal(
          blocked: 'These two villages are worked by different areas '
              '(Uranduru, Srikalahasti Line). Put both villages in the same '
              'areas first, or the customers here would change rounds.')
    ]);

    expect(find.text('Cannot be merged'), findsOneWidget);
    expect(find.textContaining('Uranduru, Srikalahasti Line'), findsOneWidget);
    // The action is absent rather than disabled. A dead button with no
    // sentence beside it is indistinguishable from a broken screen.
    expect(find.widgetWithText(FilledButton, 'Merge Villages'), findsNothing);
  });

  testWidgets('merging asks first, then sends loser and survivor the right way'
      ' round', (t) async {
    final api = await open(t, rows: [_panagal()]);

    await t.tap(find.widgetWithText(FilledButton, 'Merge Villages'));
    await t.pumpAndSettle();

    // The question names both villages and how many people move, because
    // after this the old name stops being offered to anybody.
    expect(find.text('Merge these two villages?'), findsOneWidget);
    expect(
      find.textContaining('2 people move from Panagal to Panagallu (Rural)'),
      findsOneWidget,
    );
    expect(api.merges, isEmpty, reason: 'nothing until it is confirmed');

    await t.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Merge Villages'),
    ));
    await t.pumpAndSettle();

    expect(api.merges, [('loc-drop', 'loc-keep')]);
  });

  testWidgets('cancelling the question merges nothing', (t) async {
    final api = await open(t, rows: [_panagal()]);

    await t.tap(find.widgetWithText(FilledButton, 'Merge Villages'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();

    expect(api.merges, isEmpty);
  });

  testWidgets('the result quotes what the server moved, not what was on screen',
      (t) async {
    await open(t, rows: [_panagal()]);

    await t.tap(find.widgetWithText(FilledButton, 'Merge Villages'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Merge Villages'),
    ));
    await t.pumpAndSettle();

    // The screen counted 2 current addresses; the server moved 5, because it
    // moves past addresses too. The snackbar says 5.
    expect(find.textContaining('5 people now live in Panagallu (Rural)'),
        findsOneWidget);
  });

  testWidgets('swapping turns the pair around and asks the server again',
      (t) async {
    final api = await open(t, rows: [_panagal()]);
    api.nextReason = '';

    await t.tap(find.widgetWithText(TextButton, 'Swap'));
    await t.pumpAndSettle();

    expect(api.reasonCalls, 1,
        reason: 'the refusal is per direction, so the old answer cannot be '
            'carried over to the new one');

    await t.tap(find.widgetWithText(FilledButton, 'Merge Villages'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Merge Villages'),
    ));
    await t.pumpAndSettle();

    // The sides are exchanged: the 19-person row is now the one being moved.
    expect(api.merges, [('loc-keep', 'loc-drop')]);
  });

  testWidgets('the sheet offers the mandal and the district, not just one',
      (t) async {
    // The Owner asked for both: "enable user to select mandal, district".
    await open(t, rows: const [], villages: _oneVillage());
    await t.tap(find.text('Panagallu (Rural)'));
    await t.pumpAndSettle();

    expect(find.text('Mandal *'), findsOneWidget);
    expect(find.text('District *'), findsOneWidget);
    expect(find.text('Srikalahasti'), findsWidgets);
    expect(find.text('Chittoor'), findsWidgets);
    expectNoLayoutFault(t, 'the correction sheet');
  });

  testWidgets('a district is offered with how much of this book uses it',
      (t) async {
    final api = await open(t, rows: const [], villages: _oneVillage());
    await t.tap(find.text('Panagallu (Rural)'));
    await t.pumpAndSettle();

    await t.tap(find.text('District *'));
    await t.pumpAndSettle();

    // "most used on top" -- the count is what makes the question answerable,
    // because an Owner knows their own ledger and not which district is
    // legally current.
    expect(find.text('Already used by 3 of your villages'), findsOneWidget);
    expect(find.text('Already used by 1 of your villages'), findsOneWidget);

    await t.tap(find.text('Tirupati').last);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();

    expect(api.corrections, [('loc-keep', 'Srikalahasti', 'Tirupati')]);
    expect(find.textContaining('moved from Chittoor to Tirupati'),
        findsOneWidget);
  });

  testWidgets('changing the mandal asks for that mandal district list',
      (t) async {
    final api = await open(t, rows: const [], villages: _oneVillage());
    await t.tap(find.text('Panagallu (Rural)'));
    await t.pumpAndSettle();
    expect(api.optionCallsForMandal, ['Srikalahasti']);

    await t.tap(find.text('Mandal *'));
    await t.pumpAndSettle();
    await t.tap(find.text('Thottambedu').last);
    await t.pumpAndSettle();

    // THE DISTRICTS DEPEND ON THE MANDAL. Keeping the first list would offer
    // districts belonging to the mandal that had just been replaced -- a
    // wrong answer presented confidently, which is the failure mode this
    // whole item exists to end.
    expect(api.optionCallsForMandal, ['Srikalahasti', 'Thottambedu']);
  });

  testWidgets('changing nothing writes nothing', (t) async {
    final api = await open(t, rows: const [], villages: _oneVillage());
    await t.tap(find.text('Panagallu (Rural)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();

    // Not a no-op for politeness -- a write that changes nothing still
    // rewrites a row every book on this database shares.
    expect(api.corrections, isEmpty);
  });

  testWidgets('the list says what tapping a village will do', (t) async {
    await open(t, rows: const [], villages: _oneVillage());
    expect(find.text('Your Villages'), findsOneWidget);
    expect(
      find.textContaining('not who lives there or what they owe'),
      findsOneWidget,
    );
    expectNoLayoutFault(t, 'village list with the correction note');
  });

  testWidgets('a swap whose check never answered is undone, not offered',
      (t) async {
    final api = await open(t, rows: [
      _panagal(
          blocked: 'These two villages are worked by different areas '
              '(Uranduru). Put both villages in the same areas first, or the '
              'customers here would change rounds.')
    ]);
    api.nextReason = null; // the call throws

    await t.tap(find.widgetWithText(TextButton, 'Swap'));
    await t.pumpAndSettle();

    // WHAT WOULD HAVE HAPPENED WITHOUT THE FIX. blockedReason() used to
    // return null for "allowed", and NetworkErrorHandler.run returns null for
    // "the call failed". The screen could not tell them apart and resolved
    // the ambiguity towards drawing the Merge button -- on a pair it had just
    // been told, a moment earlier, that it must not merge.
    expect(find.widgetWithText(FilledButton, 'Merge Villages'), findsNothing);
    expect(find.textContaining('Uranduru'), findsOneWidget,
        reason: 'the pair is put back as it was, reason and all');
    expect(api.merges, isEmpty);

    // The failure raises a snackbar, and a snackbar is a six-second timer the
    // test has to outlive or the whole case fails on a pending timer rather
    // than on anything it was checking.
    await t.pump(const Duration(seconds: 7));
  });

  testWidgets('a swap that the server refuses says so instead of merging',
      (t) async {
    final api = await open(t, rows: [_panagal()]);
    api.nextReason = 'The village being kept is not active.';

    await t.tap(find.widgetWithText(TextButton, 'Swap'));
    await t.pumpAndSettle();

    expect(find.text('The village being kept is not active.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Merge Villages'), findsNothing);
    expect(api.merges, isEmpty);
  });
}
