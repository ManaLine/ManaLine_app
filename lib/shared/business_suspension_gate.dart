import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';
import 'translation_service.dart';

/// SP-001: a non-Owner may not enter a suspended business.
///
/// WHAT THIS FILE USED TO BE. The check, the redirect helper and the screen
/// were all written, the route was registered, and **nothing ever called any
/// of it** — `isBusinessSuspended` and `checkAndRedirect` had zero callers in
/// `lib/` or `test/`. The header said it had wired the LR-012 hookup; it had
/// not. LR-012 drew a red "Suspended" pill on the card and left the card
/// tappable, so a suspended business announced itself and then let you in.
///
/// RLS did not catch it either: no policy on any table references
/// `business_status`, and `businesses_member_select` admits anyone holding an
/// Active membership. Active membership in a suspended business is still
/// active membership. Each layer was assuming the other one had it.
///
/// Found 2026-09-15 by `supabase/tests/multi_tenancy_isolation_tests.sql`, on
/// the first occasion it had ever been executed.
///
/// ## Fail closed
///
/// The standing decision is that ambiguity blocks: if the app cannot confirm a
/// business is Active, nobody gets in. An agent standing at a door is stopped
/// rather than let through on a maybe.
///
/// **That decision costs nothing in latency, because the answer is already in
/// hand.** `business_members.businesses(business_status)` comes back with the
/// memberships at login, so the verdict is a pure function of data the app has
/// already loaded — see [manaSuspensionVerdictFor], which is synchronous and
/// does no IO.
///
/// This matters more than it looks. The obvious implementation — call
/// [isBusinessSuspended] at each workspace entry and block on failure — would
/// have ejected an agent to an error screen on any thirty-second signal drop,
/// which is precisely the condition `lib/shared/outbox/` exists to ride out.
/// Failing closed on a live network call and queueing collections through a
/// blip are contradictory designs. Reading a field that is already loaded is
/// not.
///
/// [isBusinessSuspended] remains for a caller that wants a fresh answer, and
/// is likewise fail-closed — but nothing on the entry path needs it.
enum ManaSuspensionVerdict {
  /// Active, or the person is an Owner of it.
  allowed,

  /// `business_status` is a value other than 'Active'.
  suspended,

  /// The status could not be established. Treated as blocking, and shown as
  /// what it is rather than as a suspension — telling somebody their business
  /// is suspended when the app simply could not ask is the same category of
  /// mistake as a confidently wrong number.
  unconfirmed,
}

/// An Owner is never blocked out of their own book.
///
/// SP-001 is a confidentiality rule aimed at non-Owners, and an Owner has to
/// be able to reach the business to resolve the suspension that is the reason
/// they are being stopped. Locking the one person who can fix it out of the
/// thing that needs fixing is a closed loop.
const String kManaOwnerRole = 'Owner';

/// The whole decision, as a pure function of data already loaded.
///
/// [roles] is every role this person holds in THIS business — somebody can be
/// both Owner and Agent of the same book, and Owner wins.
ManaSuspensionVerdict manaSuspensionVerdictFor({
  required String businessStatus,
  required List<String> roles,
}) {
  if (roles.contains(kManaOwnerRole)) return ManaSuspensionVerdict.allowed;
  final status = businessStatus.trim();
  if (status.isEmpty) return ManaSuspensionVerdict.unconfirmed;
  if (status == 'Active') return ManaSuspensionVerdict.allowed;
  return ManaSuspensionVerdict.suspended;
}

/// Route for a blocking verdict, or null when the caller may proceed.
String? manaSuspensionRouteFor(ManaSuspensionVerdict verdict) =>
    switch (verdict) {
      ManaSuspensionVerdict.allowed => null,
      ManaSuspensionVerdict.suspended => '/business-suspended',
      ManaSuspensionVerdict.unconfirmed => '/business-suspended?reason=unconfirmed',
    };

/// A live read, for a caller that wants a fresh answer rather than the one
/// loaded at login. Fail-closed: anything other than a clean 'Active' — an
/// error, a missing row, a null column — blocks.
///
/// Nothing on the entry path calls this. See the note above on why a live
/// call there would fight the outbox.
Future<ManaSuspensionVerdict> manaFetchSuspensionVerdict(String businessId) async {
  try {
    final row = await Supabase.instance.client
        .from('businesses')
        .select('business_status')
        .eq('business_id', businessId)
        .maybeSingle();
    if (row == null) return ManaSuspensionVerdict.unconfirmed;
    final status = (row['business_status'] as String?) ?? '';
    return manaSuspensionVerdictFor(businessStatus: status, roles: const []);
  } catch (_) {
    // Deliberately not rethrown and deliberately not 'allowed'. The caller
    // asked whether it is safe to proceed; "I could not find out" is an answer
    // to that question, and it is no.
    return ManaSuspensionVerdict.unconfirmed;
  }
}

/// True when the business is suspended for a non-Owner.
@Deprecated('Use manaSuspensionVerdictFor with the membership already loaded, '
    'or manaFetchSuspensionVerdict when a fresh read is genuinely wanted. This '
    'returns a bool and so cannot distinguish "suspended" from "could not ask".')
Future<bool> isBusinessSuspended(String businessId) async =>
    await manaFetchSuspensionVerdict(businessId) != ManaSuspensionVerdict.allowed;

class BusinessSuspensionGate {
  BusinessSuspensionGate._();

  /// Returns true when the caller must STOP — the verdict was blocking and
  /// this has already navigated away.
  ///
  /// Synchronous in everything that matters: pass the status and roles already
  /// held on the membership.
  static bool blockIfSuspended(
    BuildContext context, {
    required String businessStatus,
    required List<String> roles,
  }) {
    final route = manaSuspensionRouteFor(
      manaSuspensionVerdictFor(businessStatus: businessStatus, roles: roles),
    );
    if (route == null) return false;
    context.go(route);
    return true;
  }

  /// The live-read variant. Same contract, one round trip.
  static Future<bool> checkAndRedirect(BuildContext context, String businessId) async {
    final verdict = await manaFetchSuspensionVerdict(businessId);
    if (!context.mounted) return true; // navigated away; do not proceed either way
    final route = manaSuspensionRouteFor(verdict);
    if (route == null) return false;
    context.go(route);
    return true;
  }
}

/// Shared block screen. Deliberately generic about a suspension — never varies
/// by role, never says why or by whom (SP-001 confidentiality). It is NOT
/// generic about the difference between "suspended" and "could not ask": those
/// need different things from the person reading them.
class BusinessSuspendedScreen extends ConsumerWidget {
  const BusinessSuspendedScreen({super.key, this.unconfirmed = false});

  /// True when the app could not establish the status, rather than having
  /// established that it is suspended.
  final bool unconfirmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);
    return Scaffold(
      backgroundColor: ManaColors.ink,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  unconfirmed ? Icons.cloud_off_outlined : Icons.pause_circle_outline,
                  size: 56,
                  color: ManaColors.brand,
                ),
                const SizedBox(height: ManaSpacing.lg),
                ManaText.raw(
                  ref.t(unconfirmed
                      ? 'business_unconfirmed_message'
                      : 'business_suspended_message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: ManaColors.textOnDark, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: ManaSpacing.xl),
                OutlinedButton(
                  onPressed: () => context.go('/lr-012'),
                  child: ManaText(ref.t('back_to_business_selector')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
