import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/router.dart';
import 'design/theme.dart';
import 'design/tokens/colors.dart';
import 'design/tokens/spacing.dart';
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
    // A build with no --dart-define points at REPLACE-ME.supabase.co, which
    // HANGS rather than failing — the app looked alive but every screen
    // showed raw translation keys and login claimed "no internet" on a
    // perfectly good network. Say so immediately instead.
    if (SupabaseConfig.isPlaceholder) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ManaTheme.light(),
        home: const _MisconfiguredBuildScreen(),
      );
    }

    return MaterialApp.router(
      title: 'MANA LINE',
      debugShowCheckedModeBanner: false,
      theme: ManaTheme.light(),
      routerConfig: manaRouter,
    );
  }
}

/// Shown when the app was built without --dart-define, so it has no real
/// Supabase URL or key. Deliberately blunt and developer-facing: this can
/// only ever be seen by someone running a mis-built binary, and the whole
/// point is that it names the cause instead of presenting as a network
/// fault.
class _MisconfiguredBuildScreen extends StatelessWidget {
  const _MisconfiguredBuildScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ManaColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build_circle_outlined,
                    size: 48, color: ManaColors.accent),
                SizedBox(height: ManaSpacing.md),
                Text(
                  'Build not configured',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: ManaColors.textOnDark,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ManaSpacing.sm),
                Text(
                  'This build has no Supabase URL or key, so every request '
                  'goes to a host that does not exist and simply hangs — it '
                  'is not a network problem.\n\n'
                  'Rebuild with the --dart-define arguments (see run.ps1.txt '
                  'in the project root).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ManaColors.textOnDark, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
