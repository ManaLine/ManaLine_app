import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_member_roster.dart';
import 'package:mana_line/design/tokens/colors.dart';

/// The ring reaches every roster, and the count slides leave the last two
/// screens that had them.
///
/// OW-012's member list settled both on 2026-09-17. Asked for again the same
/// day, for Agent and Investor Management: "remove those top swipes total,
/// active, etc" and "remove active wording - implement ring concept here."
/// Those two screens draw their people through ManaMemberRoster, so the rule
/// lands in the shared row rather than in each screen.
void main() {
  final roster =
      // LINE ENDINGS NORMALISED. These assertions match multi-line snippets of
      // source, and .gitattributes pins only *.sql to LF -- every other file follows
      // the machine's core.autocrlf, so a Dart file is CRLF on Windows and LF in CI.
      // Five tests in this repo failed the moment a branch switch re-materialised
      // the working tree with CRLF, having passed all day only because unrelated
      // edits had happened to rewrite those files as LF. What the guard is checking
      // is the code, not which bytes end its lines.
      File('lib/design/components/mana_member_roster.dart').readAsStringSync().replaceAll('\r\n', '\n');

  group('the ring says the state', () {
    test('Suspended and Removed are different colours', () {
      // NOT statusKind's mapping, deliberately. That getter groups them both
      // as "bad", which is right for a pill that also carries the word -- the
      // word does the separating. A ring has no word.
      const suspended = MemberEntry(id: '1', name: 'A', subtitle: '', status: 'Suspended');
      const removed = MemberEntry(id: '2', name: 'B', subtitle: '', status: 'Removed');
      expect(suspended.ringColor, ManaColors.statusBad);
      expect(removed.ringColor, ManaColors.statusWarn);
      expect(suspended.ringColor, isNot(removed.ringColor),
          reason: 'with no word beside it, a ring that paints both the same '
              'says less than the pill it replaced');
      // And the pill's own grouping is untouched, because the word carries it.
      expect(suspended.statusKind, removed.statusKind);
    });

    test('Active is green and Pending is amber', () {
      const active = MemberEntry(id: '1', name: 'A', subtitle: '', status: 'Active');
      const pending = MemberEntry(
          id: '2', name: 'B', subtitle: '', status: 'Pending Invitation');
      expect(active.ringColor, ManaColors.statusGood);
      expect(pending.ringColor, ManaColors.statusWarn);
    });

    test('the row draws it', () {
      expect(roster, contains('border: Border.all(color: entry.ringColor'));
    });
  });

  group('the word goes, except where it is the only thing saying so', () {
    test('an Active row carries no pill', () {
      expect(roster, contains("entry.status == 'Active'\n          ? null"),
          reason: '"Active" beside a green ring is the same fact twice, and it '
              'was the fact on nearly every row -- so the column existed to '
              'say nothing');
    });

    test('every other state keeps its word', () {
      expect(roster, contains('ManaTrailingStatus(\n              label: entry.status'),
          reason: 'a colour on its own is a legend nobody was given, and '
              'Suspended, Removed and the Pending states are the rows where '
              'being sure matters');
    });
  });

  group('the count slides are gone from the last two screens', () {
    test('Investor Management', () {
      final src = File(
              'lib/features/owner_workspace/screens/ow_003_investor_management.dart')
          .readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains('_DashboardStrip'), isFalse,
          reason: 'the widget went with its usage, not just the call');
      expect(src.contains('ManaStatStrip'), isFalse);
      // What it claimed is still there and better: the filter narrows by the
      // same states and every row's ring says its own.
      expect(src, contains('onStatusChanged:'));
    });

    test('Agent Management, still', () {
      final src = File(
              'lib/features/owner_workspace/screens/ow_002_workforce_management.dart')
          .readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains('_DashboardStrip'), isFalse);
      expect(src.contains('ManaStatStrip'), isFalse);
    });

    test('no roster screen has grown one back', () {
      // The general shape. ManaStatStrip is still legitimate elsewhere -- it
      // is a component, not a mistake -- but not above a list that already
      // filters by the thing being counted.
      for (final f in const [
        'lib/features/owner_workspace/screens/ow_002_workforce_management.dart',
        'lib/features/owner_workspace/screens/ow_003_investor_management.dart',
        'lib/features/owner_workspace/screens/ow_004_customer_management.dart',
        'lib/features/agent_workspace/screens/ag_004_customer_management.dart',
      ]) {
        final src = File(f).readAsStringSync().replaceAll('\r\n', '\n');
        if (!src.contains('ManaMemberRoster')) continue;
        expect(src.contains('header: _DashboardStrip'), isFalse,
            reason: '$f put a count strip back above its roster');
      }
    });
  });
}
