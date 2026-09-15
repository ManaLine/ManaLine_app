import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mana_outbox_provider.dart';

/// Sends what is waiting, without anybody asking it to.
///
/// "Queue it until live" is only true if something notices when live happens.
/// Without this the queue fills and sits there until an agent thinks to open
/// the outbox and press retry -- which is a worse promise than the one that
/// was made.
///
/// TWO TRIGGERS, deliberately both:
///
///   * RESUME. The commonest real sequence is the phone going in a pocket in a
///     village and coming out in a place with a signal. Foreground is the
///     moment most likely to be different from the last one.
///
///   * A TIMER while foregrounded. A collection recorded while standing still,
///     on a cell that comes back thirty seconds later, would otherwise wait
///     for an app switch that may not come for an hour.
///
/// NO CONNECTIVITY PACKAGE. A connectivity plugin reports whether an interface
/// is up, which on a village cell is not the same question as whether a
/// request will complete -- the captive-portal and dying-cell cases that
/// kManaQueryTimeout exists for both report "connected". Trying is the only
/// honest test, it costs one request that fails fast, and a failure is already
/// handled: the entry goes back in the queue under the same key.
class ManaOutboxWatcher extends ConsumerStatefulWidget {
  final Widget child;

  /// How often to try while the app is in the foreground.
  ///
  /// Sixty seconds against ManaOutbox.attemptsBeforeStuck of 3 means an entry
  /// reads "Still trying" after about three minutes of no signal. For gaps
  /// described as "a few minutes or less", that is the right moment to say
  /// something rather than the wrong one.
  final Duration interval;

  const ManaOutboxWatcher({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 60),
  });

  @override
  ConsumerState<ManaOutboxWatcher> createState() => _ManaOutboxWatcherState();
}

class _ManaOutboxWatcherState extends ConsumerState<ManaOutboxWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _flush());
    // Once at startup too: the app may have been killed with collections
    // waiting, which is the case the on-disk queue exists for.
    WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }

  void _flush() {
    // Not awaited and never surfaced. This is background work: an agent
    // filling in a collection must not be interrupted by a queue draining
    // behind them, and ManaOutbox.flush already refuses to run twice at once.
    unawaited(ref.read(manaOutboxProvider).flush());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
