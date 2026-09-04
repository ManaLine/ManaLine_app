import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../design/components/mana_text.dart';
import 'translation_service.dart';

/// Adds a village the reference data does not have yet, and says so when it
/// fails.
///
/// Four screens carried their own copy of this -- CW-006, IW-005, OW-014 and
/// OW-016 -- and the copies had drifted. CW-006 and IW-005 were byte
/// identical and told the person when the call failed. The two owner-side
/// copies did this instead:
///
///     } catch (_) {
///       if (!mounted) return;
///       setState(() => _savingManual = false);
///     }
///
/// The spinner stops, nothing is said, and the village was never added. The
/// person taps Save, sees the button settle, and carries on believing their
/// address is recorded. A silent failure that looks like success is the one
/// failure mode this codebase treats as unacceptable, and it had two copies.
///
/// Returns the new location_id, or null when it could not be added -- in
/// which case the caller has ALREADY shown the person why, so it only has to
/// stop.
Future<String?> manaAddVillageIfMissing(
  BuildContext context,
  WidgetRef ref, {
  required String pinCode,
  required String villageTownName,
  required String areaType,
  required String mandal,
  required String district,
  required String state,
}) async {
  try {
    final rows = await Supabase.instance.client
        .schema('app')
        .rpc('add_location_if_missing', params: {
      'p_pin_code': pinCode,
      'p_village_town_name': villageTownName,
      'p_area_type': areaType,
      'p_mandal': mandal,
      'p_district': district,
      'p_state': state,
    });
    return ((rows as List).first as Map<String, dynamic>)['location_id']
        as String?;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ManaText.raw(
            ref.t('could_not_add_village_note').replaceAll('{error}', '$e'),
          ),
        ),
      );
    }
    return null;
  }
}

/// Turns a picked village row into a real `location_id`.
///
/// A row that came from the LGD reference has a NULL `location_id` — it is a
/// suggestion, and the `locations` row is written only when somebody commits to
/// it. Reading that field as a String is what the four address editors used to
/// do, and it worked only because they never offered a reference row in the
/// first place: they searched `locations` alone, so every result already had an
/// id, and every village nobody had used yet was unreachable.
///
/// Returns null when the village could not be created, in which case
/// [manaAddVillageIfMissing] has already told the person why.
Future<String?> manaResolvePickedVillage(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> row,
  required String pinCode,
}) async {
  final existing = row['location_id'] as String?;
  if (existing != null && existing.isNotEmpty) return existing;
  return manaAddVillageIfMissing(
    context,
    ref,
    pinCode: pinCode,
    villageTownName: ((row['village_town_name'] as String?) ?? '').trim(),
    // 'Village' and 'Town' are the whole of location_area_type_enum, and every
    // directory pick in this app already hardcodes the former.
    areaType: 'Village',
    mandal: ((row['mandal'] as String?) ?? '').trim(),
    district: ((row['district'] as String?) ?? '').trim(),
    state: ((row['state'] as String?) ?? '').trim(),
  );
}
