import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import 'network_error_handler.dart';

/// P4 Security — switch an account off, or ask for it to be deleted.
///
/// Two very different things, deliberately presented as such:
///
///   * Switching off keeps everything and only blocks sign-in. It is
///     completely reversible by signing back in.
///   * Deleting starts a 90-day clock. It is reversible for all 90 days by
///     signing back in, and the screen says so plainly rather than implying
///     the decision is final the moment it is made.
///
/// Both log the person out afterwards, because both make their own account
/// unusable — leaving them on a working dashboard after switching off would
/// be showing them a session that no longer has a way back.
class AccountClosureScreen extends ConsumerStatefulWidget {
  const AccountClosureScreen({super.key});

  @override
  ConsumerState<AccountClosureScreen> createState() =>
      _AccountClosureScreenState();
}

class _AccountClosureScreenState extends ConsumerState<AccountClosureScreen> {
  bool _busy = false;

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText(title),
        content: ManaText.raw(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const ManaText('cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: ManaText.raw(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _run(String rpc, {required String title, required String body,
      required String confirmLabel, required String done}) async {
    if (!await _confirm(title: title, body: body, confirmLabel: confirmLabel)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);

    final result = await NetworkErrorHandler.run(context, () async {
      return Supabase.instance.client.schema('app').rpc(rpc);
    });

    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return; // network failure — already surfaced

    // Log out: the session that remains cannot be used to sign in again, so
    // keeping it would show a dashboard the person can never return to.
    ref.read(authFlowProvider.notifier).reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(done)),
    );
    context.go('/lr-003');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const ManaText('account'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText('switch off my account',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Your records stay exactly as they are. You will not be able to '
              'sign in until you switch it back on, which you can do at any '
              'time by signing in again.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.sm),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        'disable_own_account',
                        title: 'switch off my account',
                        body: 'You will be signed out. Sign in again whenever '
                            'you want it back — nothing is deleted.',
                        confirmLabel: 'Switch Off',
                        done: 'Your account is switched off.',
                      ),
              child: const ManaText('switch off'),
            ),
            const Divider(height: ManaSpacing.xxl),
            ManaText('delete my account',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: ManaColors.statusBad)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Your account is switched off straight away and scheduled for '
              'deletion in 90 days. You can still change your mind at any '
              'point in those 90 days by signing in again.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.xs),
            // Said plainly rather than discovered at the point of failure: an
            // Owner cannot leave a live business behind, because its agents
            // and customers would have nobody able to administer them.
            ManaText.raw(
              'If you own a business, transfer or close it first.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: ManaColors.statusBad),
              onPressed: _busy
                  ? null
                  : () => _run(
                        'request_account_deletion',
                        title: 'delete my account',
                        body: 'Your account will be switched off now and '
                            'deleted after 90 days. Sign in again at any time '
                            'in those 90 days to stop it.',
                        confirmLabel: 'Delete',
                        done: 'Your account is scheduled for deletion.',
                      ),
              child: const ManaText('delete my account'),
            ),
            if (_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
