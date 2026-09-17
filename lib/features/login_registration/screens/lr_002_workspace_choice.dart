import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_logo_backdrop.dart';
import '../../../design/components/mana_brand_mark.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/translation_service.dart';


/// LR-002 — root product picker. V1 ships MLF (Mana Finance) only;
/// MLC (Mana Chits) is visible-but-disabled to establish brand presence.
class WorkspaceChoiceScreen extends ConsumerWidget {
  const WorkspaceChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider); // triggers cache load, rebuilds when ready

    return Scaffold(
      // THE LOGO IS THE BACKGROUND NOW, not a 44dp square beside the
      // wordmark. At that size on a 360dp bar it was a smudge competing with
      // the one word it was meant to support; the splash already showed it
      // the right way -- large and centred -- and the two agree now.
      body: ManaLogoBackdrop(
        child: SafeArea(
        child: Column(
          children: [
            // THE BRAND IS A HEADER NOW, not the first thing you scroll past.
            //
            // This screen spent its top half on a 72px logo, a headline name,
            // a tagline and two xxl gaps, and then asked the question it
            // exists to ask below the fold. On a 360x640 handset the two
            // product cards -- the only two controls on the screen -- were
            // reached by scrolling. Reported from a handset as exactly that.
            //
            // ManaBrandMark(horizontal: true) already existed for this, with
            // a doc saying what it is for: "for a header that is pinned above
            // a scrolling form ... it costs one row and the logo stops
            // sliding away". This screen had a hand-rolled copy of the stacked
            // mark instead, which is why it never got the header version.
            // Deleting the copy also ends the drift it was already in: its
            // name was headlineMedium in ManaColors.brand, the shared mark's
            // is 20sp w800 in brandDeep.
            //
            // The long-press admin gate comes with it. The admin panel has no
            // other entry point in the app, it is deliberately not
            // discoverable, and the username/password screen behind it is the
            // real gate -- so the only requirement is that the gesture keeps
            // a target, not that the target keeps its old size.
            GestureDetector(
              onLongPress: () => context.push('/admin-login'),
              // Opaque, so the long press lands on the whole header band
              // rather than only on the glyphs inside it.
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md,
                    ManaSpacing.lg, ManaSpacing.md),
                // logoSize: 0 -- the component's own documented way to
                // show "the wordmark alone", which is what a header wants
                // once the mark itself is behind the page.
                child: ManaBrandMark(horizontal: true, logoSize: 0),
              ),
            ),
            const Divider(height: 1),
            // STILL SCROLLABLE, because fitting is not the same as being
            // guaranteed to fit. At 2.0x text in landscape these two cards
            // plus their heading are taller than the viewport, and the
            // comment this replaces records what a fixed-height Column did
            // the last time: overflowed by 41px on a real handset. It simply
            // has nothing to scroll at any ordinary size now.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ManaText.raw(ref.t('choose_workspace'),
                        style: ManaType.strong),
                    const SizedBox(height: ManaSpacing.md),
                    _ProductCard(
                      code: 'MLF',
                      name: 'Mana Finance',
                      enabled: true,
                      // Straight to the login screen. LR-003 ("Already
                      // registered? Login / Register") used to sit here and
                      // has been deleted: it asked a question the app can
                      // answer itself. LR-009 shows the PIN pad when this
                      // device has a PIN and the password form when it does
                      // not, and Register is a button on that form -- so the
                      // choice screen was a tap that told us nothing.
                      onTap: () => context.push('/lr-009'),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    _ProductCard(
                      code: 'MLC',
                      name: 'Mana Cheeti',
                      enabled: false,
                      badge: ref.t('coming_soon'),
                      onTap: () => _showComingSoon(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw(ref.t('mana_chits_coming_soon'), textAlign: TextAlign.center),
            const SizedBox(height: ManaSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: ManaText.raw(ref.t('close')),
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
                  backgroundColor: enabled ? ManaColors.brandFaint : ManaColors.surfaceSunken,
                  child: ManaText.raw(code, style: ManaType.strong),
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
                if (enabled) Icon(Icons.chevron_right, color: ManaColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
