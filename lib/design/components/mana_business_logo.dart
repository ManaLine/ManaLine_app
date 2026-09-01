import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../shared/stored_file.dart';
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
///  * **A broken or unsigned URL is also the glyph.** The column holds an
///    object path; the link is minted on demand and expires in minutes, so it
///    can be absent, in flight, or 404. A broken-image icon in the header of
///    every screen is much worse than a placeholder.
class ManaBusinessLogo extends StatefulWidget {
  /// What `businesses.logo_url` holds: an object path, or — on rows written
  /// before that changed — a full signed URL. ManaStoredFile reads both.
  final String? logoUrl;

  const ManaBusinessLogo({super.key, required this.logoUrl});

  @override
  State<ManaBusinessLogo> createState() => _ManaBusinessLogoState();
}

/// Stateful, not a FutureBuilder on a future built in build().
///
/// The link has to be minted asynchronously now, and this widget sits in a
/// header that rebuilds constantly. A `future:` created inline is a NEW future
/// every rebuild, which restarts the builder and flashes the placeholder on
/// every frame of a scroll. Resolved once here, and again only when the row
/// itself changes.
class _ManaBusinessLogoState extends State<ManaBusinessLogo> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ManaBusinessLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl) _resolve();
  }

  Future<void> _resolve() async {
    final url = await ManaStoredFile.signedUrl(
        bucket: 'business-logos', stored: widget.logoUrl);
    if (mounted) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Icon(Icons.storefront, color: ManaColors.brandDeep);
    final url = _url;
    return Container(
      color: ManaColors.brandFaint,
      child: url == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => placeholder,
            ),
    );
  }
}
