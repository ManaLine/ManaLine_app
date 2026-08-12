import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../state/admin_auth_service.dart';

/// Platform Admin's own login screen — not reached from anywhere in the
/// regular Owner/Agent/Customer/Investor login flow (that entry point,
/// buried inside OW-001's own popup menu, was removed entirely; see
/// supabase/migrations/20260807125210_admin_own_identity_system.sql).
/// Username+password against admin_accounts, nothing to do with `persons`.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _authApi = AdminAuthService();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  bool get _canSubmit => _username.text.trim().isNotEmpty && _password.text.isNotEmpty && !_submitting;

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await _authApi.login(username: _username.text.trim(), password: _password.text);
      if (!mounted) return;
      context.go('/admin-panel');
    } on AdminAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('admin_login'))),
      body: SafeArea(
        // SCROLLS. A non-scrolling Column overflowed by 140px the moment the
        // keyboard opened over the password field — the same class of fault
        // as LR-002 and the Request to Join sheet. A login screen is
        // guaranteed to have the keyboard up, so it is the last place that
        // can afford a fixed-height layout.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: ManaSpacing.xxl),
              Icon(Icons.admin_panel_settings_outlined, size: 48, color: ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(ref.t('platform_admin'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.xl),
              TextField(
                controller: _username,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: ref.t('username_field')),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _canSubmit ? _login() : null,
                decoration: InputDecoration(
                  labelText: ref.t('password_field'),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw(_error!, style: TextStyle(color: ManaColors.statusBad)),
              ],
              const SizedBox(height: ManaSpacing.lg),
              ElevatedButton(
                onPressed: _canSubmit ? _login : null,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('login')),
              ),
              const SizedBox(height: ManaSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : () => context.push('/admin-forgot-password'),
                  child: ManaText.raw(ref.t('forgot_password_question')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
