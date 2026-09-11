import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/inbox_service.dart';
import 'package:mana_line/shared/inbox_state.dart';
import 'package:mana_line/shared/network_error_handler.dart';
import 'package:mana_line/shared/notifications_screen.dart';

import 'support/mana_harness.dart';

/// An Agent accepted an invitation at 11:57 AM and the spinner inside the
/// Accept button never stopped.
///
/// Nothing was wrong with the server: app.respond_to_invitation was invoked
/// directly against the same membership and answered Active. The request had
/// been sent and the reply never arrived, and PostgREST has no client-side
/// deadline of its own, so the await in InboxNotifier.decide never returned --
/// which means the catch that clears busyItemId never ran either. The card
/// stayed disabled with a turning spinner and offered nothing to cancel.
///
/// Two separate defects sat on that one path, and both are pinned here:
///
///   A. NO DEADLINE. Fixed in InboxService, not in the notifier -- a timeout
///      wrapped around decide() would fire on time and leave the inner await
///      pending forever, so the button would go on spinning behind the error.
///
///   B. A FAILED DECISION REPORTED NOWHERE. decide used to swallow the error
///      into state.error, which the screen renders only when BOTH lists are
///      empty. On a populated inbox -- the only way to see an invitation at
///      all -- a failure produced no sentence anywhere on screen.
class _FailingInbox implements InboxService {
  _FailingInbox(this.error, {this.action});

  final Object error;
  final InboxAction? action;

  @override
  Future<List<InboxAction>> pendingActions() async =>
      action == null ? const [] : [action!];

  @override
  Future<List<InboxNotice>> notices({int limit = 100}) async => const [];

  @override
  Future<bool> respondToInvitation({
    required String membershipId,
    required bool accept,
  }) async =>
      throw error;

  @override
  Future<bool> decideRequest({
    required String requestId,
    required bool approve,
    String? rejectionReason,
  }) async =>
      throw error;

  @override
  Future<bool> payOutWithdrawal({required String requestId}) async =>
      throw error;

  @override
  Future<bool> approveSettlement({required String settlementId}) async =>
      throw error;

  @override
  Future<void> markRead(String notificationId) async {}

  @override
  Future<void> dismiss(String notificationId) async {}

  @override
  Future<void> markAllRead() async {}
}

InboxAction _invitation() => InboxAction(
      kind: InboxActionKind.invitation,
      itemId: '4768ca9a',
      businessId: 'b-1',
      businessName: 'SDF',
      role: 'Agent',
      createdAt: DateTime(2026, 9, 4, 11, 57),
    );

void main() {
  group('A -- the spinner comes off', () {
    test('a failed decision clears busyItemId and rethrows', () async {
      final container = ProviderContainer(overrides: [
        inboxServiceProvider.overrideWithValue(
          _FailingInbox(const SocketException('Connection closed')),
        ),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(inboxProvider.notifier);

      await expectLater(
        notifier.decide(_invitation(), yes: true),
        throwsA(isA<SocketException>()),
        reason: 'the failure must reach the caller, which is what words it',
      );

      // The defect itself. A card whose busyItemId is still set is a card
      // with a turning spinner and a disabled button, forever.
      expect(container.read(inboxProvider).busyItemId, isNull,
          reason: 'the Accept button must become usable again');
    });

    test('a timeout is what a hung request turns into', () async {
      // The deadline lives in InboxService, so this asserts the shape the
      // notifier must survive: TimeoutException, like any other failure.
      final container = ProviderContainer(overrides: [
        inboxServiceProvider.overrideWithValue(
          _FailingInbox(TimeoutException('no reply', kManaQueryTimeout)),
        ),
      ]);
      addTearDown(container.dispose);

      await expectLater(
        container.read(inboxProvider.notifier).decide(_invitation(), yes: true),
        throwsA(isA<TimeoutException>()),
      );
      expect(container.read(inboxProvider).busyItemId, isNull);
    });
  });

  group('B -- the failure is visible', () {
    testWidgets('a failed Accept says so on screen', (tester) async {
      await pumpManaScreen(
        tester,
        const NotificationsScreen(),
        overrides: [
          inboxServiceProvider.overrideWithValue(
            _FailingInbox(
              const SocketException('Failed host lookup'),
              action: _invitation(),
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'a decision that failed must not fail silently');
      expect(find.textContaining('No internet connection'), findsOneWidget,
          reason: 'a host lookup failure is genuinely a connectivity problem');
      // Every error in the app carries one, and it is the only way back
      // without leaving the screen.
      expect(find.text('Retry'), findsOneWidget);

      // The card is usable again behind the bar.
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(kErrorSnackDuration + const Duration(seconds: 1));
      await tester.pumpAndSettle();
    });
  });

  group('the guard -- every inbox call carries a deadline', () {
    // A new method on InboxService that forgets the wrapper reintroduces
    // exactly this bug, silently and invisibly to flutter analyze. This is
    // the test that would have failed in the first place.
    final source = File('lib/shared/inbox_service.dart').readAsStringSync();

    test('no call reaches Supabase without going through the deadline', () {
      // Chain starts: _db.from(...) and _db.schema(...). Each one must sit
      // inside a _withDeadline( call.
      // Whitespace-tolerant on purpose: four of the nine chains wrap onto
      // the next line, and a same-line-only pattern silently checked five of
      // them and passed.
      final starts =
          RegExp(r'_db\s*\.\s*(?:from|schema)\(').allMatches(source).length;
      // One mention is the declaration itself; the rest are uses, one per
      // chain start. Nine today: five app RPCs and four notifications calls.
      final wrapped = RegExp(r'_withDeadline[(<]').allMatches(source).length;

      expect(starts, greaterThan(0),
          reason: 'a guard that finds nothing to check reads exactly like '
              'one that passes');
      expect(wrapped, starts + 1,
          reason: 'found $starts calls to Supabase but ${wrapped - 1} of them '
              'wrapped -- a new method has skipped the deadline');

      expect(RegExp(r'await\s+_db\.').hasMatch(source), isFalse,
          reason: 'an awaited bare _db call has no deadline and can hang '
              'forever');
    });

    test('the deadline is the shared constant, not a second copy', () {
      // Two copies of a timeout is how two paths start disagreeing about how
      // long is too long.
      expect(source, contains('kManaQueryTimeout'));
      expect(RegExp(r'Duration\(seconds:').hasMatch(source), isFalse,
          reason: 'use kManaQueryTimeout from network_error_handler.dart');
    });
  });
}
