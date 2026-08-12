import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../../../shared/local_auth_store.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../../../shared/live_photo_upload.dart';
import '../../../shared/gps_address_service.dart';
import 'lr_005_otp_verification.dart';

/// LR-007 — Mobile Number + Password auth. Branches by pin_exists in
/// the response: false → LR-008 Create PIN; true → LR-012 Business
/// Selector directly (or LR-008 in upgrade mode first, if
/// needs_pin_upgrade came back true — ADDED this batch).
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
  bool _obscurePassword = true;
  String? _error;
  String? _pendingRedirect; // set when "forgot pin?" needs to verify password first, then hand off

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    });
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
    if (!mounted) return;

    LoginResult? result;
    AccountLockedException? locked;
    final reached = await NetworkErrorHandler.run(context, () async {
      try {
        result = await ref.read(authApiServiceProvider).login(
              identifier: _mobile.text,
              credential: _password.text,
              credentialType: 'password',
              deviceFingerprint: fingerprint,
            );
      } on AccountLockedException catch (e) {
        // BUG FIXED this pass: BR-201 lockout used to fall through to the
        // generic "incorrect" branch below — the OTP-unlock screen this
        // routes to already existed but was unreachable from here.
        locked = e;
      }
      return true;
    });

    if (!mounted) return;
    if (reached == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
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

    if (result == null || !result!.success || result!.token == null || result!.personId == null) {
      setState(() {
        _submitting = false;
        _error = 'Incorrect mobile number or password.';
        _pendingRedirect = null;
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

    // Upload the registration-time live photo now, if one is pending —
    // this is the earliest point a real session/JWT exists (registration
    // itself has none, so persons_self_update RLS couldn't be satisfied
    // there). Non-fatal: a failed upload never blocks login, just leaves
    // profile_photo_url unset for this person to retry later via Profile.
    final pendingPhoto = ref.read(authFlowProvider).pendingProfilePhotoBytes;
    if (pendingPhoto != null) {
      try {
        final personId = result!.personId!;
        final url = await ProfilePhotoUpload.upload(
          bytes: pendingPhoto,
          personId: personId,
        );
        await Supabase.instance.client
            .from('persons')
            .update({'profile_photo_url': url})
            .eq('person_id', personId);

        // Also record it as an identity document. WHY HERE: a self-registered
        // person otherwise has no identity_documents row at all — LR-004 never
        // creates one — while auth-register already stamps them
        // profile_status='Complete' from dob+mobile+aadhaar. They therefore
        // never appear in OW-014's incomplete list, so nothing would ever
        // prompt anyone to collect a document for them.
        //
        // Type 'Photo', not 'Aadhaar': file_url is NOT NULL and the only real
        // file in this flow is the live capture. Registration collects an
        // Aadhaar *number*, never an Aadhaar image, so an 'Aadhaar' row here
        // would need an invented file_url — a fabricated record, which is
        // worse than no record.
        //
        // NOT MANDATORY, per the Owner's instruction: its own try, so a failed
        // insert leaves the photo (already saved above) intact and never
        // blocks first login.
        try {
          await Supabase.instance.client.from('identity_documents').insert({
            'person_id': personId,
            'document_type': 'Photo',
            'file_url': url,
          });
        } catch (_) {
          // Non-fatal by design. uploaded_at defaults to now() under the
          // Asia/Kolkata database, so no client timestamp is sent.
        }
      } catch (e) {
        // Swallowed deliberately — see comment above.
      } finally {
        ref.read(authFlowProvider.notifier).clearPendingProfilePhoto();
      }
    }

    if (!mounted) return;

    // Location consent, asked ONCE at first login rather than at every
    // doorstep. An agent prompted on every visit taps through without
    // reading, which is not consent. Declining is a real answer and costs
    // nothing: GPS never gates a loan, a customer or an address.
    await _askLocationConsent(result!.personId!);
    if (!mounted) return;

    final redirect = _pendingRedirect ?? widget.redirectAfterSuccess;
    if (redirect != null) {
      context.push(redirect);
      return;
    }

    if (pinExists) {
      // Session is live (ManaSession set inside setLoginResult above) —
      // safe to fetch real memberships now, subject to RLS
      // business_members_self_select.
      final memberships = await NetworkErrorHandler.run(
        context,
        () => ref.read(authApiServiceProvider).fetchMemberships(ref.read(authFlowProvider).personId!),
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
    } else {
      context.go('/lr-008');
    }
  }

  /// Asked once, at first login. Stored on the person, so no screen asks
  /// again.
  ///
  /// Non-fatal throughout: if the write fails, the person simply has not
  /// consented and nothing captures location. Location is never required for
  /// anything, so a failure here has no downstream victim.
  Future<void> _askLocationConsent(String personId) async {
    try {
      final already =
          await ref.read(gpsAddressServiceProvider).hasConsent(personId: personId);
      if (already || !mounted) return;

      final granted = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: ManaText.raw(ref.t('use_your_location_question')),
          content: const ManaText.raw(
            'When you visit a customer, MANA LINE can note where you were, to '
            'confirm the visit happened at their address.\n\n'
            'It is only read while you are using the app, never in the '
            'background. You can say no — nothing in the app stops working '
            'either way.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: ManaText.raw(ref.t('not_now'))),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: ManaText.raw(ref.t('allow'))),
          ],
        ),
      );

      await ref
          .read(gpsAddressServiceProvider)
          .setConsent(personId: personId, granted: granted == true);
    } catch (_) {
      // Deliberately swallowed: this is a preference, not a money path, and a
      // failure to record it must not block a login that already succeeded.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final lang = ref.watch(authFlowProvider).language;
    final canSubmit = _mobile.text.length == 10 && _password.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        // SCROLLS. This was a fixed Column, so the login button at the
        // bottom overflowed by ~22px on a real handset — and the keyboard
        // opening for the mobile/password fields makes it far worse. A
        // login screen has to survive every device height, a raised system
        // font, and a longer language; a Column that cannot scroll survives
        // none of them.
        child: SingleChildScrollView(
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
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  children: [
                    TextButton(
                      onPressed: (_mobile.text.length == 10 && _password.text.isNotEmpty && !_submitting)
                          ? () {
                              // Was: blind context.push('/lr-011') — landed on Forgot
                              // Pin with no personId ever established (whoever's PIN
                              // is being reset was never verified), causing "session
                              // expired" as soon as that screen tried to act on an
                              // identity it never actually had. Fix: verify the
                              // password already typed here via the normal _login
                              // flow first, THEN hand off to LR-011 only on success —
                              // same pattern already used for LR-009's own
                              // "forgot pin?" link.
                              setState(() => _pendingRedirect = '/lr-011');
                              _login();
                            }
                          : null,
                      child: ManaText.raw(ref.t('forgot_pin')),
                    ),
                    TextButton(
                      onPressed: () => context.push('/lr-010'),
                      child: ManaText.raw(ref.t('forgot_password')),
                    ),
                    // Was missing: someone who is not yet registered could
                    // reach this password form (it is the generic login screen)
                    // and had no route to registration from it. No "change
                    // user" here, unlike LR-009 — on this screen you simply
                    // type a different mobile number, so there is no remembered
                    // identity to switch away from.
                    TextButton(
                      onPressed: () => context.push('/lr-004'),
                      child: ManaText.raw(ref.t('register_button')),
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
                    : ManaText.raw(ref.t('login_button')),
              ),
              const SizedBox(height: ManaSpacing.xl),
              Align(
                alignment: Alignment.center,
                child: ManaLanguageSelector(
                  current: lang,
                  onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
