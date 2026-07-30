import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';
import '../../../shared/login_nav_args.dart';
import '../../../shared/widgets/language_selector.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import 'lr_005_otp_verification.dart';

/// LR-009 — fast re-authentication for a returning person on an
/// already-trusted device. PIN pad is primary (F1); biometric (F2)
/// auto-triggers on load if enabled, but never replaces PIN as
/// fallback (BR-196). 3rd consecutive wrong PIN steps down to LR-007
/// in password-required mode (BR-201, S4) — not Forgot Password.
///
/// ADDED this batch: a successful login here also checks
/// needs_pin_upgrade — if the person's PIN is still 4 digits (or
/// predates the pin_length column), they're routed through LR-008 in
/// upgrade mode before reaching their workspace, instead of straight to
/// LR-012.
class DailyLoginScreen extends ConsumerStatefulWidget {
  const DailyLoginScreen({super.key});

  @override
  ConsumerState<DailyLoginScreen> createState() => _DailyLoginScreenState();
}

class _DailyLoginScreenState extends ConsumerState<DailyLoginScreen> {
  int? _pinLength; // remembered locally from LR-008, per F1
  String _entered = '';
  int _wrongAttempts = 0;
  bool _submitting = false;
  bool _biometricAttempted = false;
  String? _error;
  final String _personName =
      ''; // TODO: real profile fetch for header personalization

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final length = await LocalAuthStore.readPinLength();
    if (!mounted) return;

    if (length == null) {
      // Prerequisite condition failed (per LR-009 ENTRY POINT: no
      // pin_hash on this device) — not this screen's concern, route
      // back to the fresh-device flow.
      context.go('/lr-001');
      return;
    }

    setState(() => _pinLength = length);
    _maybeTriggerBiometric();
  }

  Future<void> _maybeTriggerBiometric() async {
    if (_biometricAttempted) return;
    final enabled = await LocalAuthStore.readBiometricEnabled();
    if (!enabled || !mounted) return;
    _biometricAttempted = true;

    // TODO: real native biometric prompt (local_auth package).
    // On success → _submitWithStoredPin(). On failure/cancel → S5:
    // silently fall back to PIN pad, no error, no counter increment.
    // Stub: does nothing automatically here so the PIN pad remains the
    // testable path in this scaffold; wire local_auth in a follow-up.
  }

  void _onDigit(String d) {
    if (_pinLength == null || _entered.length >= _pinLength!) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == _pinLength)
      _submit(); // auto-submit on last digit, per F1
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);

    final deviceFingerprint = await LocalAuthStore.deviceFingerprint();
    final mobile = await LocalAuthStore.readLastMobileNumber();

    if (mobile == null) {
      // Defensive — LR-009's own entry condition requires a remembered
      // device, which implies a remembered mobile number from a prior
      // LR-007 login. Shouldn't be reachable without one.
      setState(() => _submitting = false);
      context.go('/lr-001');
      return;
    }

    // Real POST /auth/login { identifier: mobile, credential: pin,
    // device_fingerprint } — same endpoint as LR-007. PIN correctness is
    // validated server-side inside that call (against persons.pin_hash),
    // NOT by comparing _entered to a plaintext copy read back out of
    // flutter_secure_storage — that on-device comparison only proves "same
    // device", not "human just proved they know the PIN" to anything a
    // server can trust, and is exactly the bug fixed by this session (see
    // auth_api_service.dart's architectural note #4). The device-local PIN
    // copy (LocalAuthStore.readPinValue) is now used ONLY by the separate
    // biometric-unlock convenience path, never as this screen's own
    // success signal.
    LoginResult? result;
    AccountLockedException? locked;
    final reached = await NetworkErrorHandler.run(context, () async {
      try {
        result = await ref.read(authApiServiceProvider).login(
              identifier: mobile,
              credential: _entered,
              credentialType: 'pin',
              deviceFingerprint: deviceFingerprint,
            );
      } on AccountLockedException catch (e) {
        // BUG FIXED this pass: this local _wrongAttempts counter usually
        // steps down to LR-007 before the server's own failed_pin_attempts
        // cap is reached, but the two can drift (e.g. a fresh app install
        // resets this counter to 0 while the server-side one persisted) —
        // defensively routing to the OTP-unlock flow here too rather than
        // just showing "Incorrect PIN" for an account that's actually locked.
        locked = e;
      }
      return true;
    });

    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown, PIN dots untouched
    }

    if (locked != null) {
      if (locked!.personId == null) {
        setState(() {
          _submitting = false;
          _error = locked!.message;
        });
        return;
      }
      final otpId = await NetworkErrorHandler.run(context, () async {
        return ref.read(authApiServiceProvider).sendOtp(personId: locked!.personId!, purpose: 'Account Unlock');
      });
      if (!mounted) return;
      setState(() => _submitting = false);
      if (otpId == null) return; // network failure — SnackBar already shown
      ref.read(authFlowProvider.notifier).setPendingOtpId(otpId);
      context.push('/lr-005', extra: const OtpEntryArgs(purpose: OtpPurpose.accountUnlock));
      return;
    }

    final success = result != null &&
        result!.success &&
        result!.token != null &&
        result!.personId != null;

    if (success) {
      await ref.read(authFlowProvider.notifier).setLoginResult(
            personId: result!.personId!,
            token: result!.token!,
            pinExists: true,
          );
      if (!mounted) return;

      final memberships = await NetworkErrorHandler.run(
        context,
        () => ref
            .read(authApiServiceProvider)
            .fetchMemberships(ref.read(authFlowProvider).personId!),
      );
      if (!mounted) return;
      if (memberships == null) {
        setState(() => _submitting = false);
        return; // network failure — SnackBar already shown
      }
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
      if (result!.needsPinUpgrade) {
        context.go('/lr-008', extra: true);
      } else {
        context.go('/lr-012');
      }
      return;
    }

    // S3 — wrong PIN
    _wrongAttempts++;
    if (_wrongAttempts >= 3) {
      // S4 / BR-201 — step down to LR-007, password required, NOT
      // Forgot Password. Local PIN material is cleared inside LR-007
      // once the password login actually succeeds (see that screen's
      // diff), not here — a 3rd wrong attempt alone doesn't erase the
      // PIN, only a confirmed successful password re-auth does.
      context.go('/lr-007',
          extra: const LoginStepDownArgs(stepDownFromFailedPin: true));
      return;
    }

    setState(() {
      _submitting = false;
      _entered = '';
      _error = 'Incorrect PIN';
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final lang = ref.watch(authFlowProvider).language;

    if (_pinLength == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: ManaSpacing.xl),
              const ManaVerificationRing(isVerified: true, size: 64),
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                _personName.isEmpty
                    ? 'Welcome back'
                    : 'Welcome back, $_personName',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength!, (i) {
                  final filled = i < _entered.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          filled ? ManaColors.brass : ManaColors.surfaceSunken,
                    ),
                  );
                }),
              ),
              if (_error != null) ...[
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(_error!,
                    style: const TextStyle(color: ManaColors.statusBad)),
              ],
              const SizedBox(height: ManaSpacing.xl),
              _numberPad(),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.push(
                      '/lr-007',
                      extra: const LoginStepDownArgs(
                          redirectAfterSuccess: '/lr-011'),
                    ),
                    child: ManaText.raw(ref.t('forgot_pin')),
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  TextButton(
                    onPressed: () => context.push('/lr-007'),
                    child: ManaText.raw(ref.t('login_with_password')),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.sm),
              ManaLanguageSelector(
                current: lang,
                onChanged: (l) =>
                    ref.read(authFlowProvider.notifier).setLanguage(l),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((d) {
                  if (d.isEmpty) return const SizedBox(width: 72, height: 56);
                  return SizedBox(
                    width: 72,
                    height: 56,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => d == '⌫' ? _onBackspace() : _onDigit(d),
                      child: Text(d, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ))
          .toList(),
    );
  }
}
