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

  /// Compares where the agent is standing against the customer's stored pin.
  ///
  /// Returns null when there is nothing to compare — no stored pin, or no fix.
  /// A null is "not checked", which the UI must never render as "does not
  /// match".
  Future<AddressCheck?> compare({
    required String customerId,
    required ManaFix fix,
  }) async {
    if (!fix.hasPosition) return null;
    final rows = await _db.schema('app').rpc('compare_address_gps', params: {
      'p_customer_id': customerId,
      'p_agent_lat': fix.latitude,
      'p_agent_lng': fix.longitude,
      'p_agent_accuracy_m': fix.accuracyM,
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return AddressCheck.fromRow(list.first);
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

class AddressCheck {
  final double? distanceM;

  /// Null when it could not be judged at all.
  final bool? isMatch;

  /// True when the fix was too rough (over 100m accuracy) or there was no
  /// stored pin to compare against.
  final bool isIndeterminate;

  const AddressCheck({
    required this.distanceM,
    required this.isMatch,
    required this.isIndeterminate,
  });

  factory AddressCheck.fromRow(Map<String, dynamic> r) => AddressCheck(
        distanceM: (r['distance_m'] as num?)?.toDouble(),
        isMatch: r['is_match'] as bool?,
        isIndeterminate: (r['is_indeterminate'] as bool?) ?? true,
      );

  /// THE IMPORTANT DISTINCTION. "Couldn't verify" and "doesn't match" are
  /// different claims, and showing the second when you mean the first accuses
  /// a customer of being somewhere they are not. Indeterminate always wins.
  String get message {
    if (isIndeterminate) {
      return 'Could not check this against the saved address.';
    }
    if (isMatch == true) {
      return 'Matches the saved address'
          '${distanceM != null ? ' (${distanceM!.round()}m away)' : ''}.';
    }
    return 'This is ${distanceM != null ? '${distanceM!.round()}m' : 'far'} '
        'from the saved address.';
  }

  bool get isMismatch => !isIndeterminate && isMatch == false;
}

final gpsAddressServiceProvider =
    Provider<GpsAddressService>((ref) => GpsAddressService(Supabase.instance.client));
