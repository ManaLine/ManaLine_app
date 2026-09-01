import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'translation_service.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import 'widgets/language_selector.dart';
import 'local_auth_store.dart';
import 'mana_biometric.dart';
import 'network_error_handler.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import '../features/login_registration/state/auth_api_service.dart';
import '../features/owner_workspace/state/business_transfer_state.dart';

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
  bool? _pinEnabled;
  bool _togglingPin = false;

  /// Wrong-PIN attempts inside this dialog. Capped BELOW the server's own
  /// lockout threshold so verifying a toggle can never be the thing that
  /// locks someone out of their account.
  int _pinAttempts = 0;
  static const _maxPinAttempts = 2;

  /// Each workspace's own profile screen. Settings is shared across all four,
  /// so the destination is derived from whichever home route was passed in
  /// rather than duplicating this screen per role.
  ///
  /// The `_` arm is reached from LR-012, which sits above role selection and
  /// so has no home route to derive from. It used to return null, which hid
  /// the Profile row entirely — and LR-012's profile photo now points here,
  /// so that would have been a tap that led nowhere. It falls back to the
  /// last role this device actually used instead. Still null on a genuinely
  /// first-ever login, where there is no prior role and no profile to show
  /// yet; the row renders disabled rather than vanishing.
  String? get _profileRoute => switch (widget.homeRoute) {
        '/ow-001' => '/ow-016',
        '/ag-001' => '/ag-009',
        '/cw-001' => '/cw-006',
        '/iw-001' => '/iw-005',
        _ => _lastUsedProfileRoute,
      };

  /// Whether this workspace is the Owner's, derived the same way the profile
  /// route is rather than from a second source of truth.
  bool get _isOwner => widget.homeRoute == '/ow-001';

  /// True once a transfer has actually been offered to this person. Null while
  /// the check is in flight, which renders as "not yet" — a row that appears a
  /// moment late is better than one that flashes and disappears.
  bool _hasIncomingTransfer = false;

  bool get _showsBusinessTransfer => _isOwner || _hasIncomingTransfer;

  /// Asked once, on open. A failure leaves the row hidden for a non-Owner:
  /// the Owner's own path does not depend on this call, and an offer that
  /// exists will still be there next time.
  Future<void> _checkIncomingTransfer() async {
    if (_isOwner) return;
    try {
      final transfers =
          await ref.read(businessTransferApiServiceProvider).list();
      final incoming = transfers.any(
          (t) => t.direction == 'incoming' && t.status == 'Pending');
      if (mounted && incoming) setState(() => _hasIncomingTransfer = true);
    } catch (_) {
      // Settings must open whether or not this answers.
    }
  }

  /// Resolved from the entity ids ManaSession caches when LR-013 last
  /// resolved a membership. Shared with LR-012's header avatar, which needs
  /// the same answer for the same reason.
  String? get _lastUsedProfileRoute => manaLastUsedProfileRoute();
  /// Opens the system share sheet. No app store link yet — MANA LINE is not
  /// published — so the message says what the app is rather than pointing at a
  /// download that would 404. Add the store URL here when there is one.
  Future<void> _shareApp() async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'MANA LINE — the app my lending business runs on. It keeps every '
            'loan, collection and daily balance in one place.',
        subject: 'MANA LINE',
      ),
    );
  }

  /// Backup exports business records, so it only means anything in the two
  /// workspaces that have them. The server is still the authority — RLS
  /// decides what any given person can actually read — this only keeps the row
  /// out of sight where it could not produce anything.
  bool get _backupIsAvailable =>
      widget.homeRoute == '/ow-001' || widget.homeRoute == '/ag-001';

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
    LocalAuthStore.readPinLength().then((v) {
      if (mounted) setState(() => _pinEnabled = v != null);
    });
    _checkIncomingTransfer();
  }

  /// Enables PIN login on this device using the PIN the person ALREADY has.
  /// This is not PIN creation -- it verifies the existing PIN against the
  /// real login RPC and then stores it locally, so a re-installed or second
  /// device can be armed without going through a reset.
  Future<void> _onPinToggled(bool wantEnabled) async {
    if (!wantEnabled) {
      // Dropping the stored PIN also drops biometric, which is only a
      // convenience wrapper around it -- leaving biometric on would point at
      // a PIN that is no longer there.
      await LocalAuthStore.clearPin();
      await LocalAuthStore.setBiometricEnabled(false);
      if (mounted) {
        setState(() {
          _pinEnabled = false;
          _biometricEnabled = false;
        });
      }
      return;
    }

    final mobile = await LocalAuthStore.readLastMobileNumber();
    if (mobile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log in once on this device first.')),
      );
      return;
    }

    if (!mounted) return;
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _PinVerifyDialog(
        title: 'enter your pin',
        label: 'Your existing PIN',
      ),
    );
    if (entered == null || entered.length < 4) return;

    setState(() => _togglingPin = true);
    final fingerprint = await LocalAuthStore.deviceFingerprint();
    if (!mounted) return;

    // AccountLockedException is caught HERE rather than left to the generic
    // handler. Verifying a PIN goes through the real login endpoint, so a
    // wrong PIN increments the SAME server-side failed_pin_attempts counter
    // as a real login — three wrong guesses in this dialog locked the
    // account and dumped the person out to the password screen, from a
    // screen whose only purpose was flipping a convenience toggle.
    LoginResult? result;
    AccountLockedException? locked;
    final reached = await NetworkErrorHandler.run(context, () async {
      try {
        result = await ref.read(authApiServiceProvider).login(
              identifier: mobile,
              credential: entered,
              credentialType: 'pin',
              deviceFingerprint: fingerprint,
            );
      } on AccountLockedException catch (e) {
        locked = e;
      }
      return true;
    });
    if (!mounted) return;
    setState(() => _togglingPin = false);

    if (reached == null) return; // network failure — SnackBar already shown

    if (locked != null) {
      _pinAttempts = 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(locked!.message),
        duration: const Duration(seconds: 6),
      ));
      return;
    }

    if (result == null || !result!.success) {
      _pinAttempts++;
      final remaining = _maxPinAttempts - _pinAttempts;
      if (remaining > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Incorrect PIN. $remaining ${remaining == 1 ? "try" : "tries"} left.'),
        ));
        // Straight back into the dialog — the toggle is still off, and
        // making the person find it again to retry is why this read as
        // "it just logs me out".
        await _onPinToggled(true);
      } else {
        _pinAttempts = 0;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Incorrect PIN. Stopping here so your account is not locked.'),
          duration: Duration(seconds: 6),
        ));
      }
      return;
    }
    _pinAttempts = 0;

    // Only stored after the server confirmed it — never on local guesswork.
    await LocalAuthStore.savePin(
        pin: entered, biometricEnabled: _biometricEnabled ?? false);
    if (!mounted) return;
    setState(() => _pinEnabled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN login enabled on this device.')),
    );
  }

  Future<void> _onBiometricToggled(bool wantEnabled) async {
    if (!wantEnabled) {
      // Disabling needs no verification — it only reduces convenience,
      // never grants access.
      await LocalAuthStore.setBiometricEnabled(false);
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    // Nothing to enable if the handset cannot do it. Checked before the PIN
    // dialog so the person is not asked to prove themselves for a feature
    // their phone does not have.
    if (!await ManaBiometric.isAvailable()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'This phone has no fingerprint or face unlock set up. Add one in phone settings first.')),
      );
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

    // The fingerprint itself, before anything is stored. Turning this on means
    // "this finger may replay my saved PIN", so the finger has to be present
    // at the moment the permission is granted — otherwise someone holding an
    // unlocked phone could enable it with a PIN they shoulder-surfed and then
    // use their OWN fingerprint from then on.
    final bio = await ManaBiometric.authenticate(
      reason: 'Confirm your fingerprint to turn on biometric sign-in',
    );
    if (!mounted) return;
    if (bio != ManaBiometricResult.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ManaBiometric.messageFor(bio))),
      );
      return;
    }

    // Then the server-side PIN check — same "identity re-confirmed via the
    // real login RPC" pattern as LR-011's password-gated PIN reset, not a
    // local string comparison.
    if (!mounted) return;
    final entered = await showDialog<String>(
        context: context, builder: (_) => const _PinVerifyDialog());
    if (entered == null || entered.length != pinLength) return;

    if (!mounted) return;
    setState(() => _togglingBiometric = true);
    final mobile = await LocalAuthStore.readLastMobileNumber();
    final fingerprint = await LocalAuthStore.deviceFingerprint();
    if (mobile == null) {
      if (!mounted) return;
      if (!mounted) return;
      setState(() => _togglingBiometric = false);
      return;
    }
    if (!mounted) return;

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
      appBar: ManaAppBar(
        title: ref.t('settings'),
        homeRoute: widget.homeRoute,
        homeExtra: widget.businessId,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            // ORDER IS LOCKED: Profile, Permissions, Subscription, Backup,
            // Security, Business Transfer, Share App, Appearance, Languages,
            // About, Logout.
            //
            // Six of those are P2/P3/P4 features that do not exist yet. They
            // are rendered here as disabled "Coming Soon" rows rather than
            // omitted, so the order is fixed once and later phases fill a row
            // instead of reshuffling a screen users have already learned. A
            // disabled row is also honest — it says "not yet", where an absent
            // row says "never", and a row wired to a dead route would say
            // "broken".
            //
            // `Account` is gone. It held exactly one item, Logout, which now
            // sits at the bottom in its own right.
            if (_profileRoute != null) ...[
              const _SectionHeader('profile'),
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'Profile',
                subtitle: 'Your details, documents and memberships.',
                onTap: () =>
                    context.push(_profileRoute!, extra: widget.businessId),
              ),
              const SizedBox(height: ManaSpacing.lg),
            ],
            const _SectionHeader('permissions'),
            // Points at OW-002, which already has the real editor — every
            // permission column, per agent, with the server as the authority.
            // Building a second one here would be two places to change the
            // same switch, and they would disagree the first time one was
            // edited.
            //
            // Owner only: permissions are something an Owner grants, not
            // something an Agent sets for themselves. An Agent seeing their
            // own permissions read-only would be reasonable, but that is a
            // screen that does not exist yet and is not worth faking.
            widget.homeRoute == '/ow-001'
                ? _SettingsTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Permissions',
                    subtitle: 'Set what each agent is allowed to do.',
                    onTap: () =>
                        context.push('/ow-002', extra: widget.businessId),
                  )
                : const _SettingsTile(
                    icon: Icons.verified_user_outlined,
                    title: 'Permissions',
                    subtitle: 'What each agent is allowed to do.',
                    trailing: _ComingSoon(),
                  ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('subscription'),
            // Owner only. The tiers priced here are the Owner's; a Customer or
            // Investor pays per role, and showing them an agent cap would be
            // answering a question they did not ask.
            widget.homeRoute == '/ow-001'
                ? _SettingsTile(
                    icon: Icons.card_membership_outlined,
                    title: 'Subscription',
                    subtitle: 'Your plan and its limits.',
                    onTap: () =>
                        context.push('/subscription', extra: widget.businessId),
                  )
                : const _SettingsTile(
                    icon: Icons.card_membership_outlined,
                    title: 'Subscription',
                    subtitle: 'Your plan and its limits.',
                    trailing: _ComingSoon(),
                  ),
            // Owner only, and deliberately not offered to an Agent even
            // with can_delete_records: destroying a record for good is the
            // Owner's call, and the server refuses it from anyone the
            // business does not have as one.
            if (widget.homeRoute == '/ow-001')
              _SettingsTile(
                icon: Icons.delete_outline,
                title: 'Trash',
                subtitle: 'Deleted records, and delete forever.',
                onTap: () => context.push('/ow-trash', extra: widget.businessId),
              ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('backup'),
            // Live for the Owner and Agent workspaces. Customers and Investors
            // keep the placeholder: they hold no business records, so a
            // "backup" there would produce six empty sheets, which reads as a
            // broken export rather than an empty one.
            _backupIsAvailable
                ? _SettingsTile(
                    icon: Icons.backup_outlined,
                    title: 'Backup',
                    subtitle: 'Export your records to Excel.',
                    onTap: () =>
                        context.push('/backup', extra: widget.businessId),
                  )
                : const _SettingsTile(
                    icon: Icons.backup_outlined,
                    title: 'Backup',
                    subtitle: 'Export your records to Excel.',
                    trailing: _ComingSoon(),
                  ),
            // Import sits under Backup rather than in its own section: they
            // are the two halves of the same job, and separating them put a
            // heading between "get your records out" and "put your records in".
            if (_backupIsAvailable)
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                title: 'Import Records',
                subtitle: 'Enter loans from before you joined MANA LINE.',
                onTap: () => context.push('/import', extra: widget.businessId),
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
              icon: Icons.password_outlined,
              title: 'Enable PIN Login',
              trailing: _pinEnabled == null
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch(
                      value: _pinEnabled!,
                      onChanged: _togglingPin ? null : _onPinToggled,
                    ),
              subtitle: _pinEnabled == true
                  ? 'Enabled — you can sign in with your PIN on this device.'
                  : 'Turn on to sign in with the PIN you already have.',
              onTap: null,
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
                  ? 'Enabled — your fingerprint signs you in on this device.'
                  : 'Enable to sign in with your fingerprint instead of typing your PIN.',
              onTap: null,
            ),
            // Deliberately the LAST row of this section, under both sign-in
            // toggles. It is the only destructive control on the screen, and
            // a red row sitting directly above the two switches people
            // actually come here to flip is a mis-tap waiting to happen.
            _SettingsTile(
              icon: Icons.no_accounts_outlined,
              title: 'Switch Off Or Delete Account',
              subtitle: 'Both are reversible — switching off keeps everything, '
                  'and a deletion can be stopped for 90 days.',
              titleColor: ManaColors.statusBad,
              onTap: () => context.push('/account-closure'),
            ),
            // Shown to an Owner, and to anyone who actually has an offer
            // waiting. It used to be shown to everybody, on the reasoning that
            // someone with no business of their own still needs somewhere to
            // accept one — true, but it put the heaviest action in the app in
            // front of every Agent, Customer and Investor permanently, to
            // cover a case that is rare and self-announcing. An incoming offer
            // brings the row with it.
            if (_showsBusinessTransfer) ...[
              const SizedBox(height: ManaSpacing.lg),
              const _SectionHeader('business transfer'),
              _SettingsTile(
                icon: Icons.swap_horizontal_circle_outlined,
                title: 'Business Transfer',
                subtitle: _isOwner
                    ? 'Hand a business over, or accept one offered to you.'
                    : 'A business has been offered to you.',
                onTap: () =>
                    context.push('/business-transfer', extra: widget.businessId),
              ),
            ],
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('share app'),
            // One system share sheet rather than five per-app buttons.
            // WhatsApp, Telegram, Facebook, Instagram and email all appear in
            // it, and it shows whichever the person actually has installed —
            // where hardcoded buttons would offer apps they do not have and
            // miss the one they use. Per-app deep links also break whenever
            // those apps change their URL schemes.
            _SettingsTile(
              icon: Icons.share_outlined,
              title: 'Share App',
              subtitle: 'Tell someone about MANA LINE.',
              onTap: _shareApp,
            ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('appearance'),
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: 'Light, dark and text size.',
              onTap: () => context.push('/appearance'),
            ),
            const SizedBox(height: ManaSpacing.lg),
            const _SectionHeader('languages'),
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
            const _SectionHeader('about'),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About MANA LINE',
              subtitle: 'What this app does, and the terms you agreed to.',
              trailing: const ManaText.raw(_versionLabel),
              onTap: () => context.push('/about'),
            ),
            const SizedBox(height: ManaSpacing.lg),
            _SettingsTile(
              icon: Icons.logout,
              title: 'Logout',
              titleColor: ManaColors.statusBad,
              onTap: () {
                ref.read(authFlowProvider.notifier).reset();
                context.go('/lr-009');
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
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ManaColors.textSecondary,
            letterSpacing: 1),
      );
}

/// Trailing marker for a row whose feature is scheduled but not built.
///
/// A plain label rather than a chip or a badge: it has to read as a status,
/// not as something else to tap.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon();

  @override
  Widget build(BuildContext context) => ManaText(
        'coming soon',
        style: ManaType.note,
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
          ? ManaText.raw(subtitle!, style: ManaType.small)
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
  final String title;
  final String label;
  const _PinVerifyDialog({
    this.title = 'confirm your pin',
    this.label = 'Enter PIN',
  });
  @override
  State<_PinVerifyDialog> createState() => _PinVerifyDialogState();
}

class _PinVerifyDialogState extends State<_PinVerifyDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: ManaText(widget.title),
      content: TextField(
        controller: _controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
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
