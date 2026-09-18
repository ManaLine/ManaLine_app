import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';

/// The whole motion vocabulary, in one file, so nothing on the site moves in
/// a way nothing else moves.
///
/// WHY SO LITTLE OF IT. This is a lending business's software. The people
/// reading it are deciding whether to trust it with a book that is their
/// livelihood, and the field half of the app is used one-handed in daylight
/// on a cheap handset. Motion here exists to say "that press registered" and
/// "there is more below" — never to perform. Everything is a fade and a few
/// pixels of travel; nothing slides in from off-screen and nothing bounces.
///
/// EVERY ANIMATION IN THIS FILE CHECKS [MediaQuery.disableAnimationsOf].
/// Somebody who has turned animations off at the OS level has often done it
/// because motion makes them ill, and a decorative flourish is exactly the
/// kind that should obey. In that case these widgets return their child
/// untouched — never a frozen half-state.

/// Durations and the curve. Two speeds: one for a response to a pointer, one
/// for something arriving on its own.
class ManaMotion {
  /// A reply to something the person just did. Anything slower than this
  /// stops reading as a response.
  static const fast = Duration(milliseconds: 140);

  /// Something arriving by itself — a card appearing, a section revealing.
  static const slow = Duration(milliseconds: 420);

  /// Decelerating, so a movement arrives rather than stops.
  static const curve = Curves.easeOutCubic;

  const ManaMotion._();
}

/// Lifts a card slightly under the pointer, and pushes it back down on press.
///
/// THE PRESS IS FASTER THAN THE HOVER and travels past where it started. A
/// press that animates at the same speed as a hover reads as the control
/// having ignored the click — the whole job of this is to answer, and an
/// answer that arrives late is not one.
///
/// Pointer-driven, so it does nothing on a touchscreen, which is correct:
/// there is no hover on a handset and the app's own ink splash already
/// answers a tap there.
class ManaHoverLift extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// How far it rises. Small on purpose — this is a surface acknowledging the
  /// pointer, not a card jumping at somebody.
  final double lift;

  const ManaHoverLift({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(ManaRadius.md)),
    this.lift = 3,
  });

  @override
  State<ManaHoverLift> createState() => _ManaHoverLiftState();
}

class _ManaHoverLiftState extends State<ManaHoverLift> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    final offset = _pressed
        ? 0.0
        : _hovered
            ? -widget.lift
            : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: _pressed ? const Duration(milliseconds: 60) : ManaMotion.fast,
          curve: ManaMotion.curve,
          transform: Matrix4.translationValues(0, offset, 0),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: _hovered && !_pressed
                ? [
                    BoxShadow(
                      color: ManaColors.ink.withValues(alpha: 0.13),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and lifts a child in once, on first build.
///
/// [index] staggers a group. CAPPED AT SIX: by the seventh card the stagger
/// has stopped being a flourish and become a wait, and the person is looking
/// at an empty space wondering whether something failed to load.
///
/// Runs ONCE — it is an entrance, not a state. Rebuilding the widget for any
/// other reason (a rail selection, a window resize) must not replay it, which
/// is why the animation lives in a controller started in initState rather
/// than in an implicit animation driven by a field.
class ManaEntrance extends StatefulWidget {
  final Widget child;
  final int index;

  const ManaEntrance({super.key, required this.child, this.index = 0});

  @override
  State<ManaEntrance> createState() => _ManaEntranceState();
}

class _ManaEntranceState extends State<ManaEntrance>
    with SingleTickerProviderStateMixin {
  /// CREATED IN initState, NOT AS A `late final` FIELD INITIALISER.
  ///
  /// With animations disabled nothing ever reads `_c` — build returns the
  /// child and didChangeDependencies returns early — so a lazy field is still
  /// uninitialised when `dispose` calls `_c.dispose()`. That CONSTRUCTS it, at
  /// teardown, and `vsync: this` then looks up an inherited widget from an
  /// element that has already been deactivated:
  ///
  ///     Looking up a deactivated widget's ancestor is unsafe.
  ///
  /// A lazy initialiser whose only reader is dispose() is a trap, and it only
  /// springs on the accessibility path — the one nobody clicks through.
  late final AnimationController _c;

  Timer? _start;
  bool _scheduled = false;

  /// SCHEDULED HERE, NOT IN initState, for two reasons that turned out to be
  /// the same reason.
  ///
  /// `MediaQuery.disableAnimationsOf` cannot be read in initState, so an
  /// earlier version started the stagger timer unconditionally and let
  /// `build` decide whether to show an animation. With animations off that
  /// left a pending timer per card, firing into a controller whose output
  /// nothing renders — a leak that does nothing visible, which is why it
  /// would never have been noticed. `mana_motion_test` caught it as
  /// `!timersPending`.
  ///
  /// A real Timer rather than Future.delayed so dispose can CANCEL it, rather
  /// than letting it fire and checking `mounted` on the way out.
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: ManaMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final delay = Duration(milliseconds: 55 * (widget.index.clamp(0, 6)));
    _start = Timer(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Not merely "no animation" — fully VISIBLE. A reduced-motion setting
    // must never leave content stuck at opacity 0, which is the failure mode
    // of every opacity-based entrance that forgets to check.
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;

    final curved = CurvedAnimation(parent: _c, curve: ManaMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
