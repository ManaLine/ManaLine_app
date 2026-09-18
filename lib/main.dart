import 'package:flutter/material.dart';
import 'shared/widgets/workspace_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/router.dart';
import 'shared/appearance_state.dart';
import 'shared/mana_back_handler.dart';
import 'design/theme.dart';
import 'design/tokens/colors.dart';
import 'design/tokens/spacing.dart';
import 'features/login_registration/state/auth_flow_state.dart';
import 'shared/mana_error_reporting.dart';
import 'shared/outbox/mana_outbox_provider.dart';
import 'shared/outbox/mana_outbox_watcher.dart';
import 'shared/supabase_config.dart';

Future<void> main() async {
  await bootstrapManaApp(router: manaRouter);
  // THE OUTBOX IS ANDROID-ONLY, and opened here rather than in
  // bootstrapManaApp because main_web.dart shares that function. sqflite has
  // no web implementation, and /ow-006 is not on the web router anyway -- a
  // hand-typed one lands on the route-unavailable screen.
  //
  // A failure to open must not stop the app launching. Without the queue a
  // collection on a dead connection fails the way it always used to, which is
  // worse than before this existed and far better than an app that will not
  // start.
  await manaOpenOutbox();
  // manaRunApp, not runApp: it installs the Flutter error handler and runs
  // the app inside a guarded zone, so a throw inside a widget build, a
  // gesture callback or an unawaited future reaches somebody who can fix it.
  // With no SENTRY_DSN defined it is exactly runApp, which is what a local
  // debug build and CI both get.
  await manaRunApp(const ProviderScope(child: ManaLineApp()));
}

/// Everything both entrypoints need before `runApp` — Android's
/// [main] above and the web build's `main_web.dart`. Pulled out here
/// rather than left duplicated in both files: this project has already
/// paid twice for two copies of the same setup drifting apart (see
/// CLAUDE.md's "Not breaking the thing next to the thing you fixed"),
/// and writing a second `Supabase.initialize`/hydrate/orientation block
/// for the web entrypoint would be exactly that mistake on the task
/// whose entire purpose is preventing drift.
///
/// [router] is the one piece that legitimately differs — Android drives
/// `manaRouter`, the web build drives the restricted `manaWebRouter` — so
/// it is a parameter rather than baked in, and it is also what the
/// expired-token redirect below must send `.go('/lr-009')` through: that
/// route exists on both routers, but it must be the SAME instance whose
/// `go()` is later handed to `MaterialApp.router` for the redirect to be
/// visible on screen.
Future<void> bootstrapManaApp({required GoRouter router}) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only. This is a one-handed field app: an Agent stands at a door
  // holding a phone and a cash bag, and every screen is laid out and tested
  // for a 360dp-wide portrait surface at text scales up to 2.0. Landscape was
  // not a supported shape and it showed -- the opening screen stranded its
  // logo against a wide empty band. Locking here is one line and undoing it
  // is one line, but every screen would need laying out again first.
  //
  // A no-op on the web build (there is no device orientation to lock), so
  // sharing this call costs nothing there.
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );

  // Manrope and Inter are bundled in assets/fonts/ and declared in
  // pubspec.yaml, so nothing should ever reach for the network. This stays as
  // a hard stop rather than a formality: if a family name is ever mistyped,
  // runtime fetching would quietly paper over it on a developer's fast wifi
  // and fail in a village. false makes that a visible fallback here too.
  GoogleFonts.config.allowRuntimeFetching = false;

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
        _redirectToPinLogin(router);
      }
      return session.currentAccessToken;
    },
  );

  // Cold-start hydration (LR-001's actual job per this session's Item E) —
  // restores a persisted session token/person_id from flutter_secure_storage
  // before the router's first health-check redirect decision fires.
  await ManaSession.instance.hydrateFromSecureStorage();

  // The three actions every Owner and Agent header carries. Installed once
  // rather than assembled at 45 call sites -- see manaInstallWorkspaceActions.
  manaInstallWorkspaceActions();
}

/// Sends the person to PIN entry once, from wherever they were.
///
/// Guarded because the accessToken callback fires per request and a screen
/// typically issues several at once — without this, one expiry would push
/// half a dozen duplicate routes onto the stack. The flag clears on the
/// next frame, so a genuinely later expiry still redirects.
bool _redirectingToLogin = false;

void _redirectToPinLogin(GoRouter router) {
  if (_redirectingToLogin) return;
  _redirectingToLogin = true;
  // Scheduled rather than immediate: this runs inside a network callback,
  // which may be mid-build or mid-frame, and go_router must not be driven
  // from there.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    router.go('/lr-009');
    _redirectingToLogin = false;
  });
}

class ManaLineApp extends ConsumerWidget {
  // Defaults to `manaRouter` so Android's call site (`runApp(const
  // ProviderScope(child: ManaLineApp()))`) is untouched. main_web.dart is
  // the only other constructor call, and it passes `manaWebRouter` — the
  // restricted router built in lib/app/web_router.dart. Everything else
  // (theme, misconfigured-build guard, text-scale handling) is identical
  // between the two builds; only the routed screen set differs.
  // Nullable rather than `= manaRouter`: a default parameter value must be
  // a compile-time constant, and manaRouter is a `final` top-level
  // GoRouter built at load time, not a const. The fallback happens in
  // [build] instead.
  const ManaLineApp({super.key, GoRouter? router}) : _router = router;

  final GoRouter? _router;
  GoRouter get router => _router ?? manaRouter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final appearance = ref.watch(appearanceProvider);

    // Which palette the tokens must resolve against. Decided HERE rather than
    // left to MaterialApp, because ManaColors is global state and the ~840
    // token call sites read it at build time — the theme and the tokens have
    // to be told the same thing, in that order, before anything renders.
    final platformDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final wantDark = switch (appearance.theme) {
      ManaThemeChoice.dark => true,
      ManaThemeChoice.light => false,
      ManaThemeChoice.system => platformDark,
    };
    final palette = wantDark ? ManaPalette.dark : ManaPalette.light;
    final themeData = ManaTheme.forPalette(palette);

    return MaterialApp.router(
      title: 'MANA LINE',
      debugShowCheckedModeBanner: false,
      // Both slots get the SAME resolved theme, and themeMode is left alone.
      // Handing MaterialApp a light and a dark theme and letting it choose
      // would let it switch without ManaColors.use() running, which is
      // precisely the state where the chrome is dark and every card is still
      // light.
      theme: themeData,
      darkTheme: themeData,
      // The pieces individually rather than routerConfig, so the back
      // button dispatcher can be ours. routerConfig supplies GoRouter's own,
      // and back would go straight to an empty stack and close the app.
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      backButtonDispatcher: ManaBackButtonDispatcher(),
      // The chosen font size, applied once at the root so every screen and
      // every dialog inherits it.
      //
      // MULTIPLIED with the device's own setting rather than replacing it:
      // someone who has already enlarged text system-wide has said something
      // about their eyesight, and overriding that to a flat 1.0 would take it
      // away. The layout tests cover 1.0x-2.0x, and this tops out at 1.3x on
      // top of whatever the handset is already doing.
      builder: (context, child) {
        // The device's own factor, recovered by asking it to scale a known
        // size. TextScaler has no "factor" getter and is not necessarily
        // linear, so this samples it rather than assuming.
        final deviceFactor = MediaQuery.textScalerOf(context).scale(100) / 100;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(deviceFactor * appearance.textSize.scale),
          ),
          // NO SelectionArea here.
          //
          // It was here for one build and took the whole app down with it:
          // SelectableRegion requires an Overlay ancestor, and this builder
          // sits ABOVE the Navigator that provides one, so it threw during
          // build and every screen became an ErrorWidget. Copy-paste has to
          // be introduced below the Navigator -- inside the screens -- not
          // above it.
          // The outbox drains from here, above every screen and below the
          // Navigator, so it keeps running while an agent moves around the
          // app. "Queue it until live" is only true if something notices when
          // live happens; without this the queue waits for somebody to open
          // it and press retry, which is a worse promise than the one made.
          child: ManaOutboxWatcher(
            // ManaWebFrame USED TO BE HERE, and it is gone.
            //
            // It clamped every web page to a measure from up here, above the
            // Navigator -- which is exactly why its route check never worked:
            // the configuration has no matches at this level, so the path it
            // matched against was the empty string for the whole of its life.
            //
            // Both jobs moved into web_router.dart, where the route is the
            // thing that selected the builder and cannot be unknown:
            // ManaWebShell frames the twenty-one signed-in pages and
            // ManaAuthShell the twelve signed-out ones. That also fixed a
            // second problem this position made unavoidable -- a measure
            // applied here wrapped the navigation rail as well as the
            // content, leaving the whole assembly floating in the middle of
            // a wide monitor.
            child: child!,
          ),
        );
      },
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
    return Scaffold(
      backgroundColor: ManaColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.build_circle_outlined, size: 48, color: ManaColors.accent),
                const SizedBox(height: ManaSpacing.md),
                Text(
                  'Build not configured',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: ManaColors.textOnDark, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: ManaSpacing.sm),
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
