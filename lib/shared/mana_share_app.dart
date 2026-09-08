import 'package:share_plus/share_plus.dart';

/// Opens the system share sheet with a description of MANA LINE.
///
/// MANA LINE has no published store listing yet, so this describes what the
/// app does rather than linking to a download that would 404. Add the store
/// URL here, in this one place, when there is one.
///
/// Previously three byte-for-byte copies of the same four lines --
/// `settings_screen.dart`, `web_home_screen.dart`, and `web_router.dart`'s
/// route-unavailable screen -- which is exactly the "a second copy went on
/// using the old technique" pattern CLAUDE.md calls out as this codebase's
/// most expensive recorded regression. One function, three callers.
Future<void> shareManaLineApp() async {
  await SharePlus.instance.share(
    ShareParams(
      text: 'MANA LINE — the app my lending business runs on. It keeps every '
          'loan, collection and daily balance in one place.',
      subject: 'MANA LINE',
    ),
  );
}
