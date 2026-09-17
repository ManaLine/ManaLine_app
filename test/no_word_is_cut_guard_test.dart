import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_fit_text.dart';

import 'support/mana_harness.dart';

/// No word gets cut and replaced with dots.
///
/// THE OWNER'S RULE, given on 2026-09-17: "make sure no word (in the entire
/// app includes every language we render in future also) from now should be
/// cut and show the remaining in dots, if necessary use the extra row (auto
/// extend) when necessary." Asked again, sharper: "can't the app reduce the
/// size automatically if the name gets longer to fit in!"
///
/// It can. ManaFitText measures, shrinks to a floor, and then takes another
/// line -- and passes no `overflow`, which is the whole difference: Flutter
/// clips rather than ellipsising when overflow is null, so a string that
/// still does not fit loses pixels instead of gaining a "..." that claims to
/// be the whole answer.
///
/// WHY A FLOOR AND NOT JUST FittedBox. This app is used at a doorstep in
/// bright sun on a cheap screen. Text shrunk far enough to fit anything is
/// text nobody can read, which fails the same person the rule protects -- and
/// FittedBox would also undo the text scale somebody deliberately raised in
/// their phone settings.
///
/// THE LIST BELOW IS A BACKLOG, NOT AN EXEMPTION, and it is the point of the
/// file. It is the same shape as `_appliedButFileMissing` in
/// translation_keys_exist_test (69 -> 21 -> 0) and the money backlog in
/// money_display_guard_test (20 files -> 0). Counting the debt is what made
/// those shrink; a rule with nothing keeping score does not.
///
/// NOT EVERY ENTRY HERE IS WRONG. Free prose -- a remark, a rejection reason,
/// a description -- is genuinely unbounded, the reader can open it to see the
/// rest, and letting one push a list row to nine lines helps nobody. Those
/// come OFF this list by being read and judged, one at a time, with the
/// reason written beside them. What must not happen is a new name, village,
/// business or amount joining it.
///
/// SHRINKING THIS LIST IS PROGRESS. Adding to it is not. A count that goes UP
/// fails, and so does a count that goes DOWN without the number being
/// corrected -- because the census is answered by looking, not by editing.
void main() {
  /// Files that still ellipsise, and how many times.
  ///
  /// 128 sites across 50 files, measured 2026-09-17 after the first pass. It
  /// was 137: the shared member roster (four identity fields, and four
  /// screens draw their people through it), the business-management member
  /// row, the one-person entry header, the app bar title and the dashboard
  /// header all moved to ManaFitText.
  ///
  /// The app bar and the dashboard header take a HARDER floor, 0.7 rather
  /// than 0.8, because both have a fixed height -- a second line is not
  /// available there, so the alternative to shrinking is dots on a screen
  /// title. That is exactly what "Workforce Ma..." was.
  const backlog = <String, int>{
    'design/components/mana_amount.dart': 2,
    'design/components/mana_app_shell.dart': 5,
    'design/components/mana_brand_mark.dart': 2,
    'design/components/mana_collapsible_section.dart': 1,
    'design/components/mana_header.dart': 3,
    'design/components/mana_ledger.dart': 7,
    'design/components/mana_member_roster.dart': 9,
    'design/components/mana_money_row.dart': 2,
    'design/components/mana_stat_strip.dart': 1,
    'design/components/mana_text.dart': 1,
    'features/agent_workspace/screens/ag_001_agent_home_dashboard.dart': 1,
    'features/agent_workspace/screens/ag_004_customer_management.dart': 4,
    'features/agent_workspace/screens/ag_005_draft_transactions.dart': 1,
    'features/agent_workspace/screens/ag_006_owner_settlement.dart': 2,
    'features/agent_workspace/screens/ag_007_loan_distribution.dart': 1,
    'features/agent_workspace/screens/ag_008_notifications.dart': 3,
    'features/customer_workspace/screens/cw_005_make_a_payment.dart': 1,
    'features/login_registration/screens/lr_007_first_login.dart': 1,
    'features/login_registration/screens/lr_012_business_selector.dart': 2,
    'features/owner_workspace/screens/ow_002_workforce_management.dart': 2,
    'features/owner_workspace/screens/ow_003_investor_management.dart': 1,
    'features/owner_workspace/screens/ow_006_collection_mode.dart': 2,
    'features/owner_workspace/screens/ow_007_loan_details.dart': 3,
    'features/owner_workspace/screens/ow_009_daily_record_book.dart': 2,
    'features/owner_workspace/screens/ow_010_report_hub.dart': 4,
    'features/owner_workspace/screens/ow_011_day_closure.dart': 1,
    'features/owner_workspace/screens/ow_012_business_management.dart': 7,
    'features/owner_workspace/screens/ow_013_account_review.dart': 2,
    'features/owner_workspace/screens/ow_015_group_loan_management.dart': 2,
    'features/owner_workspace/screens/ow_016_profile.dart': 1,
    'features/owner_workspace/screens/ow_017_statement_screen.dart': 1,
    'features/owner_workspace/screens/ow_018_business_migration.dart': 3,
    'features/owner_workspace/screens/ow_019_cheti_management.dart': 2,
    'features/owner_workspace/screens/ow_one_by_one_migration.dart': 1,
    'features/owner_workspace/screens/ow_trash_screen.dart': 6,
    'features/owner_workspace/screens/ow_village_book.dart': 3,
    'features/owner_workspace/screens/ow_village_customers.dart': 1,
    'shared/agent_picker_sheet.dart': 2,
    'shared/apply_penalty_sheet.dart': 3,
    'shared/collect_sheet.dart': 1,
    'shared/collection_round_view.dart': 10,
    'shared/customer_row.dart': 4,
    'shared/ledger_filter_sheet.dart': 2,
    'shared/ledger_history_view.dart': 2,
    'shared/notifications_screen.dart': 4,
    'shared/widgets/add_village_sheet.dart': 1,
    'shared/widgets/mana_tab_heading.dart': 1,
    'shared/widgets/reference_field.dart': 1,
    'shared/widgets/village_picker_field.dart': 1,
    'shared/widgets/village_search_field.dart': 3,
  };

  final ellipsis = RegExp(r'TextOverflow\.ellipsis');

  int countIn(String relativePath) =>
      ellipsis.allMatches(File('lib/$relativePath').readAsStringSync()).length;

  Map<String, int> scan() {
    final found = <String, int>{};
    void walk(Directory d) {
      for (final e in d.listSync()) {
        if (e is Directory) {
          walk(e);
        } else if (e is File && e.path.endsWith('.dart')) {
          final rel =
              e.path.replaceAll(r'\', '/').replaceFirst(RegExp(r'^lib/'), '');
          final n = ellipsis.allMatches(e.readAsStringSync()).length;
          if (n > 0) found[rel] = n;
        }
      }
    }

    walk(Directory('lib'));
    return found;
  }

  test('no NEW file starts cutting words', () {
    final found = scan();
    final added = found.keys.where((f) => !backlog.containsKey(f)).toList();
    expect(added, isEmpty,
        reason: 'these ellipsise and were not on the backlog: '
            '${added.join(', ')}. If the text identifies somebody or '
            'something -- a name, a village, a business, an MLID, an amount '
            '-- use ManaFitText. Do not add a name to the backlog');
  });

  test('a file on the backlog has not grown', () {
    final found = scan();
    final grown = <String>[];
    for (final e in backlog.entries) {
      final now = found[e.key] ?? 0;
      if (now > e.value) grown.add('${e.key} ${e.value} -> $now');
    }
    expect(grown, isEmpty,
        reason: 'a file already carrying this debt added more of it: '
            '${grown.join('; ')}');
  });

  test('the backlog is answered by looking, not by editing the number', () {
    final found = scan();
    final stale = <String>[];
    for (final e in backlog.entries) {
      final now = found[e.key] ?? 0;
      if (now < e.value) stale.add('${e.key} ${e.value} -> $now');
    }
    expect(stale, isEmpty,
        reason: 'fixed some -- record the new figure, or remove the entry: '
            '${stale.join('; ')}');
  });

  group('the widget that replaces them', () {
    final src =
        File('lib/design/components/mana_fit_text.dart').readAsStringSync();

    test('it passes no overflow, which is the whole difference', () {
      expect(src.contains('overflow:'), isFalse,
          reason: 'passing any overflow at all would make this another way '
              'of cutting a word');
    });

    test('it measures before it chooses', () {
      expect(src, contains('TextPainter('));
      expect(src, contains('didExceedMaxLines'));
      expect(src, contains('textScaler: scaler'),
          reason: 'measuring without the platform scaler would shrink text '
              'that a person had deliberately enlarged');
    });

    test('it stops shrinking at a floor', () {
      expect(src, contains('final floor = size * minScale;'));
      expect(src, contains('this.minScale = 0.8'),
          reason: 'the default floor; the two fixed-height bars pass 0.7 '
              'explicitly and say why');
    });

    test('an unbounded width is not guessed at', () {
      // A Row without a Flexible gives infinite width, and shrinking to fit
      // infinity is not a question with an answer.
      expect(src, contains('constraints.hasBoundedWidth'));
    });
  });

  group('the sites that carry identity', () {
    test('the shared member roster does not cut a name', () {
      final roster = File('lib/design/components/mana_member_roster.dart')
          .readAsStringSync();
      expect(roster, contains('ManaFitText(entry.name'));
      expect(roster, contains('ManaFitText(entry.subtitle'));
    });

    test('the two fixed-height bars shrink harder than the default', () {
      for (final f in const [
        'design/components/mana_app_bar.dart',
        'design/components/mana_header.dart',
      ]) {
        expect(File('lib/$f').readAsStringSync(), contains('minScale: 0.7'),
            reason: '$f has a fixed height, so the alternative to shrinking '
                'is dots on a screen title rather than another line');
      }
    });

    test('the app bar stopped ellipsising its title', () {
      expect(countIn('design/components/mana_app_bar.dart'), 0,
          reason: 'this is what the handset read as "Workforce Ma..."');
    });
  });

  group('it actually shrinks, and actually wraps', () {
    /// The rendered font size of the one Text inside a pumped ManaFitText.
    double sizeOf(WidgetTester tester) =>
        tester.widget<Text>(find.byType(Text)).style!.fontSize!;

    Future<void> pump(WidgetTester tester, String text, double width,
        {double scale = 1.0, int maxLines = 2}) async {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: width,
              child: ManaFitText(text,
                  maxLines: maxLines,
                  style: const TextStyle(fontSize: 20)),
            ),
          ),
        ),
      ));
    }

    testWidgets('a short string is left at full size', (tester) async {
      await pump(tester, 'Ashok', 300);
      expect(sizeOf(tester), 20);
    });

    testWidgets('a long one shrinks rather than being cut', (tester) async {
      await pump(tester, 'Kammalapati Venkata Subrahmanya Sastry Garu', 120);
      expect(sizeOf(tester), lessThan(20),
          reason: 'it should have shrunk to fit two lines of 120dp');
      expect(sizeOf(tester), greaterThanOrEqualTo(16),
          reason: 'and never below the 0.8 floor, which is what stops this '
              'from being unreadable at a doorstep');
    });

    testWidgets('past the floor it stops shrinking and takes the line',
        (tester) async {
      // Narrow enough that no permitted size fits two lines. The floor holds
      // and the widget still draws every word it can -- with no ellipsis,
      // which is the rule.
      await pump(tester, 'Kammalapati Venkata Subrahmanya Sastry Garu', 40);
      expect(sizeOf(tester), 16, reason: '20 * 0.8, the floor exactly');
      expect(tester.widget<Text>(find.byType(Text)).overflow, isNull,
          reason: 'no ellipsis, ever -- that is the whole rule');
      expectNoLayoutFault(tester, 'ManaFitText past its floor');
    });

    testWidgets('a raised system text scale is respected, not undone',
        (tester) async {
      // FittedBox would squeeze this back down past where the person set it.
      // Measuring WITH the scaler means a 2.0x reader gets a wrap instead.
      await pump(tester, 'Venkata Subrahmanyam Garu', 200, scale: 2.0);
      expect(sizeOf(tester), greaterThanOrEqualTo(16));
      expectNoLayoutFault(tester, 'ManaFitText at 2.0x');
    });
  });
}
