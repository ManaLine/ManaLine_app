import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/web_router.dart';
import 'main.dart' show ManaLineApp, bootstrapManaApp;

/// The web build's entrypoint — `flutter build web -t lib/main_web.dart`.
///
/// Deliberately thin. Everything Android's `main()` (lib/main.dart) does
/// before `runApp` — Supabase.initialize, cold-start session hydration,
/// the orientation lock, installing the shared header actions — is the
/// SAME work this build needs, so it is not repeated here: both
/// entrypoints call [bootstrapManaApp], which lives in main.dart. The one
/// difference between the two builds is which router drives navigation,
/// so that is the one thing passed in.
Future<void> main() async {
  await bootstrapManaApp(router: manaWebRouter);
  runApp(ProviderScope(child: ManaLineApp(router: manaWebRouter)));
}
