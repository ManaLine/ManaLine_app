/// The Notifications entry point, for every workspace's header.
///
/// Lives in shared/ rather than design/ because it reads the inbox provider,
/// and the design layer must not depend on app state — a component library
/// that knows about membership requests is no longer a component library.
///
/// Built on ManaHeaderAction so it looks and reads exactly like the other
/// header actions (same tooltip/semantics handling, same badge treatment)
/// rather than being a raw IconButton sitting oddly beside them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/components/mana_header.dart';
import 'inbox_state.dart';
import 'translation_service.dart';

class ManaNotificationBell extends ConsumerStatefulWidget {
  const ManaNotificationBell({super.key});

  @override
  ConsumerState<ManaNotificationBell> createState() => _ManaNotificationBellState();
}

class _ManaNotificationBellState extends ConsumerState<ManaNotificationBell> {
  @override
  void initState() {
    super.initState();
    // Loads once per dashboard mount rather than polling. The count is a
    // prompt to look, not a live figure, and a timer on four dashboards would
    // be four repeating queries on a handset that is often on mobile data.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(inboxProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);

    return ManaHeaderAction(
      icon: Icons.notifications_outlined,
      label: ref.t('notifications'),
      // Badges the ACTION count, not unread notices. An unread informational
      // message is not something anyone has to do, and badging both trains
      // people to ignore the badge.
      badgeCount: state.actionCount,
      // Refresh on return: a decision made in the inbox changes this count.
      onPressed: () => context
          .push('/notifications')
          .then((_) => ref.read(inboxProvider.notifier).load()),
    );
  }
}
