import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../state/auth_flow_state.dart';

/// LR-002 — root product picker. V1 ships MLF (Mana Finance) only;
/// MLC (Mana Chits) is visible-but-disabled to establish brand presence.
class WorkspaceChoiceScreen extends ConsumerWidget {
  const WorkspaceChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(authFlowProvider).language;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              const SizedBox(height: ManaSpacing.xl),
              Text('MANA LINE', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              const ManaText('choose workspace', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.lg),
              _ProductCard(
                code: 'MLF',
                name: 'Mana Finance',
                enabled: true,
                onTap: () => context.push('/lr-003'),
              ),
              const SizedBox(height: ManaSpacing.md),
              _ProductCard(
                code: 'MLC',
                name: 'Mana Chits',
                enabled: false,
                badge: 'Coming Soon',
                onTap: () => _showComingSoon(context),
              ),
              const Spacer(),
              ManaLanguageSelector(
                current: lang,
                onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
              ),
              const SizedBox(height: ManaSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ManaText('mana chits — coming soon — version 2', textAlign: TextAlign.center),
            const SizedBox(height: ManaSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const ManaText('close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String code;
  final String name;
  final bool enabled;
  final String? badge;
  final VoidCallback onTap;

  const _ProductCard({
    required this.code,
    required this.name,
    required this.enabled,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: enabled ? ManaColors.brassFaint : ManaColors.surfaceSunken,
                  child: ManaText.raw(code, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(name, style: Theme.of(context).textTheme.titleMedium),
                      if (badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: ManaText(badge!, style: Theme.of(context).textTheme.labelSmall),
                        ),
                    ],
                  ),
                ),
                if (enabled) const Icon(Icons.chevron_right, color: ManaColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
