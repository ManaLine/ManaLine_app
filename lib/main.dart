import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/router.dart';
import 'design/theme.dart';
import 'features/login_registration/state/auth_flow_state.dart';
import 'shared/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // See design/tokens/typography.dart — flip this to false and bundle
  // font assets before shipping, so first paint doesn't depend on
  // network in exactly the low-connectivity conditions this app targets.
  GoogleFonts.config.allowRuntimeFetching = true;

  // ARCHITECTURAL NOTE (see auth_api_service.dart header for the full
  // decision record): this app does NOT use Supabase's own GoTrue
  // auth.users session — persons.mlid/password_hash/pin_hash is the sole
  // identity source of truth (BR-178/181/182), and there is no
  // persons.auth_user_id column in the delivered schema to bridge the two.
  // Instead, login/register/OTP/PIN flows go through Supabase Edge
  // Functions (NOT YET WRITTEN — flagged as a blocking gap in the END
  // RESULT) that mint a custom JWT containing a `person_id` claim, signed
  // with the project's JWT secret server-side. The `accessToken` callback
  // below is supabase_flutter's documented hook for exactly this
  // "third-party/custom auth" pattern — it lets Postgrest/Realtime send
  // that custom JWT as the bearer token on every request, without ever
  // going through supabase.auth.signInWithPassword/signUp. RLS policies in
  // 0012_rls_module0_identity.sql read this same claim via
  // app.current_person_id().
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
    // This callback runs before EVERY Postgrest/Realtime request, which
    // makes it the one place that catches a session dying mid-use.
    //
    // The minted token has a 1-hour TTL and there is no refresh endpoint —
    // auth-login mints, nothing renews. Before this, an expired token kept
    // being sent: every screen failed with PGRST303 "JWT expired" and the
    // Retry button re-sent the same dead token, so the app was stuck until
    // it was force-closed.
    //
    // Now expiry drops the token and bounces to PIN entry, which re-mints.
    // Daily login is PIN-only by design (GLOBAL BR-195), so this is the
    // intended path back in, not a workaround.
    accessToken: () async {
      final session = ManaSession.instance;
      if (session.isAccessTokenExpired) {
        await session.clearExpiredAccessToken();
        _redirectToPinLogin();
      }
      return session.currentAccessToken;
    },
  );

  // Cold-start hydration (LR-001's actual job per this session's Item E) —
  // restores a persisted session token/person_id from flutter_secure_storage
  // before the router's first health-check redirect decision fires.
  await ManaSession.instance.hydrateFromSecureStorage();

  runApp(const ProviderScope(child: ManaLineApp()));
}

/// Sends the person to PIN entry once, from wherever they were.
///
/// Guarded because the accessToken callback fires per request and a screen
/// typically issues several at once — without this, one expiry would push
/// half a dozen duplicate routes onto the stack. The flag clears on the
/// next frame, so a genuinely later expiry still redirects.
bool _redirectingToLogin = false;

void _redirectToPinLogin() {
  if (_redirectingToLogin) return;
  _redirectingToLogin = true;
  // Scheduled rather than immediate: this runs inside a network callback,
  // which may be mid-build or mid-frame, and go_router must not be driven
  // from there.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    manaRouter.go('/lr-009');
    _redirectingToLogin = false;
  });
}

class ManaLineApp extends StatelessWidget {
  const ManaLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MANA LINE',
      debugShowCheckedModeBanner: false,
      theme: ManaTheme.light(),
      routerConfig: manaRouter,
    );
  }
}
