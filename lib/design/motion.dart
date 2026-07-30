/// Motion tokens and the app's transition language.
///
/// The app had zero animations and zero RepaintBoundary before this, so
/// everything here is deliberate rather than inherited.
///
/// BATTERY IS A HARD CONSTRAINT, NOT A PREFERENCE. These users are on cheap
/// Android phones, often far from a charger, working a full collection round.
/// Four rules follow from that, and every token below obeys them:
///
///  1. ANIMATE ONLY `transform` AND `opacity`. Both are handled by the
///     compositor — the framework can skip layout and paint entirely and just
///     re-composite existing layers. Animating width, height, padding, colour
///     or elevation instead forces a relayout or repaint every single frame,
///     which is where "smooth UI" quietly becomes a battery complaint.
///
///  2. NOTHING LOOPS. Every duration here settles. The one repeating animation
///     in the app (the skeleton shimmer) is bounded by how long a fetch takes
///     and stops dead under reduce-motion. No idle screen should ever be
///     scheduling frames.
///
///  3. SHORT. 180–260ms. Fewer frames is less work, and past roughly 300ms a
///     transition stops reading as responsive and starts reading as lag —
///     which is the opposite of the goal. Speed IS the polish.
///
///  4. REDUCE-MOTION COLLAPSES EVERYTHING TO ZERO, through one function
///     ([ManaMotion.duration]) so it cannot be forgotten per-widget. This
///     serves accessibility and battery at once: no motion means no frames.
library;

import 'package:flutter/material.dart';

class ManaMotion {
  ManaMotion._();

  // --- Durations --------------------------------------------------------

  /// Tap feedback, press states, small state flips. Deliberately near the
  /// threshold of perception — feedback must feel instant, not animated.
  static const fast = Duration(milliseconds: 110);

  /// The default. Content arriving, fades, reveals.
  static const normal = Duration(milliseconds: 180);

  /// Page transitions, sheets — the largest movements in the app.
  static const page = Duration(milliseconds: 240);

  /// Per-item delay when a list staggers in. Small on purpose: 8 items at 30ms
  /// finishes in 240ms, whereas a "nicer looking" 80ms stagger would take
  /// 640ms and make a fast list feel slow.
  static const stagger = Duration(milliseconds: 30);

  /// Cap on how many items stagger. Beyond this they appear together — a long
  /// list otherwise animates items the user has already scrolled past, burning
  /// frames for something nobody sees.
  static const int maxStaggerItems = 8;

  // --- Curves -----------------------------------------------------------

  /// Entrances: fast out of the gate, gentle settle. Standard Material
  /// emphasised-decelerate feel without the overshoot, which on a money screen
  /// reads as imprecision.
  static const enter = Curves.easeOutCubic;

  /// Exits: content leaving should get out of the way quickly.
  static const exit = Curves.easeInCubic;

  /// Two-way state changes that need to feel symmetrical.
  static const standard = Curves.easeInOutCubic;

  // --- The reduce-motion gate -------------------------------------------

  /// Every animated widget in this app takes its duration from here.
  ///
  /// Returns [Duration.zero] when the OS asks for reduced motion, which makes
  /// implicit animations jump straight to their target: no tween, no frames,
  /// no battery. Centralised so a new widget cannot quietly skip the check.
  static Duration duration(BuildContext context, Duration d) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? Duration.zero : d;
  }

  /// True when the OS has asked for reduced motion. Use to skip building an
  /// animated wrapper altogether where that is cheaper than a zero-duration
  /// animation.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// The app's page transition, installed once via
/// `ThemeData.pageTransitionsTheme` rather than per-route.
///
/// WHY THAT MATTERS: there are ~60 routes, all declared with GoRoute's
/// `builder:`, which produces a MaterialPage and therefore honours the theme's
/// PageTransitionsTheme. Setting it centrally means every route gets the same
/// motion — including routes added later, by anyone — without touching the
/// router. Doing it per-route with CustomTransitionPage would have been 60 edits
/// and would drift on the 61st.
///
/// The transition itself: incoming page slides a short distance from the
/// trailing edge while fading, outgoing page fades and slides slightly the
/// other way. Both are transform+opacity only, so no layout or paint work
/// happens per frame. The slide is deliberately short (8% of width, not 100%)
/// — a full-width slide at this speed reads as a jerk, and at a readable speed
/// takes too long.
class ManaPageTransitions extends PageTransitionsBuilder {
  const ManaPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Under reduce-motion, hand back the child untouched. Not a zero-duration
    // animation — no wrapper at all, so there is nothing to composite.
    if (ManaMotion.reduced(context)) return child;

    final enter = CurvedAnimation(parent: animation, curve: ManaMotion.enter);
    final leave = CurvedAnimation(parent: secondaryAnimation, curve: ManaMotion.exit);

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).animate(enter),
      child: FadeTransition(
        opacity: enter,
        // The page being covered drifts slightly away and dims, which is what
        // gives the stack a sense of depth without a shadow to repaint.
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(-0.04, 0),
          ).animate(leave),
          child: child,
        ),
      ),
    );
  }
}

/// Scale-on-press feedback for cards, tiles and rows.
///
/// A ripple tells you *where* you touched; a slight shrink tells you the whole
/// surface is one button and that it registered. On a dusty screen, in
/// sunlight, that physical confirmation matters more than the ripple, which can
/// be nearly invisible outdoors.
///
/// Cost: one `Transform.scale` on a 110ms curve, transform-only, wrapped in a
/// RepaintBoundary so the press cannot dirty its siblings. Nothing animates
/// while idle.
class ManaPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  /// How far it shrinks. 0.97 is enough to feel and small enough not to look
  /// like a bounce.
  final double pressedScale;

  const ManaPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.pressedScale = 0.97,
  });

  @override
  State<ManaPressable> createState() => _ManaPressableState();
}

class _ManaPressableState extends State<ManaPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    Widget content = widget.child;

    if (enabled && !ManaMotion.reduced(context)) {
      content = RepaintBoundary(
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : 1.0,
          duration: ManaMotion.duration(context, ManaMotion.fast),
          curve: ManaMotion.standard,
          child: content,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap,
      child: content,
    );
  }
}

/// Fades and lifts content into place — for the moment real data replaces a
/// skeleton, and for list items on first load.
///
/// Without this, content *pops* in: the skeleton vanishes and the real widget
/// appears in the same frame, which reads as a flicker even when the fetch was
/// fast. A 180ms fade makes the same load feel deliberate. This is most of
/// what "glossy" actually is — not extra movement, but no abrupt edges.
///
/// [index] staggers items in a list. Capped by [ManaMotion.maxStaggerItems] so
/// long lists don't animate rows nobody will see.
class ManaAppear extends StatefulWidget {
  final Widget child;
  final int index;

  /// Vertical lift in logical pixels. Small: a big rise turns a page load into
  /// a performance.
  final double offset;

  const ManaAppear({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 8,
  });

  @override
  State<ManaAppear> createState() => _ManaAppearState();
}

class _ManaAppearState extends State<ManaAppear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ManaMotion.normal,
  );

  bool _started = false;

  // Started here rather than in initState because MediaQuery — and therefore
  // the reduce-motion setting — is not readable from initState. Starting it
  // there meant that under reduce-motion the controller ran anyway: invisible,
  // because build() returns the child directly, but still holding a frame
  // callback open and costing a frame every vsync for 180ms. Precisely the
  // battery cost this widget claims to avoid. Caught by motion_test.dart's
  // transientCallbackCount assertion.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (ManaMotion.reduced(context)) {
      // Jump to the finished state without ever running the ticker. If the OS
      // setting is turned off later, the content stays put instead of
      // re-animating something already on screen.
      _controller.value = 1.0;
      return;
    }

    final steps = widget.index.clamp(0, ManaMotion.maxStaggerItems);
    final delay = ManaMotion.stagger * steps;
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      // A one-shot delayed start, not a repeating timer — nothing is scheduled
      // after the animation completes.
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduce-motion: no wrapper, no controller work, straight to final state.
    if (ManaMotion.reduced(context)) return widget.child;

    final curved = CurvedAnimation(parent: _controller, curve: ManaMotion.enter);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          return Opacity(
            opacity: curved.value,
            child: Transform.translate(
              offset: Offset(0, widget.offset * (1 - curved.value)),
              child: child,
            ),
          );
        },
        // Built once and reused across frames rather than rebuilt per frame —
        // the whole point of AnimatedBuilder's child parameter.
        child: widget.child,
      ),
    );
  }
}
