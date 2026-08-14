import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';
import 'package:mana_line/shared/translation_service.dart';
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// Switching to Telugu in Settings changed nothing on screen.
///
/// `ref.t()` READ the language rather than watching it, so a change updated the
/// state and marked nobody dirty. The only screens that followed were the four
/// that happened to watch authFlowProvider for their own reasons — Settings
/// itself among them, which is why the dropdown moved and the app behind it
/// did not.
///
/// These pin the two shapes that matter. The dialog one is not decoration: it
/// decides whether watching inside t() is safe at all, because a WidgetRef
/// watched outside its owning widget's build is an error, and a dialog builder
/// runs in the dialog's build while holding the screen's ref. If that were
/// illegal the fix would have to be something else entirely.
void main() {
  testWidgets('a screen follows a language change', (tester) async {
    final container = await pumpManaScreen(
      tester,
      Consumer(builder: (context, ref, _) => Text(ref.t('cancel'))),
    );

    expect(find.text('Cancel'), findsOneWidget);

    container.read(authFlowProvider.notifier).setLanguage(ManaLanguage.telugu);
    await tester.pump();

    expect(find.text('Cancel'), findsNothing);
    expect(find.text('రద్దు చేయండి'), findsOneWidget);
  });

  testWidgets('a dialog builder may call t() without throwing', (tester) async {
    await pumpManaScreen(
      tester,
      Consumer(
        builder: (context, ref, _) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(title: Text(ref.t('cancel'))),
          ),
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
  });
}
