import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';

enum _StartupState { loading, slowLoad, failure }

/// LR-001 — root screen, no user input, sequential health checks then
/// auto-navigate. Per spec: System Status Indicator only appears if
/// init exceeds 1.5s, to avoid flash-of-loading-state on fast connections.
class SystemStartupScreen extends StatefulWidget {
  const SystemStartupScreen({super.key});

  @override
  State<SystemStartupScreen> createState() => _SystemStartupScreenState();
}

class _SystemStartupScreenState extends State<SystemStartupScreen> {
  _StartupState _state = _StartupState.loading;

  @override
  void initState() {
    super.initState();
    _runHealthChecks();
  }

  Future<void> _runHealthChecks() async {
    // Show the status indicator only if we cross 1.5s — per spec.
    final slowTimer = Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _state == _StartupState.loading) {
        setState(() => _state = _StartupState.slowLoad);
      }
    });

    try {
      // TODO: real GET /system/health then GET /system/config, sequential
      // per spec (Server Available → DB Connected → API Version Valid →
      // Application Version Valid), then parallel non-blocking config load.
      await Future.delayed(const Duration(milliseconds: 600));
      await slowTimer.timeout(Duration.zero, onTimeout: () {}).catchError((_) {});

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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ManaColors.ink,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  // 1254x1254 source rendered at ~96px. cacheWidth decodes at
                  // display size rather than holding a 2.4MB full-res bitmap
                  // in memory — this is a cheap-Android target and the splash
                  // is the first thing that runs.
                  cacheWidth: 288,
                  height: 96,
                  width: 96,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              Text(
                'MANA LINE',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: ManaColors.textOnDark,
                    ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              // Tagline: EVERY ₹ COUNTS, with the rupee as the hero.
              //
              // The ₹ is `accent` gold and oversized. The WORDS are
              // textOnDark, not black: this screen's background is
              // ManaColors.ink (dark navy), so black-on-dark would be
              // invisible. See the note in the build method below if the
              // splash is ever moved to a light surface — `accent` is
              // 1.76:1 on white and must never become ink there.
              Semantics(
                label: 'Every rupee counts',
                excludeSemantics: true,
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      color: ManaColors.textOnDark,
                      letterSpacing: 3,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      const TextSpan(text: 'EVERY '),
                      TextSpan(
                        text: '₹',
                        style: TextStyle(
                          color: ManaColors.accent,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const TextSpan(text: ' COUNTS'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              if (_state == _StartupState.slowLoad) ...[
                CircularProgressIndicator(color: ManaColors.brand),
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw('Loading...', style: TextStyle(color: ManaColors.textOnDark)),
              ],
              if (_state == _StartupState.failure) _FailureCard(onRetry: () {
                setState(() => _state = _StartupState.loading);
                _runHealthChecks();
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _FailureCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.wifi_off, color: ManaColors.statusBad, size: 32),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(
          'Unable to connect. Please check your internet connection and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(color: ManaColors.textOnDark),
        ),
        const SizedBox(height: ManaSpacing.md),
        ElevatedButton(onPressed: onRetry, child: const ManaText('retry')),
      ],
    );
  }
}
