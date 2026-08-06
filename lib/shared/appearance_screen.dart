import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';
import '../design/components/mana_amount.dart';
import 'appearance_state.dart';

/// P2 Appearance — text size.
///
/// The preview is the point. A list of the words Small/Normal/Large tells
/// someone nothing about whether they will be able to read a rupee figure at
/// arm's length in sunlight; showing one at the chosen size does. The change
/// applies immediately across the whole app, so tapping an option IS the
/// preview — this screen just puts a money figure on screen to look at while
/// deciding.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const ManaText('appearance'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText('text size',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.xs),
            const ManaText.raw(
              'This adds to whatever text size your phone is already set to.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),

            // RadioGroup rather than per-tile groupValue/onChanged: those two
            // are deprecated on RadioListTile as of Flutter 3.32.
            RadioGroup<ManaTextSize>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) ref.read(appearanceProvider.notifier).set(v);
              },
              child: Column(
                children: [
                  for (final size in ManaTextSize.values)
                    RadioListTile<ManaTextSize>(
                      value: size,
                      contentPadding: EdgeInsets.zero,
                      title: ManaText(size.label),
                    ),
                ],
              ),
            ),

            const SizedBox(height: ManaSpacing.lg),
            const ManaText('preview',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.sm),
            Container(
              padding: const EdgeInsets.all(ManaSpacing.md),
              decoration: BoxDecoration(
                color: ManaColors.surface,
                borderRadius: BorderRadius.circular(ManaRadius.md),
                border: Border.all(color: ManaColors.divider),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw('Today’s Collection',
                      style: TextStyle(
                          fontSize: 13, color: ManaColors.textSecondary)),
                  SizedBox(height: ManaSpacing.xs),
                  // A real money figure through the real component, not
                  // lorem text: the whole reason to change text size in this
                  // app is being able to read amounts.
                  ManaAmount(12450, semanticLabel: 'Example amount'),
                  SizedBox(height: ManaSpacing.sm),
                  ManaText.raw(
                    'Ravi Kumar — instalment due today',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: ManaSpacing.xl),
            // Said out loud rather than left as a silent absence, so nobody
            // goes looking for a switch that is not there.
            const ManaText.raw(
              'Dark mode is not available yet.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
