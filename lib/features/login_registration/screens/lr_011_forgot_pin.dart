import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';
import '../../../shared/network_error_handler.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/translation_service.dart';

enum _Step { password, otp, newPin }

/// LR-011 — internal-step screen. Deliberate double-gate (password THEN
/// OTP) before allowing a PIN reset — stronger verification for a
/// daily-use credential, per spec's explicit "not an inconsistency to
/// simplify away" note. Password mismatch here does NOT count toward
/// BR-201's 5x login-lockout counter (that counter is scoped to
/// LR-007/LR-009 only).
class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  _Step _step = _Step.password;
  final _password = TextEditingController();
  String? _otpId;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  // --- OTP step state (same pattern as LR-005/LR-010; not yet
  // extracted to a shared widget — see hand-off note) ---
  final List<TextEditingController> _otpDigits = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());
  String get _otpCode => _otpDigits.map((c) => c.text).join();
  int _otpResendCount = 0;
  String? _otpError;

  // --- New PIN step state (same pattern as LR-008 F1/F2) ---
  int _pinLength = 4;
  String _pin = '';
  String _confirmPin = '';
  bool _confirmingPin = false;

  Future<void> _verifyPassword() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _submitting = true;
      _passwordError = null;
    });

    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      setState(() {
        _submitting = false;
        _passwordError = 'Session expired. Please log in again.';
      });
      return;
    }

    // No lockout-counter impact here (BR-201's counter is login-scoped
    // only, per spec). On success, the server sends the OTP automatically
    // (purpose='PIN Reset') as part of this same call — single combined
    // action, no extra tap between password and OTP. A wrong password is
    // a normal (non-exceptional) business-logic outcome here — the Edge
    // Function is expected to signal it via a 401/403 FunctionException
    // rather than a 200, which we treat as "incorrect password" below
    // rather than a generic connectivity failure.
    String? otpId;
    String? failureReason;
    final reached = await NetworkErrorHandler.run(context, () async {
      try {
        otpId = await ref.read(authApiServiceProvider).pinResetRequest(
              personId: personId,
              password: _password.text,
            );
      } on FunctionException catch (e) {
        if (e.status == 401 || e.status == 403) {
          failureReason = 'Incorrect password.';
          return true; // reached the server — not a network failure
        }
        rethrow;
      }
      return true;
    });
    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    if (failureReason != null) {
      setState(() {
        _submitting = false;
        _passwordError = failureReason;
      });
      return;
    }

    setState(() {
      _submitting = false;
      _otpId = otpId;
      _step = _Step.otp;
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) return;
    setState(() => _submitting = true);

    if (_otpId == null) {
      setState(() {
        _submitting = false;
        _otpError = 'Session expired. Please start over.';
      });
      return;
    }

    bool? verified;
    final reached = await NetworkErrorHandler.run(context, () async {
      verified = await ref.read(authApiServiceProvider).verifyOtp(otpId: _otpId!, code: _otpCode);
      return true;
    });
    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    if (verified != true) {
      setState(() {
        _submitting = false;
        _otpError = 'Incorrect code. Please try again.';
        for (final c in _otpDigits) {
          c.clear();
        }
      });
      _otpNodes.first.requestFocus();
      return;
    }

    setState(() {
      _submitting = false;
      _step = _Step.newPin;
    });
  }

  Future<void> _resendOtp() async {
    if (_otpResendCount >= 5) return;
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) return; // defensive

    // Re-sends via the same password-gated request call — matches
    // pinResetRequest's "server sends OTP automatically" contract; there
    // is deliberately no separate bare-resend endpoint for this
    // double-gated flow (password already re-verified once per screen
    // load, no reason to ask again just to resend a code).
    final newOtpId = await NetworkErrorHandler.run(
      context,
      () => ref.read(authApiServiceProvider).sendOtp(personId: personId, purpose: 'PIN Reset'),
    );
    if (!mounted || newOtpId == null) return; // network failure — SnackBar already shown
    setState(() {
      _otpId = newOtpId;
      _otpResendCount++;
      _otpError = null;
    });
  }

  void _onPinDigit(String d) {
    setState(() {
      if (!_confirmingPin) {
        if (_pin.length < _pinLength) _pin += d;
        if (_pin.length == _pinLength) _confirmingPin = true;
      } else {
        if (_confirmPin.length < _pinLength) _confirmPin += d;
        if (_confirmPin.length == _pinLength) _checkPinMatch();
      }
    });
  }

  void _checkPinMatch() {
    if (_pin == _confirmPin) {
      _savePin();
    } else {
      setState(() {
        _pin = '';
        _confirmPin = '';
        _confirmingPin = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PINs don\'t match')));
    }
  }

  Future<void> _savePin() async {
    setState(() => _submitting = true);

    if (_otpId == null) {
      setState(() => _submitting = false);
      return;
    }

    final result = await NetworkErrorHandler.run(context, () async {
      await ref.read(authApiServiceProvider).pinResetConfirm(
            otpId: _otpId!,
            code: _otpCode,
            newPin: _pin,
          );
      return true;
    });
    if (!mounted) return;
    if (result == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    // Does NOT re-prompt for biometric (spec, LR-011 STEP 3) —
    // biometric_enabled stays whatever it already was; only the stored
    // PIN value itself is refreshed to the new one.
    final wasBiometricEnabled = await LocalAuthStore.readBiometricEnabled();
    await LocalAuthStore.savePin(pin: _pin, biometricEnabled: wasBiometricEnabled);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN updated')));
    context.go('/lr-012'); // NOT LR-007 — this flow already re-proved password itself
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('forgot_pin_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: switch (_step) {
            _Step.password => _passwordStep(),
            _Step.otp => _otpStep(),
            _Step.newPin => _newPinStep(),
          },
        ),
      ),
    );
  }

  Widget _passwordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        const ManaText.raw('Re-enter your password to continue.'),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _password,
          obscureText: _obscurePassword,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Password *',
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        if (_passwordError != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_passwordError!, style: TextStyle(color: ManaColors.statusBad)),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_password.text.isNotEmpty && !_submitting) ? _verifyPassword : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('verify_password')),
        ),
      ],
    );
  }

  Widget _otpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        const ManaText.raw('Enter the OTP sent to verify this is you.', textAlign: TextAlign.center),
        const SizedBox(height: ManaSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, _otpDigitBox),
        ),
        if (_otpError != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(_otpError!, style: TextStyle(color: ManaColors.statusBad),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: ManaSpacing.lg),
        Center(
          child: TextButton(
            onPressed: _otpResendCount < 5 ? _resendOtp : null,
            child: ManaText(_otpResendCount >= 5 ? 'maximum resend attempts reached' : 'resend otp'),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_otpCode.length == 6 && !_submitting) ? _verifyOtp : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('verify')),
        ),
      ],
    );
  }

  Widget _otpDigitBox(int i) {
    return SizedBox(
      width: 44,
      child: TextField(
        controller: _otpDigits[i],
        focusNode: _otpNodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        decoration: const InputDecoration(counterText: ''),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _otpNodes[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _otpNodes[i - 1].requestFocus();
          if (i == 5 && v.isNotEmpty) _verifyOtp();
          setState(() {});
        },
      ),
    );
  }

  Widget _newPinStep() {
    final label = !_confirmingPin ? 'Create a new PIN' : 'Confirm your new PIN';
    final activeCount = !_confirmingPin ? _pin.length : _confirmPin.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ManaText.raw(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pinLength, (i) {
            final filled = i < activeCount;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? ManaColors.brand : ManaColors.surfaceSunken,
              ),
            );
          }),
        ),
        if (!_confirmingPin) ...[
          const SizedBox(height: ManaSpacing.md),
          TextButton(
            onPressed: () => setState(() => _pinLength = _pinLength == 4 ? 6 : 4),
            child: ManaText.raw(ref.t('use_other_pin_length').replaceAll('{digits}', '${_pinLength == 4 ? 6 : 4}')),
          ),
        ],
        const SizedBox(height: ManaSpacing.xl),
        _numberPad(),
      ],
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
                    width: 72, height: 56,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              if (d == '⌫') {
                                setState(() {
                                  if (!_confirmingPin && _pin.isNotEmpty) {
                                    _pin = _pin.substring(0, _pin.length - 1);
                                  } else if (_confirmingPin && _confirmPin.isNotEmpty) {
                                    _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
                                  }
                                });
                              } else {
                                _onPinDigit(d);
                              }
                            },
                      child: Text(d, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ))
          .toList(),
    );
  }
}
