import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// The business's mark, as it appears in every workspace header.
///
/// WHY THIS IS SHARED: it was written once, inline, in the Owner's dashboard,
/// and nowhere else. The Agent and Investor headers passed no `leading` at
/// all, so the same business showed its logo to its Owner and a blank square
/// to everybody else working in it. Copying twenty lines into two more files
/// would have made that three places to keep in step; this is one.
///
/// Every rule the Owner's copy had earned is kept:
///
///  * **Cached.** The header rebuilds on every visit and the logo does not
///    change between them.
///  * **A missing logo is a storefront glyph, not an empty box.** Most
///    businesses have not uploaded one.
///  * **A broken URL is also the glyph.** These are signed storage URLs and
///    they can expire or 404 — a broken-image icon in the header of every
///    screen is much worse than a placeholder.
class ManaBusinessLogo extends StatelessWidget {
  /// Signed storage URL, or null when the business has no logo.
  final String? logoUrl;

  const ManaBusinessLogo({super.key, required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(Icons.storefront, color: ManaColors.brandDeep);
    return Container(
      color: ManaColors.brandFaint,
      child: logoUrl == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: logoUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}
