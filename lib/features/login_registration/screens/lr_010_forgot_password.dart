import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/login_nav_args.dart';
import '../../../shared/network_error_handler.dart';
import '../state/auth_api_service.dart';

enum _Step { mobile, otp, newPassword }

/// LR-010 — internal-step screen (not separate route IDs, per spec).
/// OTP-only recovery, available to any role, no higher-privilege
/// dependency (BR-201/BR-195 amendment). Never reveals whether the
/// mobile number is registered — same generic message either way (F1).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _authApi = AuthApiService();
  String? _otpId;
  _Step _step = _Step.mobile;
  final _mobile = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _genericSentMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
  }

  // --- OTP step state (mirrors LR-005's pattern; not extracted to a
  // shared widget yet — see hand-off note at the end of this turn) ---
  final List<TextEditingController> _otpDigits = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());
  String get _otpCode => _otpDigits.map((c) => c.text).join();
  int _otpResendCount = 0;
  String? _otpError;

  bool get _passwordValid => _newPassword.text.length >= 8;
  bool get _confirmValid => _confirmPassword.text == _newPassword.text && _confirmPassword.text.isNotEmpty;

  Future<void> _sendOtp() async {
    if (_mobile.text.length != 10) return;
    setState(() => _submitting = true);

    // F1/S2 — CONFIRMED locked behavior: identical message regardless of
    // whether the number is registered. This client can only preserve
    // that property if `auth-password-reset-request` ALWAYS returns
    // HTTP 200 with a (possibly dummy/no-op) otp_id — never a 404/422 for
    // "no such mobile number" — otherwise NetworkErrorHandler's generic
    // error path would visibly diverge from the success path right here.
    // Flagged as a hard requirement on that Edge Function's contract, not
    // just a client-side nicety.
    final otpId = await NetworkErrorHandler.run(
      context,
      () => _authApi.passwordResetRequest(identifier: _mobile.text),
    );
    if (!mounted) return;
    if (otpId == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    setState(() {
      _submitting = false;
      _otpId = otpId;
      _genericSentMessage = 'If this number is registered, an OTP has been sent.';
      _step = _Step.otp;
    });
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) return;
    setState(() => _submitting = true);

    if (_otpId == null) {
      setState(() {
        _submitting = false;
        _otpError = 'Session expired. Please request a new code.';
      });
      return;
    }

    bool? verified;
    final reached = await NetworkErrorHandler.run(context, () async {
      verified = await _authApi.verifyOtp(otpId: _otpId!, code: _otpCode);
      return true;
    });
    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    final success = verified == true;
    if (!success) {
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
      _step = _Step.newPassword;
    });
  }

  Future<void> _resendOtp() async {
    if (_otpResendCount >= 5) return;
    // Resend re-runs the same reset-request call, which per the Edge
    // Function contract above always succeeds (200 + otp_id) regardless of
    // whether the number is registered — reusing it here keeps this
    // screen's confidentiality property intact without a separate
    // "resend" endpoint.
    final otpId = await NetworkErrorHandler.run(
      context,
      () => _authApi.passwordResetRequest(identifier: _mobile.text),
    );
    if (!mounted || otpId == null) return; // network failure — SnackBar already shown
    setState(() {
      _otpId = otpId;
      _otpResendCount++;
      _otpError = null;
    });
  }

  Future<void> _resetPassword() async {
    if (!_passwordValid || !_confirmValid) return;
    setState(() => _submitting = true);

    if (_otpId == null) {
      setState(() => _submitting = false);
      return;
    }

    // On success: persons.password_hash updated, failed_password_attempts
    // reset to 0. pin_hash/biometric_enabled/devices UNCHANGED — this
    // flow never touches PIN state, per spec's own NAVIGATION note.
    final result = await NetworkErrorHandler.run(context, () async {
      await _authApi.passwordResetConfirm(
        otpId: _otpId!,
        code: _otpCode,
        newPassword: _newPassword.text,
      );
      return true;
    });
    if (!mounted) return;
    if (result == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    context.go(
      '/lr-007',
      extra: LoginStepDownArgs(
        prefilledMobile: _mobile.text,
        successToast: 'Password updated — please log in',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/lr-007')),
        title: ManaText.raw(ref.t('forgot_password')),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: switch (_step) {
            _Step.mobile => _mobileStep(),
            _Step.otp => _otpStep(),
            _Step.newPassword => _newPasswordStep(),
          },
        ),
      ),
    );
  }

  Widget _mobileStep() {
    final canSend = _mobile.text.length == 10 && !_submitting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        ManaText.raw(
          ref.t('forgot_password_note'),
        ),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: ref.t('mobile_number_required_field')),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: canSend ? _sendOtp : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('send_otp')),
        ),
      ],
    );
  }

  Widget _otpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        if (_genericSentMessage != null)
          ManaText.raw(_genericSentMessage!, textAlign: TextAlign.center),
        const SizedBox(height: ManaSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, _otpDigitBox),
        ),
        if (_otpError != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(_otpError!, style: ManaType.bad,
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

  Widget _newPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        TextField(
          controller: _newPassword,
          obscureText: _obscureNew,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: ref.t('new_password_field'),
            helperText: ref.t('password_helper'),
            suffixIcon: IconButton(
              icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureNew = !_obscureNew),
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _confirmPassword,
          obscureText: _obscureConfirm,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: ref.t('confirm_new_password_field'),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: (_passwordValid && _confirmValid && !_submitting) ? _resetPassword : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('reset_password')),
        ),
      ],
    );
  }
}
