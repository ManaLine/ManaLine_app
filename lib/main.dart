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
    accessToken: () async => ManaSession.instance.currentAccessToken,
  );

  // Cold-start hydration (LR-001's actual job per this session's Item E) —
  // restores a persisted session token/person_id from flutter_secure_storage
  // before the router's first health-check redirect decision fires.
  await ManaSession.instance.hydrateFromSecureStorage();

  runApp(const ProviderScope(child: ManaLineApp()));
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
