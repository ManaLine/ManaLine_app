import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/business_transfer_screen.dart';
import 'package:mana_line/features/owner_workspace/state/business_transfer_state.dart';

import 'support/mana_harness.dart';

void main() {
  BusinessTransfer offer({
    required String direction,
    String status = 'Pending',
    String? note,
  }) =>
      BusinessTransfer(
        transferId: 't1',
        businessId: 'b1',
        businessName: 'Sri Tirumala Finance',
        mlbi: 'MLBI-62730000',
        direction: direction,
        counterparty: 'Kovvuri Sai Ramakrishna Reddy',
        counterpartyMlid: 'MLPI100000003',
        status: status,
        note: note,
      );

  Override seed(List<BusinessTransfer> rows) =>
      businessTransfersProvider.overrideWith((ref) async => rows);

  for (final scale in kManaTextScales) {
    testWidgets('Transfer survives text scale ${scale}x', (tester) async {
      await pumpManaScreen(
        tester,
        const BusinessTransferScreen(businessId: 'b1'),
        textScale: scale,
        surfaceSize: const Size(360, 2000),
        overrides: [
          seed([offer(direction: 'incoming'), offer(direction: 'outgoing')]),
        ],
      );
      expectNoLayoutFault(tester, 'Business transfer at ${scale}x');
    });
  }

  testWidgets('the two directions are labelled differently', (tester) async {
    // Cancelling something you offered and accepting something offered to you
    // are opposite decisions. If they ever render under the same heading,
    // someone taps the wrong one.
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [
        seed([offer(direction: 'incoming'), offer(direction: 'outgoing')]),
      ],
    );

    // "to" stays lowercase: ManaText enforces the locked Title Case standard,
    // in which 'to' is a minor word anywhere but the first position.
    expect(find.text('Offered to You'), findsOneWidget);
    expect(find.text('Waiting to Be Accepted'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Cancel Offer'), findsOneWidget);
  });

  testWidgets('an incoming offer never shows a cancel control',
      (tester) async {
    // Only the person who made an offer may withdraw it; the server enforces
    // that, and the screen must not invite an action that will be refused.
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [seed([offer(direction: 'incoming')])],
    );
    expect(find.text('Cancel Offer'), findsNothing);
    expect(find.text('Accept'), findsOneWidget);
  });

  testWidgets('an outgoing offer cannot be accepted by its sender',
      (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [seed([offer(direction: 'outgoing')])],
    );
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Cancel Offer'), findsOneWidget);
  });

  testWidgets('answered offers are not shown as if they were live',
      (tester) async {
    // Only Pending offers carry actions. A Declined row still listing Accept
    // would offer a button the server refuses.
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [
        seed([
          offer(direction: 'incoming', status: 'Declined'),
          offer(direction: 'outgoing', status: 'Accepted'),
        ]),
      ],
    );
    expect(find.text('Accept'), findsNothing);
    expect(find.text('Cancel Offer'), findsNothing);
  });

  testWidgets('handing over says plainly that everything goes', (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [seed(const [])],
    );
    // The preconditions the server enforces are stated up front rather than
    // discovered as an error.
    expect(find.textContaining('have to accept'), findsOneWidget);
    expect(find.textContaining('agent cash'), findsOneWidget);
  });

  testWidgets('no offer can be sent before a person is found', (tester) async {
    await pumpManaScreen(
      tester,
      const BusinessTransferScreen(businessId: 'b1'),
      surfaceSize: const Size(360, 2000),
      overrides: [seed(const [])],
    );
    // The Send Offer button only exists once a lookup has resolved someone —
    // otherwise there is no person_id to send to.
    expect(find.text('Send Offer'), findsNothing);
    expect(find.text('Find Person'), findsOneWidget);
  });
}
