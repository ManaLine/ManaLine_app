import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../state/admin_auth_service.dart';

/// Platform Admin's own login screen — not reached from anywhere in the
/// regular Owner/Agent/Customer/Investor login flow (that entry point,
/// buried inside OW-001's own popup menu, was removed entirely; see
/// supabase/migrations/20260807125210_admin_own_identity_system.sql).
/// Username+password against admin_accounts, nothing to do with `persons`.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
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
        _error = 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const ManaText('admin login')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: ManaSpacing.xxl),
              Icon(Icons.admin_panel_settings_outlined, size: 48, color: ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.md),
              const ManaText.raw('Platform Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.xl),
              TextField(
                controller: _username,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Username *'),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _password,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _canSubmit ? _login() : null,
                decoration: InputDecoration(
                  labelText: 'Password *',
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
                    : const ManaText('login'),
              ),
              const SizedBox(height: ManaSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : () => context.push('/admin-forgot-password'),
                  child: const ManaText('forgot password?'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
