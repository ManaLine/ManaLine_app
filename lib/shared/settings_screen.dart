import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';
import 'widgets/language_selector.dart';
import 'local_auth_store.dart';
import 'network_error_handler.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import '../features/login_registration/state/auth_api_service.dart';

/// Shared Settings screen, used by all four workspaces (Owner/Agent/
/// Investor/Customer) — one implementation instead of four near-identical
/// files, since the content is genuinely role-independent (language,
/// security, device info, logout). Role-specific administration
/// (Business Management, Workforce Management, etc.) stays in each
/// workspace's own menu/quick-actions, not here — this screen is
/// deliberately generic.
///
/// Every item here is real and functional:
///  - Language: session-scoped via authFlowProvider (same mechanism
///    already used at LR-002/009). NOTE: does not yet persist to
///    persons.preferred_language server-side — no update endpoint exists
///    for that yet (only set once at registration/first-login per the
///    original ManaLanguageSelector's own doc comment). Flagged, not
///    silently faked as if it persists.
///  - Biometric status: read-only display (LocalAuthStore has no
///    standalone toggle-write path — it's bundled into the Create/Reset
///    PIN flow). Change it via Forgot PIN below, not a fake toggle here.
///  - Security: real links to the existing password/PIN reset flows.
///  - Logout: real, same pattern as every workspace's existing logout.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Route to go back to (each workspace's own home).
  final String homeRoute;

  /// Passed through as `extra` on the way back — without this, the back
  /// button fell through to router.dart's stub-business-id fallback,
  /// which is the confirmed root cause of the reported "back click ->
  /// dead end, unable to load dashboard" bug.
  final String? businessId;
  const SettingsScreen({super.key, required this.homeRoute, this.businessId});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _biometricEnabled;
  bool _togglingBiometric = false;
  // Matches pubspec.yaml's `version: 0.1.0` — kept as a plain literal
  // rather than pulling in package_info_plus (not an existing
  // dependency) for one static line. Update this alongside pubspec.yaml
  // if the version changes.
  static const _versionLabel = 'v0.1.0';

  @override
  void initState() {
    super.initState();
    LocalAuthStore.readBiometricEnabled().then((v) {
      if (mounted) setState(() => _biometricEnabled = v);
    });
  }

  Future<void> _onBiometricToggled(bool wantEnabled) async {
    if (!wantEnabled) {
      // Disabling needs no verification — it only reduces convenience,
      // never grants access.
      await LocalAuthStore.setBiometricEnabled(false);
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    final pinLength = await LocalAuthStore.readPinLength();
    if (pinLength == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Set up a PIN first (via Forgot/Reset PIN) before enabling biometric login.')),
      );
      return;
    }

    // Real server-side PIN verification before enabling — same
    // "identity re-confirmed via the real login RPC" pattern already
    // used elsewhere (LR-011's password-gated PIN reset), not just a
    // local string comparison. Note: this enables the STORED-PIN
    // convenience-retrieval path LR-009 already has (biometric unlock
    // fetches the locally-saved PIN and submits it as a normal login) —
    // it does not itself trigger a real fingerprint/Face ID hardware
    // prompt. That native prompt is a separate, not-yet-built piece
    // (LR-009's own code has a TODO for wiring the `local_auth` package)
    // — flagged honestly here rather than implied as already working.
    final entered = await showDialog<String>(
        context: context, builder: (_) => const _PinVerifyDialog());
    if (entered == null || entered.length != pinLength) return;

    setState(() => _togglingBiometric = true);
    final mobile = await LocalAuthStore.readLastMobileNumber();
    final fingerprint = await LocalAuthStore.deviceFingerprint();
    if (mobile == null) {
      setState(() => _togglingBiometric = false);
      return;
    }

    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(authApiServiceProvider).login(
            identifier: mobile,
            credential: entered,
            credentialType: 'pin',
            deviceFingerprint: fingerprint,
          );
    });
    if (!mounted) return;
    setState(() => _togglingBiometric = false);

    if (result == null) return; // network failure — SnackBar already shown
    if (!result.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Incorrect PIN.')));
      return;
    }

    await LocalAuthStore.setBiometricEnabled(true);
    if (!mounted) return;
    setState(() => _biometricEnabled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Biometric login enabled for this device.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(authFlowProvider).language;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.go(widget.homeRoute, extra: widget.businessId)),
        title: const ManaText('settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const _SectionHeader('language'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
              child: ManaLanguageSelector(
                current: lang,
                onChanged: (l) async {
                  ref.read(authFlowProvider.notifier).setLanguage(l);
                  final personId = ref.read(authFlowProvider).personId;
                  if (personId == null) return; // session-only if not logged in
                  try {
                    await Supabase.instance.client
                        .from('persons')
                        .update({'preferred_language': l.enumValue}).eq(
                            'person_id', personId);
                  } catch (_) {
                    // Non-fatal — language still applies for this session
                    // even if the DB write fails; no need to block the UI
                    // over a preference persistence hiccup.
                  }
                },
              ),
            ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('security'),
            _SettingsTile(
              icon: Icons.lock_outline,
              title: 'Forgot / Reset Password',
              onTap: () => context.push('/lr-010'),
            ),
            _SettingsTile(
              icon: Icons.pin_outlined,
              title: 'Forgot / Reset PIN',
              onTap: () => context.push('/lr-011'),
            ),
            _SettingsTile(
              icon: Icons.fingerprint,
              title: 'Biometric Login',
              trailing: _biometricEnabled == null
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch(
                      value: _biometricEnabled!,
                      onChanged:
                          _togglingBiometric ? null : _onBiometricToggled,
                    ),
              subtitle: _biometricEnabled == true
                  ? 'Enabled — used for fast PIN login on this device.'
                  : 'Enable to skip typing your PIN on this device.',
              onTap: null,
            ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('about'),
            const _SettingsTile(
                icon: Icons.info_outline,
                title: 'App Version',
                trailing: ManaText.raw(_versionLabel)),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('account'),
            _SettingsTile(
              icon: Icons.logout,
              title: 'Logout',
              titleColor: ManaColors.statusBad,
              onTap: () {
                ref.read(authFlowProvider.notifier).reset();
                context.go('/lr-003');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);
  @override
  Widget build(BuildContext context) => ManaText(
        label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ManaColors.textSecondary,
            letterSpacing: 1),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: titleColor),
      title: ManaText.raw(title, style: TextStyle(color: titleColor)),
      subtitle: subtitle != null
          ? ManaText.raw(subtitle!, style: const TextStyle(fontSize: 13))
          : null,
      trailing: trailing,
      onTap: onTap,
      enabled: onTap != null,
    );
  }
}

/// Simple PIN-entry dialog used to re-verify identity before enabling
/// biometric login. Returns the entered PIN string, or null if cancelled.
class _PinVerifyDialog extends StatefulWidget {
  const _PinVerifyDialog();
  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ManaText('confirm your pin'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Enter PIN'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const ManaText('cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const ManaText('confirm'),
        ),
      ],
    );
  }
}
