import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';

/// Application-layer business-suspension gate (SP-001 confidentiality
/// requirement). Per the standing decision recorded in this session's
/// briefing: enforced at the app layer, NOT as an additional RLS clause —
/// see rls_role_matrix.md's "SP-001 suspension enforcement" section for the
/// full tradeoff writeup that led to this call.
///
/// This file wires the CHECK itself and the LR-012 -> workspace-entry
/// hookup (business selection happens on LR-012, the natural first
/// checkpoint). It deliberately does NOT modify OW-001/AG-001/IW-001/
/// CW-001 — those are each workspace's own entry point, out of this
/// chat's file-ownership boundary. See END RESULT for the exact one-line
/// call each of those four dashboard screens still needs to add.

/// True if the business is suspended for a non-Owner. Owners must still be
/// able to query their own business to resolve an SP-001 dispute — this
/// gate is only ever meant to be called for Agent/Investor/Customer entry
/// points, never for the Owner's own dashboard (OW-001 does not need this
/// gate at all).
Future<bool> isBusinessSuspended(String businessId) async {
  final row = await Supabase.instance.client
      .from('businesses')
      .select('business_status')
      .eq('business_id', businessId)
      .single();
  return row['business_status'] == 'Suspended';
}

/// Convenience wrapper: checks the gate and, if suspended, replaces the
/// current route with the shared suspension screen instead of letting the
/// caller proceed to its own data load. Returns true if the caller should
/// STOP (suspended, already navigated away) — false means proceed
/// normally.
///
/// Usage (the one-line hookup each of OW-001/AG-001/IW-001/CW-001 needs —
/// see END RESULT for exact placement):
///   if (await BusinessSuspensionGate.checkAndRedirect(context, businessId)) {
///     return; // suspended — already routed to the shared message screen
///   }
///   // ...proceed with this dashboard's own data load...
class BusinessSuspensionGate {
  BusinessSuspensionGate._();

  static Future<bool> checkAndRedirect(BuildContext context, String businessId) async {
    final suspended = await isBusinessSuspended(businessId);
    if (!context.mounted) return true; // navigated away already, don't proceed either way
    if (suspended) {
      context.go('/business-suspended');
      return true;
    }
    return false;
  }
}

/// Shared "This business is temporarily suspended" screen. Deliberately
/// generic — never varies by role, never explains why or by whom the
/// suspension was triggered (SP-001 confidentiality requirement). Route
/// registration (`/business-suspended`) needs to be added to router.dart —
/// flagged in END RESULT since this chat may not touch that file; the
/// GoRoute line to add is documented there.
class BusinessSuspendedScreen extends StatelessWidget {
  const BusinessSuspendedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ManaColors.ink,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pause_circle_outline, size: 56, color: ManaColors.brand),
                const SizedBox(height: ManaSpacing.lg),
                ManaText.raw(
                  'This business is temporarily suspended. Will be available soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ManaColors.textOnDark, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: ManaSpacing.xl),
                OutlinedButton(
                  onPressed: () => context.go('/lr-012'),
                  child: const ManaText('back to business selector'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
