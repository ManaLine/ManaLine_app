import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/inbox_service.dart';
import 'package:mana_line/shared/inbox_state.dart';
import 'package:mana_line/shared/notifications_screen.dart';

import 'support/mana_harness.dart';

/// A notice you cannot do anything with.
///
/// The tile carried exactly one gesture -- tap to mark read -- and that tap
/// was null once the notice HAD been read. So the only control on the screen
/// stopped working the moment it had been used, the list only ever grew, and
/// long-pressing (which is what people were trying) did nothing at all.
class _SeededInbox extends InboxNotifier {
  _SeededInbox(this._seed);
  final InboxState _seed;

  static final dismissed = <String>[];

  @override
  InboxState build() => _seed;

  @override
  Future<void> load() async {}

  @override
  Future<void> markRead(String id) async {}

  @override
  Future<void> dismiss(String id) async {
    dismissed.add(id);
    state = state.copyWith(
      notices: [for (final n in state.notices) if (n.id != id) n],
    );
  }
}

InboxNotice _notice({required String id, required bool isRead}) => InboxNotice(
      id: id,
      type: 'Other',
      message: 'Agent submitted an account for approval',
      isRead: isRead,
      createdAt: DateTime(2026, 8, 30, 20, 49),
    );

void main() {
  setUp(_SeededInbox.dismissed.clear);

  InboxState seeded() => InboxState(
        loading: false,
        notices: [
          _notice(id: 'n-unread', isRead: false),
          _notice(id: 'n-read', isRead: true),
        ],
      );

  testWidgets('a read notice is still tappable', (tester) async {
    await pumpManaScreen(
      tester,
      const NotificationsScreen(),
      overrides: [inboxProvider.overrideWith(() => _SeededInbox(seeded()))],
    );

    // Both of them. `onTap: notice.isRead ? null : ...` is what made the
    // screen go inert after one use.
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
      expect(tile.onTap, isNotNull,
          reason: 'every notice must stay openable after it has been read');
      expect(tile.onLongPress, isNotNull,
          reason: 'long press is where people reach for View / Ignore');
    }
  });

  testWidgets('long press offers View and Ignore', (tester) async {
    await pumpManaScreen(
      tester,
      const NotificationsScreen(),
      overrides: [inboxProvider.overrideWith(() => _SeededInbox(seeded()))],
    );

    await tester.longPress(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('View'), findsOneWidget);
    expect(find.text('Ignore'), findsOneWidget);
    // Says plainly that nothing is destroyed, because that is what decides
    // whether somebody is willing to press it.
    expect(find.textContaining('Nothing is deleted'), findsOneWidget);
  });

  testWidgets('Ignore puts that notice away and leaves the other',
      (tester) async {
    await pumpManaScreen(
      tester,
      const NotificationsScreen(),
      overrides: [inboxProvider.overrideWith(() => _SeededInbox(seeded()))],
    );

    expect(find.byType(ListTile), findsNWidgets(2));

    await tester.longPress(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore'));
    await tester.pumpAndSettle();

    expect(_SeededInbox.dismissed, ['n-unread']);
    expect(find.byType(ListTile), findsOneWidget,
        reason: 'the notice that was put away is gone, the other one stays');
  });

  testWidgets('tapping opens the full message', (tester) async {
    // The tile clips at three lines, so a long notice could not be read at
    // all before this.
    await pumpManaScreen(
      tester,
      const NotificationsScreen(),
      overrides: [inboxProvider.overrideWith(() => _SeededInbox(seeded()))],
    );

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
