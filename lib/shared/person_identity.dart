import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/login_registration/state/auth_flow_state.dart';

/// The signed-in person's display name, for the app shell header.
///
/// WHY A SHARED PROVIDER: the shell shows "user name, business name beneath"
/// on all four workspaces, and the name arrives from none of them. Login mints
/// a JWT carrying `person_id` but returns no name — `full_name` is only ever
/// SENT, at registration. The alternatives were to extend four API services,
/// four data classes and four notifiers with the same field, or to read it once
/// here. This is the second one.
///
/// Falls back to the MLID rather than to an empty header. An MLID is a poor
/// greeting but it is still an identity the person recognises, and a blank
/// where your own name should be reads as the app having lost your session.
/// The name of [businessId] as this person's memberships already record it.
///
/// Read from the session rather than fetched: LR-012 loaded every membership
/// with its business name to render the selector, so the name is already in
/// memory. The Customer and Investor dashboards do not otherwise carry it, and
/// a round trip for a string the client already has would be latency on the
/// first screen after login.
///
/// Null when the business is not among the memberships — the shell renders the
/// identity line alone rather than an empty second line.
String? businessNameFor(WidgetRef ref, String businessId) {
  for (final m in ref.watch(authFlowProvider).memberships) {
    if (m.businessId == businessId) return m.businessName;
  }
  return null;
}

final personDisplayNameProvider = FutureProvider<String>((ref) async {
  final auth = ref.watch(authFlowProvider);
  final personId = auth.personId;
  final fallback = auth.mlid ?? '';
  if (personId == null) return fallback;

  try {
    final row = await Supabase.instance.client
        .from('persons')
        .select('full_name')
        .eq('person_id', personId)
        .maybeSingle();
    final name = (row?['full_name'] as String?)?.trim();
    return (name == null || name.isEmpty) ? fallback : name;
    // Deliberately swallowed, and this is NOT a money path: a display name that
    // fails to load must not take a dashboard down with it. The fallback is a
    // real identity, not a plausible-looking substitute for a number.
  } catch (_) {
    return fallback;
  }
});
