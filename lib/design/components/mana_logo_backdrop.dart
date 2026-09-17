import 'package:flutter/material.dart';

/// The logo, large and quiet, behind a screen rather than beside its name.
///
/// THE OWNER'S INSTRUCTION: "remove app logo beside app name & add logo to
/// screen space as background and fit to screen (as shown in center while app
/// start up) in center large logo with visible opacity."
///
/// WHAT IT REPLACES. The logo was a 44dp square sitting next to the wordmark
/// on two pre-login screens, which is the shape of a favicon rather than of a
/// brand: at that size on a 360dp bar it is a smudge competing with the one
/// word it is meant to support. The splash already shows it the right way --
/// large and centred -- and this brings the two into agreement.
///
/// WHY AN OPACITY AND NOT A FULL-STRENGTH IMAGE. Everything on these screens
/// is read: a product name, a choice of two, a PIN pad. The logo behind them
/// must be present and must never be the thing the eye lands on, and it must
/// not eat the contrast of the text over it -- these are screens somebody
/// uses in a field in daylight, where a busy background is what turns legible
/// text into grey on grey.
///
/// [kManaBackdropOpacity] is low enough for that and high enough to be seen,
/// and it is a named constant because it is the sort of number that gets
/// nudged by whoever is looking at it on a bright desk monitor.
class ManaLogoBackdrop extends StatelessWidget {
  final Widget child;

  /// Fraction of the SHORTER screen edge the logo spans.
  ///
  /// Shorter, not the width: on a landscape handset the height is what runs
  /// out first, and sizing to width there would push the mark off both ends.
  final double extent;

  const ManaLogoBackdrop({
    super.key,
    required this.child,
    this.extent = 0.72,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final edge = (size.width < size.height ? size.width : size.height) * extent;

    return Stack(
      children: [
        // IgnorePointer, because a decoration must not take a tap. Without it
        // the Stack's first child would swallow gestures over most of the
        // screen -- including, on the workspace chooser, the two cards that
        // are the only controls on it.
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: kManaBackdropOpacity,
                child: Image.asset(
                  'assets/images/logo.png',
                  width: edge,
                  height: edge,
                  // Decoded at display size rather than held at 1024 square.
                  // This is a cheap-Android target and the backdrop is the
                  // largest image the app draws.
                  cacheWidth: (edge * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                  fit: BoxFit.contain,
                  // errorBuilder, not a bare Image.asset: a missing logo must
                  // not take a login screen down with it. The wordmark still
                  // identifies the app.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// How strongly the backdrop logo shows through.
///
/// Visible, and never competing with the text over it. Named rather than
/// inlined because it is exactly the sort of number somebody raises while
/// looking at a bright desk monitor, and the screens it belongs to are read
/// in a field in daylight.
const double kManaBackdropOpacity = 0.06;
