import 'package:flutter/material.dart';

/// Content that centres when it fits and scrolls when it does not.
///
/// A `Column(mainAxisAlignment: center)` inside a Scaffold body cannot grow.
/// It looks right at 1.0x and clips silently at 2.0x -- and what it clips is
/// the bottom, which is where the button is. LR-006 lost 146px that way and
/// LR-008 lost 85px, both at the bottom, both on screens with no other way
/// forward: a PIN pad with no visible Continue, and a registration result
/// whose "I have saved it" confirmation had gone off-screen.
///
/// LR-001 already solved this and carried the fix alone. It is the same three
/// widgets every time -- LayoutBuilder for the viewport height, a scroll view,
/// and a minHeight constraint so the Column still fills and centres when there
/// is room -- so it lives here now instead of being rediscovered per screen.
///
/// Centring is preserved at every scale where the content fits, which on these
/// screens is almost always.
class ManaCenteredScroll extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ManaCenteredScroll({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      );
}
