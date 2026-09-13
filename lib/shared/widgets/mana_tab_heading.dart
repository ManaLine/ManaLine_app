import 'package:flutter/material.dart';

import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';

/// The name of the section on screen, with an arrow on each side saying there
/// are more.
///
/// Replaces a scrollable TabBar whose later tabs sat off the right edge with
/// nothing indicating they existed. This draws one label at a time and keeps
/// the TabController driving it, so swiping still works and the index -> enum
/// mapping is untouched.
///
/// SHARED, not copied. The one-by-one migration door needs the same control
/// for its three stages, and a second copy of a paging header is how two
/// screens end up disagreeing about what an arrow means. Its only tie to any
/// screen is DefaultTabController, which both provide.
class ManaTabHeading extends StatefulWidget {
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const ManaTabHeading(
      {super.key, required this.labels, required this.onChanged});

  @override
  State<ManaTabHeading> createState() => _ManaTabHeadingState();
}

class _ManaTabHeadingState extends State<ManaTabHeading> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onTab);
    _controller = controller..addListener(_onTab);
  }

  void _onTab() {
    if (!mounted) return;
    setState(() {});
    // indexIsChanging is true mid-animation; the provider wants the settled
    // index, and reporting both would record a tab nobody stopped on.
    if (!_controller!.indexIsChanging) widget.onChanged(_controller!.index);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTab);
    super.dispose();
  }

  void _step(int by) {
    final c = _controller;
    if (c == null) return;
    final next = c.index + by;
    if (next < 0 || next >= widget.labels.length) return;
    c.animateTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final index = _controller?.index ?? 0;
    final atStart = index == 0;
    final atEnd = index == widget.labels.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.xs),
      child: Row(
        children: [
          // Tappable as well as visible. The arrows are the affordance, but
          // somebody who has noticed them will try pressing them.
          IconButton(
            onPressed: atStart ? null : () => _step(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: atStart ? null : widget.labels[index - 1],
          ),
          // Flexible between two fixed-width buttons -- the shape that does
          // not overflow when a Telugu section name is longer than the gap.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ManaText.raw(
                  widget.labels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: ManaType.cardTitle,
                ),
                const SizedBox(height: 4),
                // Which of five, at a glance. A person who cannot see the
                // labels either side still knows how much is left.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.labels.length; i++)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == index
                              ? ManaColors.brand
                              : ManaColors.textDisabled,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: atEnd ? null : () => _step(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: atEnd ? null : widget.labels[index + 1],
          ),
        ],
      ),
    );
  }
}
