import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the mistake that hid nine layout defects in this codebase.
///
/// `tester.tap(finder, warnIfMissed: false)` is silent when it lands on
/// nothing. Flutter would normally shout that a hit test missed; that flag
/// turns the shouting off, and it is needed often enough — a widget behind a
/// sheet, a scrolled list — that it is everywhere.
///
/// Combine it with `expectNoLayoutFault`, which passes on ANY screen that
/// lays out, and a test that never reached its target reports green. That is
/// not a hypothetical: every tab-walking test in this suite tapped
///
///     tester.tap(find.byType(Tab).at(i), warnIfMissed: false)
///
/// on a scrollable TabBar, where later tabs are off screen. Six screens'
/// worth of tabs were declared clean while the walk never left the first one.
/// The commit saying "Twenty-six tab bodies were clean" was wrong. Adding
/// `ensureVisible` turned up overflows of 61, 152, 160, 259, 278, 391, 404
/// and 572 pixels, one of them at 1.0x in English.
///
/// The rule: a tap that is allowed to miss in silence must either be
/// GUARANTEED to hit — ensureVisible, scrollUntilVisible, or a drag that
/// brings the target into view — or be CHECKED afterwards by an expect that
/// would fail if it had not landed. Layout assertions do not count as
/// checking, which is the whole point.
///
/// A widget-level lint was tried first and abandoned: "a Row with a flexible
/// child beside a bare button" flags 13 sites in lib/, and the ones sampled
/// do not overflow, because whether text fits is a question only layout can
/// answer. The defect was never really in the source shape — it was in tests
/// that could not see it.
void main() {
  const guarantees = ['ensureVisible', 'scrollUntilVisible', 'drag('];

  test('a silent tap is either guaranteed to land or checked afterwards', () {
    final offenders = <String>[];

    for (final entity in Directory('test').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // This file quotes the pattern it bans.
      if (entity.path.replaceAll(r'\', '/').endsWith('silent_tap_guard_test.dart')) {
        continue;
      }

      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('warnIfMissed: false')) continue;

        final before = lines.sublist((i - 8).clamp(0, i), i).join('\n');
        final after =
            lines.sublist(i + 1, (i + 12).clamp(i + 1, lines.length)).join('\n');

        final guaranteed = guarantees.any(before.contains);
        // An expect() that would fail if the tap had done nothing. A bare
        // expectNoLayoutFault is NOT one: it passes on the untouched screen.
        final checked = after.contains('expect(');

        if (!guaranteed && !checked) {
          offenders.add('${entity.path.split(RegExp(r'[\/]')).last}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These taps can miss in silence and nothing would notice:\n'
          '  ${offenders.join('\n  ')}\n\n'
          'Put ensureVisible (or scrollUntilVisible, or a drag) before the '
          'tap, or an expect after it that fails when the tap does nothing. '
          'expectNoLayoutFault does not count — it passes on the screen the '
          'tap was supposed to leave.',
    );
  });
}
