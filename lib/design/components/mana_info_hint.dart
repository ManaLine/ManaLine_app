import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import 'mana_text.dart';

/// A small circled "i" that reveals its explanation on tap.
///
/// Replaces `helperText`, which printed the explanation under every field
/// whether or not anyone needed it. Two reasons that was worth changing:
/// a form of eight fields became eight labels and eight paragraphs, and at a
/// 2.0x text scale the helper lines were most of the screen — this project's
/// recurring overflow class is a form that fits at 1.0x and does not at 2.0x.
///
/// The text is not thrown away, only folded: it is one tap from the field it
/// belongs to, and the dialog is the same shape as the glossary popup in
/// [ManaInfoWord] so the two read as one idea rather than two.
class ManaInfoHint extends StatelessWidget {
  /// The explanation. Already translated by the caller — this widget does no
  /// lookup of its own, so it works for a `ref.t(...)` string and a literal
  /// alike.
  final String message;

  /// Shown as the dialog's heading. Defaults to the field's own label when the
  /// caller passes one, so the popup says what it is explaining.
  final String? title;

  const ManaInfoHint(this.message, {super.key, this.title});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.info_outline, size: 18, color: ManaColors.textSecondary),
      // A 18px glyph is below the 48dp minimum on its own; the button keeps
      // the tap target even though the icon is deliberately quiet.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      tooltip: message,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: title == null ? null : ManaText.raw(title!),
          content: ManaText.raw(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const ManaText('ok'),
            ),
          ],
        ),
      ),
    );
  }
}
