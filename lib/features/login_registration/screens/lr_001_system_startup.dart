import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_brand_mark.dart' show kManaAppName;
import '../../../design/components/mana_centered_scroll.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';

enum _StartupState { loading, slowLoad, failure }

/// LR-001 — root screen, no user input, sequential health checks then
/// auto-navigate. Per spec: System Status Indicator only appears if
/// init exceeds 1.5s, to avoid flash-of-loading-state on fast connections.
class SystemStartupScreen extends ConsumerStatefulWidget {
  const SystemStartupScreen({super.key});

  @override
  ConsumerState<SystemStartupScreen> createState() => _SystemStartupScreenState();
}

class _SystemStartupScreenState extends ConsumerState<SystemStartupScreen> {
  _StartupState _state = _StartupState.loading;

  /// Keeps re-running the health checks while this screen is showing its
  /// failure card, so the app continues on its own once signal returns
  /// instead of waiting for someone to notice and press Retry. The button
  /// stays — it is the "try now" for anyone who does not want to wait —
  /// but it is no longer the only way out.
  Timer? _retryTimer;

  /// The 1.5s "this is taking a while" timer.
  ///
  /// A real Timer held in a field rather than a bare Future.delayed, so
  /// dispose can cancel it. As a Future it kept running after the screen was
  /// gone — harmless in the app because the callback checks `mounted`, but it
  /// left a pending timer behind, which is a leak in the small and made the
  /// screen impossible to write a widget test for at all.
  Timer? _slowLoadTimer;

  @override
  void initState() {
    super.initState();
    _runHealthChecks();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _slowLoadTimer?.cancel();
    super.dispose();
  }

  void _retryNow() {
    _retryTimer?.cancel();
    if (!mounted) return;
    setState(() => _state = _StartupState.loading);
    _runHealthChecks();
  }

  Future<void> _runHealthChecks() async {
    // Show the status indicator only if we cross 1.5s — per spec.
    _slowLoadTimer?.cancel();
    _slowLoadTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _state == _StartupState.loading) {
        setState(() => _state = _StartupState.slowLoad);
      }
    });

    try {
      // The spec asks for GET /system/health then GET /system/config. Neither
      // endpoint exists, and neither is going to — this deployment has no
      // application server, only Postgres behind PostgREST. What used to sit
      // here was `Future.delayed(600ms)`, which passed unconditionally: a
      // build pointed at a dead Supabase URL sailed through the screen whose
      // entire job is to catch that, and only fell over several screens later
      // as raw translation keys and a login claiming "No internet connection".
      //
      // Loading the translation cache IS the health check, and it is the
      // honest one. It is a real round trip to the real project, so it proves
      // in one call everything the four sequential checks were meant to prove
      // — the URL resolves, PostgREST answers, the anon key is accepted, and
      // the schema this build expects is there. It is also work the app has to
      // do anyway before any screen can render a word, so this costs nothing
      // and warms the cache the next screen needs.
      final cache = ref.read(translationCacheProvider);
      await cache.load();
      if (cache.lastError != null) throw cache.lastError!;
      // The check finished, so the "taking a while" indicator must not fire
      // after the fact. This line used to be
      // `await slowTimer.timeout(Duration.zero, ...)`, which read like it was
      // waiting for something and did nothing at all — a zero timeout on a
      // 1.5s future always elapses immediately, and the callback still ran.
      _slowLoadTimer?.cancel();

      if (!mounted) return;

      // Per LR-009's own ENTRY POINT: route to Daily Login (fast PIN
      // path) if this device already has a PIN set up; otherwise fall
      // through to the normal Workspace Choice → Registration/First
      // Login flow. This is the missing half of that screen's entry
      // condition — LR-009 can't reach itself, LR-001 has to send it
      // there. (The other half of LR-009's stated condition — an
      // is_active `devices` row server-side — can't be checked without
      // a live backend yet; local pin_length is the reliable signal
      // available in this scaffold and will remain correct once the
      // device-row check is added alongside the real API call.)
      final pinLength = await LocalAuthStore.readPinLength();
      if (!mounted) return;

      context.go(pinLength != null ? '/lr-009' : '/lr-002');
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _StartupState.failure);
      // 3s rather than a connectivity listener: the check that matters is
      // whether this request succeeds, not whether the handset believes it
      // has a network. A captive portal reports "connected" and answers
      // nothing.
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 3), _retryNow);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A FIXED white, not ManaColors.surface. The Android window background
      // is painted before Flutter's first frame and cannot follow the app
      // theme, so the two must name the same literal colour or the handover
      // flashes. Same reasoning as android/app/src/main/res/values/colors.xml,
      // where splash_background is the matching #FFFFFF.
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        // Scrollable, and not because the splash is long. At 2.0x text scale
        // on a 360x640 handset the mark plus the failure card and its retry
        // button do not fit, and a Column would simply clip the button — the
        // one control someone with no signal actually needs. It scrolls
        // instead, and centres whenever there is room, which is almost always.
        child: ManaCenteredScroll(
          padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The wordmark and the tagline used to be laid out again in text
              // underneath a 96px logo. They are both already inside the mark
              // — "MANA LINE" and "EVERY ₹ COUNTS" are drawn into it — so at
              // this size that was the same two lines twice. The Semantics
              // label keeps them available to a screen reader, which is the
              // only reader that lost anything.
              Semantics(
                label: '$kManaAppName. ${ref.t('every_rupee_counts')}',
                image: true,
                child: _SplashLogo(),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              if (_state == _StartupState.slowLoad) ...[
                CircularProgressIndicator(color: ManaColors.brand),
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw(ref.t('loading_ellipsis'),
                    style: TextStyle(color: ManaColors.textPrimary)),
              ],
              if (_state == _StartupState.failure) _FailureCard(onRetry: _retryNow),
            ],
          ),
        ),
      ),
    );
  }
}

/// The brand mark at opening size — as wide as the screen allows.
///
/// Width normally wins: the mark spans the display less one 12dp step either
/// side. The height cap only bites on a short, wide screen — a landscape
/// tablet — where a width-sized square would be taller than the display.
class _SplashLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final side = math.min(
      media.size.width - ManaSpacing.md * 2,
      media.size.height * 0.7,
    );
    return Image.asset(
      'assets/images/logo.png',
      width: side,
      height: side,
      // Decode at display size rather than holding the full 1024² bitmap.
      // This is the first thing that runs on a cheap Android.
      cacheWidth: (side * media.devicePixelRatio).round(),
      // contain, not cover: the asset is cropped to the circle's own edge, so
      // cover would shave the rim off at any non-square box.
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(height: side),
    );
  }
}

class _FailureCard extends ConsumerWidget {
  final VoidCallback onRetry;
  const _FailureCard({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Icon(Icons.wifi_off, color: ManaColors.statusBad, size: 32),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(
          ref.t('unable_to_connect_note'),
          textAlign: TextAlign.center,
          // The screen behind this is a fixed white now, so the copy has to
          // be dark ink — textOnDark was white on white, an invisible error
          // message on the one screen where losing it costs the most.
          style: TextStyle(color: ManaColors.textPrimary),
        ),
        const SizedBox(height: ManaSpacing.md),
        ElevatedButton(onPressed: onRetry, child: ManaText.raw(ref.t('retry'))),
      ],
    );
  }
}
