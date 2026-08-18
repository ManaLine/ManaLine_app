import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global people search, shared by every screen that needs to find a person
/// who may not belong to this business yet.
///
/// It wraps `app.global_person_search`, which ANDs whatever it is given.
/// The RPC it replaces, `app.owner_search_person`, is an ELSIF chain: pass an
/// MLID and a name and the name is ignored. That is only useful once you
/// already know the single field that identifies someone — which is precisely
/// when you did not need to search.
///
/// The server returns identity and current address only: no balances and no
/// business list, so a global directory cannot become a way to read another
/// business's book.
class PersonSearchService {
  PersonSearchService(this._db);

  final SupabaseClient _db;

  /// [query] is the free-text box — the server works out whether it looks like
  /// an MLID, a phone, a PIN, an Aadhaar or a name. The named parameters are
  /// the structured filters, and they win over anything guessed from [query].
  Future<List<PersonSearchResult>> search({
    String? query,
    String? mlid,
    String? mobileNumber,
    String? aadhaarNumber,
    String? fullName,
    String? pinCode,
    String? village,
    int limit = 25,
  }) async {
    final rows = await _db.schema('app').rpc('global_person_search', params: {
      if (query != null && query.trim().isNotEmpty) 'p_query': query.trim(),
      if (mlid != null && mlid.trim().isNotEmpty) 'p_mlid': mlid.trim(),
      if (mobileNumber != null && mobileNumber.trim().isNotEmpty) 'p_mobile_number': mobileNumber.trim(),
      if (aadhaarNumber != null && aadhaarNumber.trim().isNotEmpty) 'p_aadhaar_number': aadhaarNumber.trim(),
      if (fullName != null && fullName.trim().isNotEmpty) 'p_full_name': fullName.trim(),
      if (pinCode != null && pinCode.trim().isNotEmpty) 'p_pin_code': pinCode.trim(),
      if (village != null && village.trim().isNotEmpty) 'p_village': village.trim(),
      'p_limit': limit,
    });

    return [
      for (final r in (rows as List? ?? const []).cast<Map<String, dynamic>>())
        PersonSearchResult(
          personId: (r['person_id'] as num).toInt().toString(),
          fullName: (r['full_name'] ?? '').toString(),
          fatherHusbandName: (r['father_husband_name'] ?? '').toString(),
          mobileNumber: (r['mobile_number'] ?? '').toString(),
          mlid: (r['mlid'] ?? '').toString(),
          village: (r['village'] as String?)?.trim(),
          pinCode: (r['pin_code'] as String?)?.trim(),
          district: (r['district'] as String?)?.trim(),
        ),
    ];
  }
}

class PersonSearchResult {
  final String personId;
  final String fullName;
  final String fatherHusbandName;
  final String mobileNumber;
  final String mlid;

  /// Current address, when the person has one. Null means "no address on
  /// file", not "no village" — the screens show nothing rather than an empty
  /// dash, so a missing address never reads as a real one.
  final String? village;
  final String? pinCode;
  final String? district;

  const PersonSearchResult({
    required this.personId,
    required this.fullName,
    required this.fatherHusbandName,
    required this.mobileNumber,
    required this.mlid,
    this.village,
    this.pinCode,
    this.district,
  });

  /// "Renigunta · 517644" — whatever part of the address exists.
  String get placeLabel {
    final parts = [
      if (village != null && village!.isNotEmpty) village!,
      if (pinCode != null && pinCode!.isNotEmpty) pinCode!,
    ];
    return parts.join(' · ');
  }
}

final personSearchServiceProvider =
    Provider<PersonSearchService>((ref) => PersonSearchService(Supabase.instance.client));
