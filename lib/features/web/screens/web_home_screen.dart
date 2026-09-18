import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mana_motion.dart';
import '../state/web_destinations.dart';
import '../../../design/components/mana_form_grid.dart';
import '../../../design/components/mana_header.dart';
import '../../../design/components/mana_logo_backdrop.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/breakpoints.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/translation_service.dart';

/// The web home — first thing a signed-in person sees on the site, and
/// nowhere else. Plan 3a removed the four workspace dashboards from the
/// web build (collections, loans, day closure, reports all happen on the
/// handset), which leaves this as the one screen that has to answer "I'm
/// signed in, now what" without becoming a smaller copy of what was cut.
///
/// So: destinations and words only, gated by role, never a figure — see
/// [_Destination] and the "no digits" test this screen is pinned by.
///
/// ALSO: the first production consumer of [ManaAdaptiveShell]. Every other
/// screen still renders its own bottom nav or drawer; this one exists
/// entirely on the web, so it is the natural place for the rail-at-desk-
/// width shell to prove itself before anything else adopts it.
class ManaWebHomeScreen extends ConsumerWidget {
  const ManaWebHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);
    final destinations = manaWebDestinations(manaWebRole(ref), ref);

    // NO SHELL HERE ANY MORE. This screen used to build its own
    // ManaAdaptiveShell, which is why the rail existed on this page and
    // nowhere else. web_router's ShellRoute now wraps all twenty-one
    // signed-in routes in it, so wrapping again here would draw two rails.
    return Scaffold(
      body: ManaLogoBackdrop(
        alignment: Alignment.bottomRight,
        extent: 0.55,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              ManaBreakpoints.of(MediaQuery.sizeOf(context).width) == ManaWidthClass.expanded
                  ? ManaSpacing.xxl
                  : ManaSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('welcome_back'),
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: ManaSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ManaText.raw(ref.t('web_home_lead'), style: ManaType.secondary),
                ),
                const SizedBox(height: ManaSpacing.xl),
                ManaFormGrid(
                  columnsAtMedium: 2,
                  columnsAtExpanded: 3,
                  children: [
                    // Staggered in, and lifting under the pointer. The index
                    // is the card's position in the grid, so the page
                    // assembles left to right rather than all at once.
                    for (final (i, d) in destinations.indexed)
                      _DestinationCard(
                        d,
                        index: i,
                        onTap: () {
                          final route = d.route;
                          if (route != null) {
                            context.push(route);
                          } else {
                            d.onTap?.call();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final ManaWebDestination destination;
  final VoidCallback onTap;
  final int index;
  const _DestinationCard(this.destination, {required this.onTap, this.index = 0});

  @override
  Widget build(BuildContext context) {
    final d = destination;
    final borderColor = d.isPrimary ? ManaColors.brand : ManaColors.divider;
    return ManaEntrance(
      index: index,
      child: ManaHoverLift(
        child: _body(context, d, borderColor),
      ),
    );
  }

  Widget _body(BuildContext context, ManaWebDestination d, Color borderColor) {
    return Material(
      color: d.isPrimary ? ManaColors.brandFaint : ManaColors.surface,
      borderRadius: BorderRadius.circular(ManaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: kManaMinTapTarget),
          padding: const EdgeInsets.all(ManaSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ManaRadius.md),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.icon, color: d.isPrimary ? ManaColors.brandDeep : ManaColors.textSecondary),
              const SizedBox(height: ManaSpacing.sm),
              // .raw, not title-cased: d.title is already a translated string
              // straight from ui_translations (same reasoning as ManaAppBar's
              // own title, which is .raw for the same reason) — re-casing it
              // in code would mangle "Pre-Existing Business" into
              // "Pre-existing Business" the moment ManaText's algorithm hits
              // the hyphen.
              ManaText.raw(
                d.title,
                style: d.isPrimary
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.titleMedium,
              ),
              if (d.body != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(d.body!, style: ManaType.note),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
