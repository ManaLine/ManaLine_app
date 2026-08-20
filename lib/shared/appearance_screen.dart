import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
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
    final appearance = ref.watch(appearanceProvider);
    final current = appearance.textSize;

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
            const ManaText('theme',
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Dark uses less battery on some phones, and is easier at night. '
              'Light is easier to read in direct sun.',
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            RadioGroup<ManaThemeChoice>(
              groupValue: appearance.theme,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appearanceProvider.notifier).setTheme(v);
                }
              },
              child: Column(
                children: [
                  for (final choice in ManaThemeChoice.values)
                    RadioListTile<ManaThemeChoice>(
                      value: choice,
                      contentPadding: EdgeInsets.zero,
                      title: ManaText(choice.label),
                    ),
                ],
              ),
            ),

            const SizedBox(height: ManaSpacing.lg),
            const ManaText('text size',
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'This adds to whatever text size your phone is already set to.',
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),

            // RadioGroup rather than per-tile groupValue/onChanged: those two
            // are deprecated on RadioListTile as of Flutter 3.32.
            RadioGroup<ManaTextSize>(
              groupValue: current,
              onChanged: (v) {
                if (v != null) {
                  ref.read(appearanceProvider.notifier).setTextSize(v);
                }
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
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.sm),
            Container(
              padding: const EdgeInsets.all(ManaSpacing.md),
              decoration: BoxDecoration(
                color: ManaColors.surface,
                borderRadius: BorderRadius.circular(ManaRadius.md),
                border: Border.all(color: ManaColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw('Today’s Collection',
                      style: TextStyle(
                          fontSize: 13, color: ManaColors.textSecondary)),
                  const SizedBox(height: ManaSpacing.xs),
                  // A real money figure through the real component, not
                  // lorem text: the whole reason to change text size in this
                  // app is being able to read amounts.
                  const ManaAmount(12450, semanticLabel: 'Example amount'),
                  const SizedBox(height: ManaSpacing.sm),
                  const ManaText.raw(
                    'Ravi Kumar — instalment due today',
                    style: ManaType.small,
                  ),
                ],
              ),
            ),

            const SizedBox(height: ManaSpacing.xl),
            // The one honest caveat. The dark palette's contrast ratios were
            // derived, not measured on glass, and this app is read outdoors on
            // cheap screens — so it is worth saying that light remains the
            // tested-in-the-field option.
            ManaText.raw(
              'Dark is new. If anything is hard to read outdoors, switch back '
              'to light and tell us which screen.',
              style: ManaType.note,
            ),
          ],
        ),
      ),
    );
  }
}
