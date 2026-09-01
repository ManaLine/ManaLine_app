import 'package:flutter/material.dart';

import '../../shared/stored_file.dart';

/// Resolves what a `*_url` column holds into an [ImageProvider] the caller can
/// hand to a CircleAvatar, a verification ring, or anything else.
///
/// WHY THIS EXISTS: those columns used to hold a signed URL valid for a year,
/// so every display site could write `NetworkImage(value)` and be done. They
/// hold an object path now — see ManaStoredFile — and a path is not a URL, so
/// all thirteen of those call sites would have quietly rendered nothing.
///
/// A builder rather than a finished avatar widget on purpose: the sites differ
/// (CircleAvatar with a fallback letter, ManaVerificationRing, a roster row),
/// and forcing one shape on them would mean rewriting each one's appearance to
/// fix its plumbing. This changes only where the image comes from.
///
/// Resolution is asynchronous and the link is short-lived, so [builder] is
/// called first with null and again once a URL exists. Every call site already
/// handles a null provider — that is what a person with no photo looks like —
/// so the placeholder is the one they already draw.
class ManaStoredImage extends StatefulWidget {
  /// The storage bucket the path lives in.
  final String bucket;

  /// The column value: an object path, or a legacy full signed URL.
  final String? stored;

  final Widget Function(BuildContext context, ImageProvider? image) builder;

  const ManaStoredImage({
    super.key,
    required this.bucket,
    required this.stored,
    required this.builder,
  });

  @override
  State<ManaStoredImage> createState() => _ManaStoredImageState();
}

class _ManaStoredImageState extends State<ManaStoredImage> {
  ImageProvider? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ManaStoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve only when the row actually changed. Rebuilds are constant in
    // headers and rosters; re-signing on each one would hit storage per frame.
    if (oldWidget.stored != widget.stored || oldWidget.bucket != widget.bucket) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = await ManaStoredFile.signedUrl(
        bucket: widget.bucket, stored: widget.stored);
    if (!mounted) return;
    setState(() => _image = url == null ? null : NetworkImage(url));
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _image);
}
