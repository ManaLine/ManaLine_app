import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../state/admin_auth_service.dart';

enum _Step { username, otpAndPassword }

/// Admin password reset — OTP sent to admin_accounts.recovery_mobile_number
/// (9493509919, currently). Never reveals whether a username matched, same
/// confidentiality property as LR-010. Unlike the person-side flow, OTP
/// verification and the new password are submitted together in one call
/// (admin-password-reset-confirm) — the backend never splits them, so
/// neither does this screen.
class AdminForgotPasswordScreen extends ConsumerStatefulWidget {
  const AdminForgotPasswordScreen({super.key});

  @override
  ConsumerState<AdminForgotPasswordScreen> createState() => _AdminForgotPasswordScreenState();
}

class _AdminForgotPasswordScreenState extends ConsumerState<AdminForgotPasswordScreen> {
  final _authApi = AdminAuthService();
  final _username = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  _Step _step = _Step.username;
  String? _otpId;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;
  String? _sentMessage;

  final List<TextEditingController> _otpDigits = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List.generate(6, (_) => FocusNode());
  String get _otpCode => _otpDigits.map((c) => c.text).join();

  bool get _passwordValid => _newPassword.text.length >= 8;
  bool get _confirmValid => _confirmPassword.text == _newPassword.text && _confirmPassword.text.isNotEmpty;

  @override
  void dispose() {
    _username.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    for (final c in _otpDigits) {
      c.dispose();
    }
    for (final n in _otpNodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _requestReset() async {
    if (_username.text.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final otpId = await _authApi.requestPasswordReset(username: _username.text.trim());
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _otpId = otpId;
        _sentMessage = 'If this username exists, an OTP has been sent to its recovery number.';
        _step = _Step.otpAndPassword;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        // Only claim a connection problem when it actually IS one. This
        // swallowed every failure into "check your connection", which is
        // how a client-side envelope bug looked like a dead network while
        // the server was answering 200 the whole time.
        _error = e is FunctionException
            ? 'Server rejected the request (${e.status}). Please try again.'
            : e is FormatException
                ? 'Unexpected response from the server. Please report this.'
                : 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  Future<void> _confirmReset() async {
    if (_otpCode.length != 6 || !_passwordValid || !_confirmValid || _otpId == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _authApi.confirmPasswordReset(
        otpId: _otpId!,
        code: _otpCode,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('password_updated_note'))),
      );
      context.go('/admin-login');
    } on AdminAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Incorrect code, or the OTP has expired. Request a new one.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('forgot_password'), homeRoute: '/admin-login'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: switch (_step) {
            _Step.username => _usernameStep(),
            _Step.otpAndPassword => _otpAndPasswordStep(),
          },
        ),
      ),
    );
  }

  Widget _usernameStep() {
    final canSend = _username.text.trim().isNotEmpty && !_submitting;
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: ManaSpacing.xl),
        const ManaText.raw(
          'Enter the admin username. If it exists, an OTP will be sent to its linked recovery number.',
        ),
        const SizedBox(height: ManaSpacing.lg),
        TextField(
          controller: _username,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: ref.t('username_field')),
        ),
        if (_error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(_error!, style: ManaType.bad),
        ],
        const SizedBox(height: ManaSpacing.lg),
        ElevatedButton(
          onPressed: canSend ? _requestReset : null,
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : ManaText.raw(ref.t('send_otp')),
        ),
      ],
      ),
    );
  }

  Widget _otpAndPasswordStep() {
    final canSubmit = _otpCode.length == 6 && _passwordValid && _confirmValid && !_submitting;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: ManaSpacing.xl),
          if (_sentMessage != null) ManaText.raw(_sentMessage!, textAlign: TextAlign.center),
          const SizedBox(height: ManaSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(6, _otpDigitBox),
          ),
          const SizedBox(height: ManaSpacing.lg),
          TextField(
            controller: _newPassword,
            obscureText: _obscureNew,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: ref.t('new_password_field'),
              helperText: ref.t('password_helper_short'),
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
          if (_error != null) ...[
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(_error!, style: ManaType.bad),
          ],
          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton(
            onPressed: canSubmit ? _confirmReset : null,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('reset_password')),
          ),
        ],
      ),
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
          setState(() {});
        },
      ),
    );
  }
}
