/// The app's identity block: logo, name, tagline.
///
/// One component because it appears on both the workspace chooser and the
/// login screen, and those two must not drift into showing the brand two
/// different ways. The name and tagline are deliberately NOT translated —
/// "MANA LINE" and "EVERY ₹ COUNTS" are the brand, and a brand that changes
/// wording per language is not a brand.
library;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_text.dart';

/// The registered app name. Never translated, never title-cased by ManaText.
const String kManaAppName = 'MANA LINE';

/// The tagline. Rupee sign is part of it, not decoration.
const String kManaTagline = 'EVERY ₹ COUNTS';

class ManaBrandMark extends StatelessWidget {
  /// Logo edge length. 0 hides the logo and shows the wordmark alone, for
  /// screens too short to afford it.
  final double logoSize;

  /// Larger name for a screen the brand is the point of.
  final bool prominent;

  /// Logo on the LEFT with the name and tagline centred beside it, rather
  /// than stacked above them.
  ///
  /// For a header that is pinned above a scrolling form: stacked, the mark is
  /// tall enough that pinning it would eat the screen a login form needs.
  /// Laid out sideways it costs one row and the logo stops sliding away.
  final bool horizontal;

  const ManaBrandMark({
    super.key,
    this.logoSize = 56,
    this.prominent = false,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return Row(
        children: [
          if (logoSize > 0) ...[
            Image.asset(
              'assets/images/logo.png',
              height: logoSize,
              width: logoSize,
              cacheWidth: (logoSize * 3).round(),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const SizedBox(width: ManaSpacing.sm),
          ],
          // Expanded, and the words inside it centre themselves. A Row with a
          // fixed-size image beside an unflexible Column is this codebase's
          // recurring overflow shape -- the image takes its natural width
          // first and the text has nowhere to go. The flexible child absorbs
          // instead, and the name and tagline stay centred in what is left.
          Expanded(child: _words(centred: true)),
          // Balances the logo so the words are centred on the SCREEN rather
          // than on the space beside the logo.
          if (logoSize > 0) SizedBox(width: logoSize + ManaSpacing.sm),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logoSize > 0) ...[
          // errorBuilder, not a bare Image.asset: a missing logo must not
          // take the login screen down with it. The wordmark below still
          // identifies the app.
          Image.asset(
            'assets/images/logo.png',
            height: logoSize,
            width: logoSize,
            // 1024x1024 source. Decoding at display size instead of holding a
            // full-res bitmap matters on the cheap Androids this targets.
            cacheWidth: (logoSize * 3).round(),
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          const SizedBox(height: ManaSpacing.sm),
        ],
        _words(centred: false),
      ],
    );
  }

  /// The name over its tagline, shared by both layouts so they cannot drift.
  Widget _words({required bool centred}) => Column(
        mainAxisSize: MainAxisSize.min,
        // Centred in both layouts. The parameter is kept because the caller
        // reads better for having said which it wanted, not because the two
        // branches differ today.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ManaText.raw(
            kManaAppName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: prominent ? 26 : 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: ManaColors.brandDeep,
            ),
          ),
          const SizedBox(height: 2),
          ManaText.raw(
            kManaTagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: prominent ? 13 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.0,
              color: ManaColors.textSecondary,
            ),
          ),
        ],
      );
}
