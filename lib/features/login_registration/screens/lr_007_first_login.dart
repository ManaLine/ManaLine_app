import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';

/// LR-007 — Mobile Number + Password auth. Branches by pin_exists in
/// the response: false → LR-008 Create PIN; true → LR-012 Business
/// Selector directly.
class FirstLoginScreen extends ConsumerStatefulWidget {
  /// True when arriving here via LR-009's BR-201 step-down (3x wrong
  /// PIN) rather than a fresh first-time login — shows a contextual
  /// banner and pre-fills Mobile Number, per LR-009 S4.
  final bool stepDownFromFailedPin;

  /// Set when arriving via LR-010 (Forgot Password) success — pre-fills
  /// Mobile Number so the person doesn't retype what they just entered.
  final String? prefilledMobile;

  /// Set when arriving via LR-010 success — shown once as a SnackBar,
  /// per that screen's exit spec ("Password updated — please log in").
  final String? successToast;

  /// Set when this screen is reached purely to re-establish identity for
  /// a recovery flow (e.g. LR-009's "Forgot Pin?" before any personId is
  /// known this session) — route here on success instead of the normal
  /// lr-012/lr-008 destination.
  final String? redirectAfterSuccess;

  const FirstLoginScreen({
    super.key,
    this.stepDownFromFailedPin = false,
    this.prefilledMobile,
    this.successToast,
    this.redirectAfterSuccess,
  });

  @override
  ConsumerState<FirstLoginScreen> createState() => _FirstLoginScreenState();
}

class _FirstLoginScreenState extends ConsumerState<FirstLoginScreen> {
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.prefilledMobile != null) {
      _mobile.text = widget.prefilledMobile!;
    } else if (widget.stepDownFromFailedPin) {
      LocalAuthStore.readLastMobileNumber().then((mobile) {
        if (mobile != null && mounted) setState(() => _mobile.text = mobile);
      });
    }
    if (widget.successToast != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.successToast!)),
        );
      });
    }
  }

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final fingerprint = await LocalAuthStore.deviceFingerprint();

    LoginResult? result;
    final reached = await NetworkErrorHandler.run(context, () async {
      result = await ref.read(authApiServiceProvider).login(
            identifier: _mobile.text,
            credential: _password.text,
            credentialType: 'password',
            deviceFingerprint: fingerprint,
          );
      return true;
    });

    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }

    if (result == null || !result!.success || result!.token == null || result!.personId == null) {
      setState(() {
        _submitting = false;
        _error = 'Incorrect mobile number or password.';
      });
      return;
    }

    final pinExists = result!.pinExists;

    final previousMobile = await LocalAuthStore.readLastMobileNumber();
    final isDifferentAccount = previousMobile != null && previousMobile != _mobile.text;
    await LocalAuthStore.saveMobileNumber(_mobile.text);
    if (widget.stepDownFromFailedPin || isDifferentAccount) await LocalAuthStore.clearPin();

    await ref.read(authFlowProvider.notifier).setLoginResult(
          personId: result!.personId!,
          token: result!.token!,
          pinExists: pinExists,
        );

    if (!mounted) return;

    if (widget.redirectAfterSuccess != null) {
      context.push(widget.redirectAfterSuccess!);
      return;
    }

    if (pinExists) {
      // Session is live (ManaSession set inside setLoginResult above) —
      // safe to fetch real memberships now, subject to RLS
      // business_members_self_select.
      final memberships = await NetworkErrorHandler.run(
        context,
        () => ref.read(authApiServiceProvider).fetchMemberships(),
      );
      if (!mounted) return;
      if (memberships == null) {
        setState(() => _submitting = false);
        return; // network failure — SnackBar already shown
      }
      ref.read(authFlowProvider.notifier).setMemberships(memberships);
      context.go('/lr-012');
    } else {
      context.go('/lr-008');
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _mobile.text.length == 10 && _password.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: ManaSpacing.xxl),
              if (widget.stepDownFromFailedPin)
                Container(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  margin: const EdgeInsets.only(bottom: ManaSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const ManaText.raw('Enter your password to continue',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Mobile Number *'),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Password *'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  children: [
                    TextButton(
                      onPressed: () => context.push('/lr-011'),
                      child: const ManaText('forgot pin?'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/lr-010'),
                      child: const ManaText('forgot password?'),
                    ),
                  ],
                ),
              ),
              if (_error != null) ManaText.raw(_error!),
              const SizedBox(height: ManaSpacing.lg),
              ElevatedButton(
                onPressed: (canSubmit && !_submitting) ? _login : null,
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const ManaText('login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
