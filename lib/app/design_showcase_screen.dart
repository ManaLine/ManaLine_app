import 'package:flutter/material.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../shared/widgets/language_selector.dart';

/// Not a real spec screen — a temporary showcase so the design system
/// (colors, type, ring motif, status pills, language selector) can be
/// reviewed as a whole before it gets used to build LR-001 onward.
/// Delete once real screens are underway and this no longer earns its
/// place in the route table.
class DesignShowcaseScreen extends StatefulWidget {
  const DesignShowcaseScreen({super.key});

  @override
  State<DesignShowcaseScreen> createState() => _DesignShowcaseScreenState();
}

class _DesignShowcaseScreenState extends State<DesignShowcaseScreen> {
  ManaLanguage _lang = ManaLanguage.english;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: ManaAppBar(
        // A literal, not a key: this is a development screen, not shipped
        // UI, and inventing a translation row for it would be noise.
        title: 'MANA LINE Design System',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: ManaSpacing.md),
            child: ManaLanguageSelector(
              current: _lang,
              onChanged: (l) => setState(() => _lang = l),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        children: [
          const ManaText('color tokens',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          Wrap(
            spacing: ManaSpacing.sm,
            runSpacing: ManaSpacing.sm,
            children: [
              _Swatch('Ink', ManaColors.ink),
              _Swatch('Brass', ManaColors.brand),
              _Swatch('Good', ManaColors.statusGood),
              _Swatch('Bad', ManaColors.statusBad),
              _Swatch('Warn', ManaColors.statusWarn),
            ],
          ),
          const SizedBox(height: ManaSpacing.xl),

          const ManaText('typography',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          Text('Owner Home Dashboard', style: textTheme.displayMedium),
          Text('Today\'s Business Summary', style: textTheme.headlineMedium),
          Text('Outstanding balance and today\'s due customers.',
              style: textTheme.bodyMedium),
          Text('₹ 1,24,850', style: ManaTypography.amount(fontSize: 24)),
          const SizedBox(height: ManaSpacing.xl),

          const ManaText('title case enforcement (11_ui_guidelines.md)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          const ManaText('grace period'), // renders "Grace Period"
          const ManaText(
              'request for loan'), // renders "Request for Loan" — "for" lowercase
          const ManaText.raw(
              'MLPI112345678 — Ramesh K.'), // untouched — ID + free text
          const SizedBox(height: ManaSpacing.xl),

          const ManaText('status pills',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          const Wrap(
            spacing: ManaSpacing.sm,
            children: [
              ManaStatusPill(label: 'Balanced', status: ManaStatus.good),
              ManaStatusPill(label: 'Penalty', status: ManaStatus.bad),
              ManaStatusPill(label: 'Grace Period', status: ManaStatus.warn),
              ManaStatusPill(label: 'Removed', status: ManaStatus.neutral),
            ],
          ),
          const SizedBox(height: ManaSpacing.xl),

          const ManaText('verification ring (br-191 / gc-002)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          const Row(
            children: [
              ManaVerificationRing(isVerified: true),
              SizedBox(width: ManaSpacing.lg),
              ManaVerificationRing(isVerified: false),
            ],
          ),
          const SizedBox(height: ManaSpacing.xl),

          const ManaText('buttons',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          Row(
            children: [
              ElevatedButton(
                  onPressed: () {}, child: const ManaText('collect payment')),
              const SizedBox(width: ManaSpacing.md),
              OutlinedButton(
                  onPressed: () {}, child: const ManaText('view documents')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final String label;
  final Color color;
  const _Swatch(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(12)),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
