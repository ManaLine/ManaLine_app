import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mana_line/shared/location_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What this pins: the app stops answering "which district" by sort order.
///
/// Andhra Pradesh split its districts in 2022 and `lgd_villages` carries both
/// the old and the new name, so 56,163 villages are listed twice -- every
/// village in Srikalahasti mandal among them, under Chittoor AND Tirupati.
///
/// `app.suggest_villages` orders by district A to Z, and the merge loop in
/// searchByPin used to `continue` on a name it had already seen. The row it
/// kept was therefore always the alphabetically first district, and for
/// Srikalahasti that is CHITTOOR -- which the mandal left in 2022. Every
/// village added there was silently stamped with the wrong, older district,
/// and nothing on any screen said so.
///
/// The Owner asked for this as item 11: "enable user to select mandal,
/// district ... which is correct if app fills it wrong or old data".
class _FakeClient extends http.BaseClient {
  _FakeClient(this._responder);
  final Object Function(Uri url) _responder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(_responder(request.url)))),
        200,
        headers: const {'content-type': 'application/json'},
        request: request,
      );
}

/// The reference as production actually holds it: two rows per village,
/// district ascending, exactly as suggest_villages returns them.
LocationApiService _service({List<Map<String, dynamic>>? reference}) {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: _FakeClient((url) {
      if (url.path.endsWith('/locations')) return const [];
      if (url.path.contains('suggest_villages')) {
        return reference ??
            const [
              {
                'village': 'Panagallu (Rural)',
                'mandal': 'Srikalahasti',
                'district': 'Chittoor',
                'state': 'Andhra Pradesh',
              },
              {
                'village': 'Panagallu (Rural)',
                'mandal': 'Srikalahasti',
                'district': 'Tirupati',
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

void main() {
  test('a split village is offered once, not twice', () async {
    final found =
        await _service().searchByPin(pinCode: '517640', query: 'pan');
    expect(found.length, 1,
        reason: 'two directory rows for one village are one village');
    expect(found.single.name, 'Panagallu (Rural)');
  });

  test('both districts survive the search instead of one being discarded',
      () async {
    final found =
        await _service().searchByPin(pinCode: '517640', query: 'pan');
    // THE BUG. The loop used to keep the first row and drop the second, and
    // the second row is the other district.
    expect(found.single.districtOptions, ['Chittoor', 'Tirupati']);
    expect(found.single.districtIsAmbiguous, isTrue);
  });

  test('a village with one district is not made into a question', () async {
    final found = await _service(reference: const [
      {
        'village': 'Someswaram',
        'mandal': 'Rayavaram',
        'district': 'East Godavari',
        'state': 'Andhra Pradesh',
      },
    ]).searchByPin(pinCode: '533261', query: 'som');

    // 93% of villages are this case. Asking here would be asking for nothing,
    // on nearly every village anybody ever adds.
    expect(found.single.districtIsAmbiguous, isFalse);
    expect(found.single.districtOptions, isEmpty);
    expect(found.single.district, 'East Godavari');
  });

  test('choosing a district keeps everything else about the village', () {
    const v = ManaVillage(
      locationId: '',
      name: 'Panagallu (Rural)',
      pinCode: '517640',
      mandal: 'Srikalahasti',
      district: 'Chittoor',
      state: 'Andhra Pradesh',
      districtOptions: ['Chittoor', 'Tirupati'],
    );
    final picked = v.withDistrict('Tirupati');

    expect(picked.district, 'Tirupati');
    expect(picked.name, v.name);
    expect(picked.pinCode, v.pinCode);
    expect(picked.mandal, v.mandal);
    expect(picked.state, v.state);
    // The options stay, so a screen can still say why it asked.
    expect(picked.districtOptions, v.districtOptions);
  });

  test('the old behaviour would have picked the pre-split district', () async {
    // Kept as a statement of what was wrong, so a future change that
    // reintroduces "take the first row" fails here with the reason attached.
    final found =
        await _service().searchByPin(pinCode: '517640', query: 'pan');
    final alphabeticallyFirst = ([...found.single.districtOptions]..sort()).first;
    expect(alphabeticallyFirst, 'Chittoor',
        reason: 'Chittoor sorts first and is the district Srikalahasti mandal '
            'LEFT in 2022 -- which is exactly why sort order must not decide '
            'this. Tirupati is the current one.');
  });
}
