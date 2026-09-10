import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/shared/location_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [LocationApiService.searchVillages] and [LocationApiService.states] talk
/// to Postgres over plain HTTP (PostgREST). There is no mocking package in
/// this repo and no established fake-SupabaseClient pattern to follow, so
/// this test injects a fake `http.Client` into `SupabaseClient` itself —
/// `SupabaseClient(url, key, httpClient: ...)` is a real, public constructor
/// parameter, not a workaround.
///
/// WHY THIS MATTERS MORE THAN A NORMAL TEST: the whole point of the
/// prefix-then-substring design is that the substring query must NOT run
/// when the prefix query already found something — a prefix hit in the
/// largest AP district returns 14 rows, the same query as a substring
/// returns 500. A test that only checks the RETURNED VALUE could pass even
/// if both queries always ran and the results were merged; only counting the
/// actual HTTP requests proves the fallback is conditional.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._responder);

  /// Every request this client saw, in order — what the tests assert on.
  final List<Uri> requests = [];

  final List<Map<String, dynamic>> Function(Uri url) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final body = utf8.encode(jsonEncode(_responder(request.url)));
    return http.StreamedResponse(
      Stream.value(body),
      200,
      headers: const {'content-type': 'application/json'},
      // postgrest_builder reads response.request!.method — a null request
      // (the http.StreamedResponse default) throws a null-check error deep
      // inside the package with no hint that it is this field.
      request: request,
    );
  }
}

/// Builds a [LocationApiService] whose every HTTP call is answered by
/// [responder] instead of hitting a real database.
({LocationApiService service, List<Uri> requests}) _serviceWith(
  List<Map<String, dynamic>> Function(Uri url) responder,
) {
  final fake = _FakeClient(responder);
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: fake,
  );
  return (
    service: LocationApiService(client),
    requests: fake.requests,
  );
}

void main() {
  group('searchVillages: fewer than minVillageLetters', () {
    test('returns empty and issues no request', () async {
      final built = _serviceWith((_) => const []);
      final result = await built.service.searchVillages(
        state: 'Andhra Pradesh',
        district: 'Visakhapatnam',
        query: 'pa', // 2 letters — below LocationApiService.minVillageLetters
      );
      expect(result, isEmpty);
      expect(built.requests, isEmpty,
          reason: 'A query too short to search must not touch the network, '
              'same rule as searchByPin.');
    });
  });

  group('searchVillages: prefix first, substring second', () {
    test('a prefix hit does not run the substring query', () async {
      final built = _serviceWith((url) {
        // Only the prefix shape ever returns rows in this test — if the
        // service issues a second (substring) request, that request would
        // hit this same responder, and the test below proves it never does
        // by counting requests, not by trusting this responder alone.
        return [
          {
            'village': 'Palasa',
            'mandal': 'Palasa',
            'district': 'Visakhapatnam',
            'state': 'Andhra Pradesh',
            'pincode': '532221',
          },
        ];
      });

      final result = await built.service.searchVillages(
        state: 'Andhra Pradesh',
        district: 'Visakhapatnam',
        query: 'pal',
      );

      expect(result, hasLength(1));
      expect(result.single.name, 'Palasa');
      expect(built.requests, hasLength(1),
          reason: 'A prefix hit must stop there. Two requests here means '
              'the substring query (500 rows in the worst AP district) ran '
              'for nothing.');
      expect(built.requests.single.queryParameters['village'], 'ilike.pal%',
          reason: 'The one request made must be the prefix shape, not the '
              'substring shape.');
    });

    test('a prefix miss falls back to substring', () async {
      final built = _serviceWith((url) {
        final villageParam = url.queryParameters['village'];
        if (villageParam == 'ilike.ich%') return const []; // prefix: nothing
        return [
          {
            'village': 'Ichchapuram',
            'mandal': 'Ichchapuram',
            'district': 'Srikakulam',
            'state': 'Andhra Pradesh',
            'pincode': '532322',
          },
        ];
      });

      final result = await built.service.searchVillages(
        state: 'Andhra Pradesh',
        district: 'Srikakulam',
        query: 'ich',
      );

      expect(result, hasLength(1));
      expect(result.single.name, 'Ichchapuram');
      expect(built.requests, hasLength(2),
          reason: 'A prefix miss must fall back to exactly one substring '
              'query.');
      expect(built.requests[0].queryParameters['village'], 'ilike.ich%');
      expect(built.requests[1].queryParameters['village'], 'ilike.%ich%',
          reason: 'The fallback must be the substring shape, not a repeat '
              'of the prefix.');
    });

    test('the query asks Postgres to order by village name', () async {
      final built = _serviceWith((_) => [
            {
              'village': 'Palasa',
              'mandal': 'Palasa',
              'district': 'Visakhapatnam',
              'state': 'Andhra Pradesh',
              'pincode': '532221',
            },
          ]);
      await built.service.searchVillages(
        state: 'Andhra Pradesh',
        district: 'Visakhapatnam',
        query: 'pal',
      );
      // postgrest-dart's order() defaults to DESCENDING (ascending: false),
      // unlike plain SQL — the service must pass ascending: true explicitly,
      // or "ordered by village name" silently becomes Z to A.
      expect(built.requests.single.queryParameters['order'],
          'village.asc.nullslast',
          reason: 'State and district are already fixed by the cascade, so '
              'the only ordering that means anything is the village name.');
    });
  });

  group('states: cached for the life of the service', () {
    test('a second call issues no second request', () async {
      var callCount = 0;
      final built = _serviceWith((_) {
        callCount++;
        return [
          {'state': 'Andhra Pradesh'},
          {'state': 'Telangana'},
        ];
      });

      final first = await built.service.states();
      final second = await built.service.states();

      expect(first, ['Andhra Pradesh', 'Telangana']);
      expect(second, first,
          reason: 'A cached read must return the same answer.');
      expect(callCount, 1,
          reason: '35 Indian states do not change mid-session — paying the '
              '244 ms "select distinct state with no filter" cost twice in '
              'one app run is the waste the cache exists to remove.');
      expect(built.requests, hasLength(1));
    });
  });
}
