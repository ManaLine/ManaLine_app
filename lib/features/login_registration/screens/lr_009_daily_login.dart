import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_brand_mark.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';
import '../../../shared/mana_biometric.dart';
import '../../../shared/login_nav_args.dart';
import '../../../shared/widgets/language_selector.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import 'lr_005_otp_verification.dart';
import 'lr_007_first_login.dart';

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
///
/// MERGED this batch: this screen now hosts BOTH credentials. PIN and
/// password answer the same question — "is this you?" — so making them
/// two destinations meant a person who could not remember one had to
/// navigate to reach the other, on the screen where they are least able
/// to. There is now one screen and a switch. `/lr-007` still resolves and
/// still carries every argument it always did; it simply opens this
/// screen already switched to password, so the locked screen IDs, the
/// BR-201 step-down and every existing push keep working unchanged.
class DailyLoginScreen extends ConsumerStatefulWidget {
  /// True when opened as `/lr-007` — start on the password form.
  final bool startInPasswordMode;

  /// Passed straight through to the password form. See [FirstLoginScreen].
  final bool stepDownFromFailedPin;
  final String? prefilledMobile;
  final String? successToast;
  final String? redirectAfterSuccess;

  const DailyLoginScreen({
    super.key,
    this.startInPasswordMode = false,
    this.stepDownFromFailedPin = false,
    this.prefilledMobile,
    this.successToast,
    this.redirectAfterSuccess,
  });

  @override
  ConsumerState<DailyLoginScreen> createState() => _DailyLoginScreenState();
}

class _DailyLoginScreenState extends ConsumerState<DailyLoginScreen> {
  /// Which credential is on screen. Starts from the route, then follows
  /// the switch — no navigation, so nothing is pushed and Back never
  /// walks backwards through credential types.
  late bool _passwordMode = widget.startInPasswordMode;

  /// Set when the 3rd wrong PIN forced the switch to password (BR-201).
  /// Kept separate from the constructor argument because the step-down can
  /// now happen without any navigation.
  bool _stepDown = false;
  int? _pinLength; // remembered locally from LR-008, per F1
  String _entered = '';
  int _wrongAttempts = 0;
  bool _submitting = false;
  bool _biometricAttempted = false;
  String? _error;
  // No name here, deliberately. This header used to hold an always-empty
  // _personName awaiting "a real profile fetch". LR-009 is the lock screen —
  // it is what someone holding the unlocked handset of a person who is not
  // them sees first, before any credential. Greeting them by that person's
  // name confirms whose phone they are holding, and buys the person being
  // greeted nothing they do not already know.

  /// The PIN is typed on the handset's own numeric keyboard now, not on a
  /// drawn keypad. This controller is the real input; the dots below are
  /// only a rendering of its length. The field itself is offstage — see
  /// _hiddenPinField — so the dots remain the thing the person looks at.
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocus = FocusNode();

  /// Set when a submit failed because the network was unreachable, and the
  /// entered PIN is still complete. While it is running the screen retries
  /// on its own, so coming back into signal signs the person in without
  /// them having to delete and retype the last digit.
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _pinController.addListener(_onPinChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _pinController.removeListener(_onPinChanged);
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final length = await LocalAuthStore.readPinLength();
    if (!mounted) return;

    if (length == null) {
      // No PIN on this device. That used to be an impossible state here,
      // so it bounced to LR-001; now that this screen is also `/lr-007`,
      // it is the ordinary case for anyone logging in for the first time.
      // Fall back to the password form rather than bouncing — bouncing
      // would send a first-time user in a circle.
      setState(() => _passwordMode = true);
      return;
    }

    setState(() => _pinLength = length);
    if (!_passwordMode) _maybeTriggerBiometric();
  }

  Future<void> _maybeTriggerBiometric() async {
    if (_biometricAttempted) return;
    final enabled = await LocalAuthStore.readBiometricEnabled();
    if (!enabled || !mounted) return;
    _biometricAttempted = true;

    // A real fingerprint is now required before the stored PIN is used.
    //
    // WHAT THIS REPLACES: the toggle used to store a flag and this method did
    // nothing, while "biometric unlock" elsewhere simply submitted the saved
    // PIN. Anyone holding an unlocked handset could sign in, because the only
    // thing being proved was that a PIN had once been saved on this device.
    //
    // Only 'ok' proceeds. Every other outcome falls through to the PIN pad in
    // silence — per S5, no error, no counter increment. A cancelled prompt is
    // a person choosing to type instead, not a failed login, and showing them
    // a red message for it would be wrong.
    if (!await ManaBiometric.isAvailable()) return;
    final result = await ManaBiometric.authenticate(
      reason: 'Confirm it is you to open MANA LINE',
    );
    if (!mounted || result != ManaBiometricResult.ok) return;

    await _submitWithStoredPin();
  }

  /// The convenience path behind a successful fingerprint.
  ///
  /// The stored PIN is still sent to the server and still validated against
  /// persons.pin_hash — biometrics decide whether this device may REPLAY the
  /// saved PIN, they never stand in for the server's own check. That is the
  /// same reasoning as _submit's note below: an on-device comparison proves
  /// "same device", not "the right person".
  Future<void> _submitWithStoredPin() async {
    final stored = await LocalAuthStore.readPinValue();
    if (stored == null || stored.isEmpty || !mounted) return;
    // Through the controller, so the dots and the value stay one source of
    // truth. The listener's auto-submit then fires this off.
    _pinController.text = stored;
  }

  /// Mirrors the field into [_entered] and auto-submits on the last digit
  /// (per F1). Typing anything also cancels a pending auto-retry — the
  /// person has taken over, and firing a stale submit underneath them
  /// would race their new input.
  void _onPinChanged() {
    if (_pinLength == null) return;
    final digits = _pinController.text;
    if (digits == _entered) return;

    _retryTimer?.cancel();
    setState(() {
      _entered = digits;
      if (digits.isNotEmpty) _error = null;
    });
    if (digits.length == _pinLength && !_submitting) {
      _submit();
    }
  }

  /// The real input, laid directly over the dots and painted in nothing.
  ///
  /// NOT Offstage and NOT a zero-size box: an offstage subtree cannot take
  /// focus, so the keyboard would never open, and a zero-size field is
  /// skipped by hit testing. Keeping it full-size over the dots means a tap
  /// on the dots IS a tap on the field — no separate gesture plumbing to
  /// re-open a dismissed keyboard.
  ///
  /// readOnly rather than enabled:false while submitting — disabling drops
  /// focus and closes the keyboard, which on a failed attempt would leave
  /// the person staring at a screen with no way to type.
  Widget _pinField() {
    return TextField(
      controller: _pinController,
      focusNode: _pinFocus,
      autofocus: true,
      readOnly: _submitting,
      keyboardType: TextInputType.number,
      obscureText: true,
      maxLength: _pinLength,
      textAlign: TextAlign.center,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      // Never offer to save or autofill a PIN, and keep it out of the
      // keyboard's learned-words store.
      autofillHints: const [],
      enableSuggestions: false,
      autocorrect: false,
      showCursor: false,
      cursorColor: Colors.transparent,
      style: const TextStyle(color: Colors.transparent, fontSize: 1),
      // collapsed(), not a hand-cleared InputDecoration: collapsed is the
      // one that also drops the 48px minimum tap-target height and the
      // counter, which is what made the field impossible to hide cleanly.
      decoration: const InputDecoration.collapsed(hintText: ''),
      onSubmitted: (_) {
        if (_entered.length == _pinLength && !_submitting) _submit();
      },
    );
  }

  /// The dots, with the real (invisible) field behind them.
  ///
  /// BUG FIXED: the field used to be a `Positioned.fill` layered OVER a
  /// Stack whose only other child was the 16px-tall dots Row. Positioned.
  /// fill forces its child to exactly the Stack's size, so a TextField —
  /// which will not render below its own minimum height — was crushed into
  /// 16px and painted a clipped band straight across the dots.
  ///
  /// Fixed by sizing the Stack explicitly and putting the field UNDER the
  /// dots rather than over them, with the dots made hit-transparent so a
  /// tap still lands on the field and still opens the keyboard.
  Widget _pinDots() {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: _pinField()),
          IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pinLength!, (i) {
                final filled = i < _entered.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? ManaColors.brand : ManaColors.surfaceSunken,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    _retryTimer?.cancel();
    setState(() => _submitting = true);

    final deviceFingerprint = await LocalAuthStore.deviceFingerprint();
    if (!mounted) return;
    final mobile = await LocalAuthStore.readLastMobileNumber();
    if (!mounted) return;

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
      // Network failure. The dots stay filled AND the screen now retries on
      // its own every few seconds.
      //
      // WHY: the PIN only submits on the transition to a full length, so
      // once a submit failed there was no event left to fire — the entry
      // was complete and nothing would ever resend it. Recovering meant
      // deleting the last digit and retyping it, which reads as the app
      // being broken rather than the signal being out. The retry is silent
      // and stops the moment the person touches the field.
      setState(() => _submitting = false);
      _scheduleRetry();
      return;
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
      // Forgot Password. Local PIN material is cleared inside the password
      // form once that login actually succeeds, not here — a 3rd wrong
      // attempt alone doesn't erase the PIN, only a confirmed successful
      // password re-auth does.
      //
      // Now a switch rather than a `go`: the password form lives on this
      // same screen, so there is nothing to navigate to. `_stepDown` makes
      // it show the same "Enter your password to continue" banner the
      // routed version showed.
      setState(() {
        _submitting = false;
        _stepDown = true;
        _passwordMode = true;
        _error = null;
      });
      _pinController.clear();
      return;
    }

    setState(() {
      _submitting = false;
      _error = 'Incorrect PIN';
    });
    // Clearing through the controller, not _entered directly — the listener
    // is what keeps the two in step, and setting _entered alone would leave
    // the field holding a full PIN with empty-looking dots.
    _pinController.clear();
    _pinFocus.requestFocus();
  }

  /// Re-attempts a completed-but-unsent PIN until it goes through.
  ///
  /// A fixed 3s poll rather than a connectivity listener: "the OS says
  /// Wi-Fi is up" is not the same as "the server answered", and this
  /// screen's failure mode covers both — a captive portal at a tea shop
  /// looks connected and is not. Retrying the request itself is the only
  /// check that tests what actually matters.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (_entered.length != _pinLength) return;
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _submitting) return;
      if (_entered.length != _pinLength) return;
      _submit();
    });
  }

  /// Back, from either the AppBar arrow or the handset's own Back key.
  ///
  /// Login is the root of the app: there is nothing above it to return to,
  /// so Back used to close the app outright on the first press. That reads
  /// as a crash. It now confirms first — but only when this really is the
  /// root. When the screen was pushed (e.g. "Forgot PIN?" verifying a
  /// password first) there is a real destination underneath and Back pops
  /// to it, as it should.
  Future<void> _handleBack() async {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText('exit app'),
        content: const ManaText('are you sure you want to close mana line?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const ManaText('cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const ManaText('exit'),
          ),
        ],
      ),
    );
    if (leave == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final lang = ref.watch(authFlowProvider).language;

    // Only the PIN pane needs the stored length. In password mode the
    // screen is usable immediately, so gating on it would show a spinner
    // to someone who has no PIN at all.
    if (_pinLength == null && !_passwordMode) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      // canPop false so the handset Back key reaches _handleBack instead of
      // closing the app under us; _handleBack does the popping itself when
      // popping is the right answer.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: _scaffold(lang),
    );
  }

  Widget _scaffold(ManaLanguage lang) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _handleBack),
      ),
      body: SafeArea(
        // Scrollable, and the Column sizes to its content instead of using
        // Spacer to push the footer down.
        //
        // WHY: this was a fixed-height Column with a Spacer, which cannot
        // absorb growth. Switching the language to Kannada made the footer
        // labels materially longer ("Login with Password" -> "ಪಾಸ್‌ವರ್ಡ್‌ನೊಂದಿಗೆ
        // ಲಾಗಿನ್"), and the same is true at larger system font sizes — the
        // Spacer's flex space went negative and the layout overflowed. A login
        // screen must be reachable in every language on every device, so it
        // scrolls rather than trying to fit.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: ManaSpacing.lg),
              // Logo, name and tagline sit above the avatar: on the first
              // screen after choosing a workspace, the app has to say what it
              // is before it says who you are.
              const ManaBrandMark(logoSize: 52),
              const SizedBox(height: ManaSpacing.lg),
              const ManaVerificationRing(isVerified: true, size: 64),
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                ref.t('welcome_back'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: ManaSpacing.xl),
              if (_passwordMode)
                FirstLoginScreen(
                  embedded: true,
                  stepDownFromFailedPin: _stepDown || widget.stepDownFromFailedPin,
                  prefilledMobile: widget.prefilledMobile,
                  successToast: widget.successToast,
                  redirectAfterSuccess: widget.redirectAfterSuccess,
                )
              else ...[
                _pinDots(),
                if (_error != null) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  ManaText.raw(_error!,
                      style: ManaType.bad),
                ],
                if (_submitting) ...[
                  const SizedBox(height: ManaSpacing.lg),
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
              const SizedBox(height: ManaSpacing.lg),
              // The switch between the two credentials. Offered only when a
              // PIN actually exists on this device — otherwise "Use PIN"
              // would lead to a pane with nothing to type into.
              if (_pinLength != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _passwordMode = !_passwordMode;
                    _error = null;
                    if (!_passwordMode) _pinController.clear();
                  }),
                  icon: Icon(_passwordMode ? Icons.pin_outlined : Icons.password_outlined),
                  label: ManaText.raw(
                    _passwordMode ? ref.t('login_with_pin') : ref.t('login_with_password'),
                  ),
                ),
              const SizedBox(height: ManaSpacing.md),
              // Wrap, not Row: these labels come from ui_translations, so their
              // width is data, not a constant. Two unconstrained TextButtons in
              // a Row overflowed as soon as the language changed to Kannada.
              // Wrap reflows to as many lines as the longest translation needs.
              //
              // "Login with Password" and "Register" used to sit here too.
              // The first is now the AppBar's back arrow, and the second is
              // reachable from LR-007 once you're there.
              //
              // Forgot PIN and Change User are hidden in PASSWORD mode. In PIN
              // mode they are the only ways out of a PIN you cannot recall or
              // a device remembering the wrong person. On the password form
              // neither applies: there is no PIN being asked for, and you
              // switch person simply by typing a different mobile number —
              // which is exactly why they read as clutter there.
              if (!_passwordMode)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: ManaSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => context.push(
                      '/lr-007',
                      extra: const LoginStepDownArgs(
                          redirectAfterSuccess: '/lr-011'),
                    ),
                    child: ManaText.raw(ref.t('forgot_pin')),
                  ),
                  TextButton(
                    onPressed: () async {
                      // Clear the remembered identity before leaving, or the
                      // next screen would still be scoped to the old person.
                      //
                      // The stored PIN goes too, and that is the actual fix:
                      // clearing only the session left this device's PIN in
                      // place, so the very next screen was a PIN pad for the
                      // person being switched AWAY from. Someone else picking
                      // up the phone had no way through. With no PIN on the
                      // device the merged screen opens on the password form,
                      // which is the only credential a different person has.
                      await LocalAuthStore.clearPin();
                      await LocalAuthStore.clearLastMobileNumber();
                      if (!mounted) return;
                      ref.read(authFlowProvider.notifier).reset();
                      context.go('/lr-007');
                    },
                    child: ManaText.raw(ref.t('change_user')),
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

}
