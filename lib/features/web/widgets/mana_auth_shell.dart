import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design/components/mana_brand_mark.dart' show kManaAppName, kManaTagline;
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/breakpoints.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/mana_site.dart';
import '../../../shared/translation_service.dart';

/// The front door: what wraps login, registration, OTP, PIN and the two
/// choosers on the web.
///
/// These twelve `/lr-*` routes are the first thing any visitor sees, and they
/// rendered as a bare column on grey — the last of the "it looks like a mobile
/// device screen" surface after the signed-in pages got their navigation.
///
/// THEY GET A PANEL, NOT A RAIL. [ManaWebShell] cannot serve here: every
/// destination in it needs a session, so navigation on a login page is a list
/// of links back to the login page. What a signed-out page needs instead is to
/// say what the product is and give the form somewhere to sit.
///
/// TWO PANELS ONLY AT DESK WIDTH. Below [ManaBreakpoints.expanded] the brand
/// panel would steal room from the form rather than frame it, so it collapses
/// and the page becomes the form on a branded background. Below
/// [ManaBreakpoints.compact] this does nothing at all — a phone browser is
/// already the width these screens were drawn for.
///
/// THE SCREENS KEEP THEIR OWN HEADINGS. Several already draw the wordmark and
/// a title (LR-002's "MANA LINE / EVERY ₹ COUNTS" above "Choose Workspace"),
/// so this adds no masthead above them — it would be the same words twice,
/// stacked. The brand panel sits BESIDE the form, where saying the name again
/// reads as letterhead rather than as a stutter.
class ManaAuthShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const ManaAuthShell({super.key, required this.child, required this.location});

  /// How wide the form column may get.
  ///
  /// The choosers are lists of cards and want more room than a text field
  /// does; a workspace card squeezed to 420px wraps its subtitle onto three
  /// lines for no reason. Everything else is a form, and a form wider than
  /// about 460 stops reading as one.
  static const _wideForms = {'/lr-002', '/lr-012', '/lr-013', '/lr-006'};

  double _formMeasure() => _wideForms.contains(location) ? 620 : 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider);
    final width = MediaQuery.sizeOf(context).width;

    if (width < ManaBreakpoints.compact) return child;

    // LR-001 IS NOT A PAGE, it is the two seconds before one. It runs health
    // checks and navigates away on its own, with nothing to read and nothing
    // to fill in. Framing it would put a brand panel beside a spinner and
    // then tear both down.
    if (location == '/lr-001') return child;

    final form = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _formMeasure()),
        child: child,
      ),
    );

    if (width < ManaBreakpoints.expanded) {
      return ColoredBox(color: ManaColors.surfaceMuted, child: form);
    }

    return Scaffold(
      backgroundColor: ManaColors.surfaceMuted,
      body: Row(
        children: [
          // 5:7. The panel is the smaller half deliberately — it is
          // letterhead, and the thing somebody came here to do is on the
          // right.
          const Expanded(flex: 5, child: _BrandPanel()),
          Expanded(flex: 7, child: form),
        ],
      ),
    );
  }
}

class _BrandPanel extends ConsumerWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: BoxDecoration(
        // The brand's own two blues, in the direction the logo's gradient
        // runs. Flat brand colour at this size reads as a swatch; the
        // gradient is what the mark itself does.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [ManaColors.brand, ManaColors.brandDeep],
        ),
      ),
      child: Stack(
        children: [
          // The mark, very large and mostly off the bottom edge. A logo
          // centred in a coloured panel is a sticker; one that bleeds past
          // the edge is a background.
          Positioned(
            left: -80,
            bottom: -140,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 520,
                  height: 520,
                  // Same reasoning as the rail's mark: hand the decoder the
                  // size it will be drawn at rather than scaling 1024px on
                  // the GPU every frame.
                  cacheWidth: 520 * 2,
                  cacheHeight: 520 * 2,
                  filterQuality: FilterQuality.high,
                  // A missing asset must never take a LOGIN page down.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(ManaSpacing.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ManaText.raw(
                  kManaAppName,
                  style: ManaType.sheetTitle.copyWith(
                    color: ManaColors.textOnDark,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                  kManaTagline,
                  style: ManaType.note.copyWith(
                    color: ManaColors.textOnDark,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: ManaSpacing.xl),
                // The one sentence. The marketing site does the selling;
                // somebody here has already decided.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: ManaText.raw(
                    ref.t('auth_panel_lead'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: ManaColors.textOnDark, height: 1.35),
                  ),
                ),
                const SizedBox(height: ManaSpacing.xl),
                // The way back to the public site, because this page is
                // reachable by typing the address and somebody who lands
                // here without an account needs somewhere that is not a
                // login form.
                TextButton(
                  onPressed: () async {
                    // The site this build was deployed with — see
                    // mana_site.dart. Hardcoding the intended
                    // domain here put a dead link on the live
                    // sign-in page.
                    final uri = Uri.parse(manaSiteUrl);
                    try {
                      await launchUrl(uri, mode: LaunchMode.platformDefault);
                    } catch (_) {
                      // A browser that refuses to open its own origin is not
                      // a case worth a dialog on a login page.
                    }
                  },
                  child: ManaText.raw(
                    ref.t('auth_panel_site_link'),
                    style: TextStyle(
                      color: ManaColors.textOnDark,
                      decoration: TextDecoration.underline,
                      decorationColor: ManaColors.textOnDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
