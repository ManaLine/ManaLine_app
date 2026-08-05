import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';

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
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const ManaText('about'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: const [
            ManaText('mana line',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            SizedBox(height: ManaSpacing.xs),
            ManaText.raw(versionLabel,
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
            SizedBox(height: ManaSpacing.lg),

            _Point(
              title: 'This app keeps records. It does not move money.',
              body: 'Every rupee is handed over in person, exactly as it '
                  'always was. MANA LINE writes down what happened. No '
                  'payment passes through this app, and no account here can '
                  'hold your money.',
            ),
            _Point(
              title: 'Your records are kept carefully.',
              body: 'Records are locked to your business, and only people you '
                  'have given a role can see them. Photos and documents are '
                  'private and are never shown publicly.',
            ),
            _Point(
              title: 'Keep your PIN and phone to yourself.',
              body: 'If you share your PIN, lend your phone while signed in, '
                  'or let someone else record entries as you, we cannot undo '
                  'what they do. Records made that way count as yours.',
            ),
            _Point(
              title: 'Line Score is arithmetic, not an opinion.',
              body: 'It is worked out only from repayments already recorded '
                  'in this app — how much, and how close to the due date. It '
                  'uses nothing about you as a person: not your caste, '
                  'religion, village, family, age or anything you have said. '
                  'Repay on time and it rises.',
            ),
            _Point(
              title: 'Deleting your account.',
              body: 'You can switch your account off at any time and switch it '
                  'back on by signing in. If you ask for deletion, it happens '
                  '90 days later and you can stop it at any point before then. '
                  'Loans and collections already recorded stay on the '
                  'business’s books, with your personal details removed.',
            ),

            SizedBox(height: ManaSpacing.lg),
            ManaText.raw(
              'Questions: manaline.in@gmail.com',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
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
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(body,
              style: const TextStyle(fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}
