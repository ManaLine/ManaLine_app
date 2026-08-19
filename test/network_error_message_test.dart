import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/network_error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reproduces what a live Owner saw while entering a pre-existing loan: the
/// raw Postgres text
///   duplicate key value violates unique constraint "uq_persons_mobile_number"
/// on a SnackBar, naming neither the field nor what to do about it.
Future<String> _messageFor(WidgetTester tester, Object error) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) {
      ctx = c;
      return const Scaffold(body: SizedBox());
    }),
  ));
  await NetworkErrorHandler.run<void>(ctx, () async => throw error);
  await tester.pump();
  final message = tester.widget<Text>(find.byType(Text).first).data!;
  // Let the bar's dismissal timer run out, or the test ends with it pending.
  await tester.pump(kErrorSnackDuration + const Duration(seconds: 1));
  await tester.pumpAndSettle();
  return message;
}

void main() {
  testWidgets('a duplicate mobile number is explained, not dumped', (tester) async {
    final message = await _messageFor(
      tester,
      const PostgrestException(
        message: 'duplicate key value violates unique constraint '
            '"uq_persons_mobile_number"',
        code: '23505',
      ),
    );

    expect(message, contains('mobile number'));
    expect(message, contains('already registered'));
    expect(message, isNot(contains('duplicate key')));
    expect(message, isNot(contains('uq_persons')));
  });

  testWidgets('an unmapped server error keeps its own words', (tester) async {
    // A friendly guess here would hide a real bug, so the raw text stands.
    final message = await _messageFor(
      tester,
      const PostgrestException(message: 'column x does not exist', code: '42703'),
    );

    expect(message, 'column x does not exist');
  });

  testWidgets('an error snackbar dismisses itself despite its Retry action',
      (tester) async {
    // Seen live: a failed save left the error bar sitting over the Save
    // buttons on Add a Customer for six minutes, unswipeable. A SnackBar
    // that carries an action ignores its own `duration` on Flutter 3.44, and
    // every error in the app carries a Retry action.
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      }),
    ));

    await NetworkErrorHandler.run<void>(ctx, () async => throw Exception('x'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.pump(kErrorSnackDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
  });
}
