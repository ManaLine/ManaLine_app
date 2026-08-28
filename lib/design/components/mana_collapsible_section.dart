import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_header.dart' show kManaMinTapTarget;
import 'mana_text.dart';

/// A section of a dashboard that can be put away.
///
/// The Agent's home carried five reference sections open at once -- business
/// status, today's summary, live activity, compensation, workspace
/// information -- which is about four screens of scrolling before the last one
/// is reached. Most of it is looked at once a day, and the parts that are not
/// were below everything that was.
///
/// Collapsed sections still say what they hold: the header keeps a one-line
/// summary, so putting a section away does not mean losing sight of it. A
/// section with nothing to summarise simply shows its name.
class ManaCollapsibleSection extends StatefulWidget {
  /// Already translated.
  final String title;

  /// The one thing worth reading with the section shut — a total, a count.
  /// Optional, and deliberately short.
  final String? summary;

  final Widget child;

  /// Open on arrival. Exactly one section on a dashboard should be, and it
  /// should be the one the day is actually spent in.
  final bool initiallyExpanded;

  /// Draws the title in a warning colour. For a section that is only present
  /// because something needs attention.
  final Color? accent;

  const ManaCollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.summary,
    this.initiallyExpanded = false,
    this.accent,
  });

  @override
  State<ManaCollapsibleSection> createState() => _ManaCollapsibleSectionState();
}

class _ManaCollapsibleSectionState extends State<ManaCollapsibleSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(ManaSpacing.md),
                child: ConstrainedBox(
                  // The whole header row is the target, and it is at least a
                  // thumb tall: this is tapped standing up, one-handed.
                  constraints:
                      const BoxConstraints(minHeight: kManaMinTapTarget),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ManaText.raw(
                              widget.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    widget.accent ?? ManaColors.textPrimary,
                              ),
                            ),
                            // Only when shut. Open, the section says it
                            // itself, and repeating it is a second figure to
                            // reconcile.
                            if (!_open && widget.summary != null)
                              ManaText.raw(
                                widget.summary!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: ManaColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      Icon(_open ? Icons.expand_less : Icons.expand_more,
                          color: ManaColors.textSecondary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.md, 0, ManaSpacing.md, ManaSpacing.md),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
