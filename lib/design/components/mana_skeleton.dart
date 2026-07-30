/// Loading placeholders that mirror the shape of the content they stand in
/// for, instead of a spinner on an empty screen.
///
/// WHY THIS EXISTS: 52 screens showed a bare centred
/// `CircularProgressIndicator` while loading. A spinner on a blank field is
/// the strongest "this app is slow" signal there is — it communicates
/// "nothing is here" and gives the eye nothing to settle on, so the same
/// 300ms feels markedly longer than the same wait behind a skeleton that
/// already shows the page's structure. It also causes a layout jump when the
/// real content replaces it, because the spinner's size has nothing to do
/// with the content's.
///
/// Deliberately no `shimmer` package dependency — the effect is a single
/// animated gradient sweep, about 40 lines, and not worth another dependency
/// to maintain and keep version-compatible.
///
/// Uses ManaColors tokens throughout, so it follows the palette rather than
/// hardcoding greys that would drift the moment the brand colours change.
library;

import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// Drives one shared sweep animation for every skeleton beneath it, so a
/// screenful of placeholders pulses in unison rather than each running its own
/// unsynchronised controller (which reads as noise, and costs one ticker per
/// placeholder).
///
/// Wrap the loading branch of a screen in this once. [ManaSkeleton] falls back
/// to a plain static block when no [ManaSkeletonGroup] is above it, so a
/// forgotten wrapper degrades to something still perfectly usable rather than
/// throwing.
class ManaSkeletonGroup extends StatefulWidget {
  final Widget child;
  const ManaSkeletonGroup({super.key, required this.child});

  @override
  State<ManaSkeletonGroup> createState() => _ManaSkeletonGroupState();
}

class _ManaSkeletonGroupState extends State<ManaSkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Stop the ticker entirely under reduce-motion rather than just ignoring
    // its value downstream — a repeating controller still schedules a frame
    // every vsync, which is wasted battery on the low-end phones this app
    // targets.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }

    // Screen readers otherwise find a screenful of decorative boxes and
    // announce nothing useful. One "Loading" label for the whole group, with
    // the placeholders themselves excluded from the tree.
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: _SkeletonTicker(
          animation: _controller,
          child: widget.child,
        ),
      ),
    );
  }
}

class _SkeletonTicker extends InheritedWidget {
  final Animation<double> animation;
  const _SkeletonTicker({required this.animation, required super.child});

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonTicker>()?.animation;

  @override
  bool updateShouldNotify(_SkeletonTicker oldWidget) => animation != oldWidget.animation;
}

/// A single placeholder block. Give it the size the real content will occupy —
/// matching it closely is the whole point, since that's what removes the
/// layout jump when data arrives.
class ManaSkeleton extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const ManaSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = ManaRadius.sm,
    this.margin,
  });

  /// Circular placeholder — avatars, logos, icon slots.
  const ManaSkeleton.circle({super.key, required double size, this.margin})
      : width = size,
        height = size,
        radius = ManaRadius.ring;

  /// A text line. [widthFactor] lets a paragraph of lines have believable
  /// ragged ends rather than a suspiciously uniform block.
  const ManaSkeleton.text({super.key, this.width, this.margin})
      : height = 12,
        radius = ManaRadius.sm;

  @override
  Widget build(BuildContext context) {
    final animation = _SkeletonTicker.maybeOf(context);

    // ACCESSIBILITY: honour the OS "reduce motion" setting. A repeating sweep
    // is exactly the kind of looping animation that triggers discomfort for
    // people with vestibular sensitivity, and on a low-end phone it also burns
    // frames for a purely decorative effect. The static block still reads as
    // a placeholder, so nothing is lost but the shimmer.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final block = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: ManaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    // No group above us: render the static block. Still a better loading
    // affordance than a spinner, and never throws for a missing ancestor.
    if (animation == null || reduceMotion) return block;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Sweep runs from off-screen left to off-screen right so the
        // highlight enters and leaves rather than appearing mid-block.
        final t = animation.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.0 - 2.0 * (1 - t), 0),
            end: Alignment(1.0 - 2.0 * (1 - t), 0),
            colors: const [
              ManaColors.surfaceSunken,
              ManaColors.inkFaint,
              ManaColors.surfaceSunken,
            ],
            stops: const [0.35, 0.5, 0.65],
          ).createShader(bounds),
          child: block,
        );
      },
    );
  }
}

/// Card-shaped placeholder matching the app's `Card` theme (same radius and
/// divider border), for the many screens that render a vertical list of cards.
class ManaSkeletonCard extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry margin;

  const ManaSkeletonCard({
    super.key,
    this.height = 76,
    this.margin = const EdgeInsets.only(bottom: ManaSpacing.sm),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.surface,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        border: Border.all(color: ManaColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(child: ManaSkeleton(height: 13)),
              SizedBox(width: ManaSpacing.lg),
              ManaSkeleton(width: 64, height: 13),
            ],
          ),
          SizedBox(height: ManaSpacing.sm),
          ManaSkeleton(width: 120, height: 10),
        ],
      ),
    );
  }
}

/// The list-of-cards case, which is most list screens in this app.
class ManaSkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;

  const ManaSkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 76,
    this.padding = const EdgeInsets.all(ManaSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return ManaSkeletonGroup(
      child: ListView(
        padding: padding,
        // Placeholders must never intercept a pull-to-refresh or scroll
        // gesture the real list would have handled.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < itemCount; i++) ManaSkeletonCard(height: itemHeight),
        ],
      ),
    );
  }
}
