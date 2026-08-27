import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mana_location.dart';

/// P2 GPS — the three server calls, and what their answers mean.
///
/// The rule that governs all of them: **GPS never blocks anything.** Every
/// method here reports what happened and returns; none of them throws in a way
/// that could stop a loan being issued or an address being saved.
class GpsAddressService {
  GpsAddressService(this._db);
  final SupabaseClient _db;

  /// Records that the person agreed to location capture (LR-007).
  ///
  /// Consent is stored once on the person, not asked per screen — an agent
  /// being prompted at every doorstep would tap through it without reading,
  /// which is not consent.
  Future<void> setConsent({required String personId, required bool granted}) {
    return _db
        .from('persons')
        .update({'consent_location_capture': granted}).eq('person_id', personId);
  }

  Future<bool> hasConsent({required String personId}) async {
    final row = await _db
        .from('persons')
        .select('consent_location_capture')
        .eq('person_id', personId)
        .maybeSingle();
    return (row?['consent_location_capture'] as bool?) ?? false;
  }


  /// Stores or refreshes the pin on the customer's CURRENT address.
  ///
  /// The village is never changed by this — see the pin-only decision. The
  /// server returns village_resolved_from_gps: false to make that explicit.
  Future<void> updateAddressPin({
    required String customerId,
    required ManaFix fix,
  }) async {
    if (!fix.hasPosition) return;
    await _db.schema('app').rpc('update_customer_address_from_gps', params: {
      'p_customer_id': customerId,
      'p_new_lat': fix.latitude,
      'p_new_lng': fix.longitude,
      'p_accuracy_m': fix.accuracyM,
    });
  }

  /// Stamps where a collection was taken. Called AFTER the collection
  /// exists, and never allowed to fail it.
  ///
  /// The server resolves a village name from the pin and stores it alongside
  /// the coordinates -- the coordinates are the audit value, the name is the
  /// only part that goes on a screen. It leaves the name EMPTY rather than
  /// naming the nearest village when nothing is within 2km: a wrong village
  /// on a money record is worse than a blank one.
  Future<void> recordCollectionLocation({
    required String collectionId,
    required ManaFix fix,
  }) async {
    if (!fix.hasPosition) return;
    await _db.schema('app').rpc('update_collection_gps', params: {
      'p_collection_id': collectionId,
      'p_lat': fix.latitude,
      'p_lng': fix.longitude,
      'p_accuracy_m': fix.accuracyM,
    });
  }

  /// Stamps where a loan was issued. Called AFTER the loan exists, because
  /// update_loan_gps takes a loan_id — the loan is the thing that must
  /// succeed, and the pin is decoration on top of it.
  Future<void> recordLoanLocation({
    required String loanId,
    required ManaFix fix,
  }) async {
    if (!fix.hasPosition) return;
    await _db.schema('app').rpc('update_loan_gps', params: {
      'p_loan_id': loanId,
      'p_lat': fix.latitude,
      'p_lng': fix.longitude,
      'p_accuracy_m': fix.accuracyM,
    });
  }
}

final gpsAddressServiceProvider =
    Provider<GpsAddressService>((ref) => GpsAddressService(Supabase.instance.client));
