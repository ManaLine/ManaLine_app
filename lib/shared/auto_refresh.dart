import 'dart:async';

import 'package:flutter/material.dart';

/// M7 — silent auto-refresh for dashboards.
///
/// Wraps a dashboard's content and re-runs [onRefresh] every [interval]
/// while this widget is the TOPMOST route (a dashboard buried under a pushed
/// detail screen stops polling — there is no point re-fetching a screen
/// nobody is looking at). Pull-to-refresh still works: the dashboard's own
/// RefreshIndicator wraps this, and its onRefresh is the same callback.
///
/// Used by the Owner, Agent and Customer dashboards (OW-001 / AG-001 /
/// CW-001) so a figure an agent enters elsewhere on the device shows up on
/// the home screen without the user having to pull.
class AutoRefresh extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Duration interval;

  const AutoRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.interval = const Duration(seconds: 30),
  });

  @override
  State<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends State<AutoRefresh> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant AutoRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      // Not the visible screen (e.g. the user pushed into Collection Mode) —
      // skip this tick instead of re-fetching a screen that is off-screen.
      if (route != null && !route.isCurrent) return;
      widget.onRefresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
