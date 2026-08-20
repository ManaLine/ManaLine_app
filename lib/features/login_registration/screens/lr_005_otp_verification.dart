import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/translation_service.dart';

enum OtpPurpose { registration, passwordReset, pinReset, accountUnlock, roleEscalation }

/// Maps this screen's UI-level purpose enum to the exact
/// otp_purpose_enum values in the schema (0001_module0_identity.sql):
/// ('Registration','Role Escalation','Password Reset','PIN Reset',
/// 'Account Unlock','Agreement Acceptance'). Only used for the resend
/// call — the initial send (and its resulting otp_id) always comes from
/// whichever screen triggered this one (register()/passwordResetRequest()/
/// pinResetRequest()/etc.), set into authFlowProvider.pendingOtpId before
/// navigating here.
String _otpPurposeEnumValue(OtpPurpose p) => switch (p) {
      OtpPurpose.registration => 'Registration',
      OtpPurpose.passwordReset => 'Password Reset',
      OtpPurpose.pinReset => 'PIN Reset',
      OtpPurpose.accountUnlock => 'Account Unlock',
      OtpPurpose.roleEscalation => 'Role Escalation',
    };

/// LR-005 — shared OTP screen, GC-004 component. `purpose` controls the
/// prompt text and where success routes to (per spec's Exit Points).
///
/// otp_id is deliberately NOT a constructor param (router.dart's existing
/// `OtpVerificationScreen(purpose: ...)` builder is untouched, per this
/// chat's file-ownership boundary) — instead read from
/// authFlowProvider.pendingOtpId, set by whichever screen triggered the
/// OTP send before navigating here.
/// Typed `extra` payload for navigating to LR-005 — replaces the bare
/// `OtpPurpose` enum once Role Escalation needed to also carry a
/// membershipId (which specific business_members row this OTP targets).
class OtpEntryArgs {
  final OtpPurpose purpose;
  final String? membershipId;
  const OtpEntryArgs({required this.purpose, this.membershipId});
}

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final OtpPurpose purpose;
  final String? membershipId;
  const OtpVerificationScreen({super.key, this.purpose = OtpPurpose.registration, this.membershipId});

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final List<TextEditingController> _digits = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  int _resendCount = 0;
  int _incorrectCount = 0;
  bool _verifying = false;
  String? _error;

  String get _code => _digits.map((c) => c.text).join();

  String get _promptText => switch (widget.purpose) {
        OtpPurpose.registration => 'Enter the OTP sent to verify your number',
        OtpPurpose.passwordReset => 'Enter the OTP sent to reset your password',
        OtpPurpose.pinReset => 'Enter the OTP sent to reset your PIN',
        OtpPurpose.accountUnlock => 'Too many failed attempts. Enter the OTP sent to unlock your account',
        OtpPurpose.roleEscalation => 'Enter the OTP sent to verify this role',
      };

  Future<void> _verify() async {
    if (_code.length != 6) return;
    final otpId = ref.read(authFlowProvider).pendingOtpId;
    if (otpId == null) {
      // This screen's verification session lives in memory only — a page
      // refresh (or directly navigating/pasting a URL) wipes it, since
      // there's no persistence layer for it. Message is explicit about
      // this rather than a generic "try again" that doesn't explain why
      // simply retrying won't help.
      setState(() => _error =
          'Your verification session was lost — this happens if the page was refreshed or reopened directly. Please go back and start again from the beginning.');
      return;
    }

    setState(() => _verifying = true);

    bool? verified;
    final reached = await NetworkErrorHandler.run(context, () async {
      verified = await ref.read(authApiServiceProvider).verifyOtp(otpId: otpId, code: _code);
      return true;
    });

    if (!mounted) return;
    if (reached == null) {
      setState(() => _verifying = false);
      return; // network failure — SnackBar already shown, stay on this step
    }

    if (verified != true) {
      setState(() {
        _verifying = false;
        _incorrectCount++;
        _error = 'Incorrect code. Please try again.';
        for (final c in _digits) {
          c.clear();
        }
      });
      _nodes.first.requestFocus();
      if (_incorrectCount >= 5) {
        setState(() => _error = 'Too many incorrect attempts. A new code is required.');
      }
      return;
    }

    ref.read(authFlowProvider.notifier).clearPendingOtpId();

    switch (widget.purpose) {
      case OtpPurpose.registration:
        context.go('/lr-006');
        break;
      case OtpPurpose.passwordReset:
        context.go('/lr-010'); // continues that flow's Step 3
        break;
      case OtpPurpose.pinReset:
        context.go('/lr-011');
        break;
      case OtpPurpose.accountUnlock:
        context.go('/lr-007');
        break;
      case OtpPurpose.roleEscalation:
        context.pop();
        break;
    }
  }

  Future<void> _resend() async {
    if (_resendCount >= 5) return;
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      setState(() => _error =
          'Your verification session was lost — this happens if the page was refreshed or reopened directly. Please go back and start again from the beginning.');
      return;
    }

    final newOtpId = await NetworkErrorHandler.run(context, () async {
      return ref.read(authApiServiceProvider).sendOtp(
            personId: personId,
            purpose: _otpPurposeEnumValue(widget.purpose),
            membershipId: widget.membershipId,
          );
    });
    if (!mounted || newOtpId == null) return; // network failure — SnackBar already shown

    ref.read(authFlowProvider.notifier).setPendingOtpId(newOtpId);
    setState(() {
      _resendCount++;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ManaText.raw(_promptText, textAlign: TextAlign.center),
              const SizedBox(height: ManaSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) => _digitBox(i)),
              ),
              if (_error != null) ...[
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw(_error!, style: ManaType.bad,
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: ManaSpacing.lg),
              TextButton(
                onPressed: _resendCount < 5 ? _resend : null,
                child: ManaText(
                  _resendCount >= 5 ? 'maximum resend attempts reached' : 'resend otp',
                ),
              ),
              const SizedBox(height: ManaSpacing.xl),
              ElevatedButton(
                onPressed: (_code.length == 6 && !_verifying) ? _verify : null,
                child: _verifying
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('verify_button')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _digitBox(int i) {
    return SizedBox(
      width: 44,
      child: TextField(
        controller: _digits[i],
        focusNode: _nodes[i],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        decoration: const InputDecoration(counterText: ''),
        onChanged: (v) {
          if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
          if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
          if (i == 5 && v.isNotEmpty) _verify(); // auto-submit on 6th digit
          setState(() {});
        },
      ),
    );
  }
}
