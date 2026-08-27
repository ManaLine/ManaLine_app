import 'translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../features/login_registration/state/auth_flow_state.dart';
import '../features/owner_workspace/state/global_workflow_state.dart';
import 'mana_time.dart';
import 'network_error_handler.dart';

/// P2 About + Terms.
///
/// The terms are written in plain sentences rather than legal register,
/// because the people agreeing to them are field agents and shop owners in
/// villages, and terms nobody can read protect nobody. Each point is here
/// because it is TRUE OF THIS APP, not because it is customary:
///
///   * records-only — the app never moves money, so it cannot lose any;
///   * security is a priority, stated without promising perfection;
///   * negligence — a shared PIN or a lent phone is not something the app
///     can undo;
///   * Line Score is arithmetic on recorded repayments, not a judgement of a
///     person, and saying so is the difference between a number people trust
///     and one they resent.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  /// Kept in step with pubspec.yaml by hand, like SettingsScreen's copy —
  /// package_info_plus is not a dependency and one static line does not
  /// justify adding it.
  static const versionLabel = 'v0.1.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: ManaAppBar(
        homeRoute: '/settings',
        title: ref.t('about'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ...<Widget>[
            const ManaText('mana line',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(versionLabel,
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.lg),

            const _Point(
              title: 'This app keeps records. It does not move money.',
              body: 'Every rupee is handed over in person, exactly as it '
                  'always was. MANA LINE writes down what happened. No '
                  'payment passes through this app, and no account here can '
                  'hold your money.',
            ),
            const _Point(
              title: 'Your records are kept carefully.',
              body: 'Records are locked to your business, and only people you '
                  'have given a role can see them. Photos and documents are '
                  'private and are never shown publicly.',
            ),
            const _Point(
              title: 'Keep your PIN and phone to yourself.',
              body: 'If you share your PIN, lend your phone while signed in, '
                  'or let someone else record entries as you, we cannot undo '
                  'what they do. Records made that way count as yours.',
            ),
            const _Point(
              title: 'Line Score is arithmetic, not an opinion.',
              body: 'It is worked out only from repayments already recorded '
                  'in this app — how much, and how close to the due date. It '
                  'uses nothing about you as a person: not your caste, '
                  'religion, village, family, age or anything you have said. '
                  'Repay on time and it rises.',
            ),
            const _Point(
              title: 'Deleting your account.',
              body: 'You can switch your account off at any time and switch it '
                  'back on by signing in. If you ask for deletion, it happens '
                  '90 days later and you can stop it at any point before then. '
                  'Loans and collections already recorded stay on the '
                  'business’s books, with your personal details removed.',
            ),

            const SizedBox(height: ManaSpacing.lg),
            ManaText.raw(
              'Questions: manaline.in@gmail.com',
              style: ManaType.note,
            ),
            ],
            const TermsAcceptance(),
          ],
        ),
      ),
    );
  }
}

/// Records acceptance of the terms shown above.
///
/// This exists because persons.terms_accepted_at was READ in two places —
/// app.owner_member_profile's completion summary and OW-014's member-side
/// check — and written by nothing at all, so both were permanently false and
/// a profile could never report the member side as complete.
///
/// Placed at the bottom of the terms rather than behind a separate screen: an
/// "I accept" button somewhere the terms are not visible is a worse record of
/// consent than one directly under them.
class TermsAcceptance extends ConsumerStatefulWidget {
  const TermsAcceptance({super.key});

  @override
  ConsumerState<TermsAcceptance> createState() => _TermsAcceptanceState();
}

class _TermsAcceptanceState extends ConsumerState<TermsAcceptance> {
  bool _busy = false;
  DateTime? _acceptedAt;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      if (mounted) setState(() => _loaded = true);
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('persons')
          .select('terms_accepted_at')
          .eq('person_id', int.parse(personId))
          .maybeSingle();
      final raw = row?['terms_accepted_at'] as String?;
      if (!mounted) return;
      setState(() {
        _acceptedAt = raw == null ? null : DateTime.tryParse(raw);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _accept() async {
    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) return;
    setState(() => _busy = true);

    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(globalWorkflowApiServiceProvider)
          .acceptTerms(personId: personId);
      return true;
    });

    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to offer someone who is not signed in, and nothing to say until
    // the current state is known — a button that flips from "Accept" to
    // "Accepted" a second after the screen opens looks like a misclick.
    if (!_loaded || ref.watch(authFlowProvider).personId == null) {
      return const SizedBox.shrink();
    }

    if (_acceptedAt != null) {
      return Padding(
        padding: const EdgeInsets.only(top: ManaSpacing.lg),
        child: ManaText.raw(
          'You accepted these terms on ${manaDisplayDate(_acceptedAt)}.',
          style: TextStyle(
              fontSize: 13, color: ManaColors.textSecondary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: ManaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: _busy ? null : _accept,
            child: const ManaText('i accept these terms'),
          ),
          if (_busy) ...[
            const SizedBox(height: ManaSpacing.md),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final String title;
  final String body;
  const _Point({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // raw: this copy is already written as sentences, and title-casing
          // a sentence would mangle it.
          ManaText.raw(title,
              style: ManaType.heavy),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(body,
              style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
