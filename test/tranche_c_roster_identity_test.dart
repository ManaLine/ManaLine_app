import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_brand_mark.dart';
import 'package:mana_line/design/tokens/icons.dart';
import 'package:mana_line/features/login_registration/screens/lr_002_workspace_choice.dart';

import 'support/mana_harness.dart';

/// Tranche C: five device findings about what the app SHOWS.
///
/// Four of the five are the same failure in different clothes -- a symbol
/// meaning two things, a word claiming something the list did not do, a name
/// cut off at the point it stopped being an answer, an identity block
/// occupying the screen above the only two controls on it.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  group('item 6 - one glyph, one meaning', () {
    test('nothing draws the piggy bank by hand any more', () {
      // Icons.savings_outlined was drawn for BOTH an investor and a cheti --
      // nine call sites across six files, and on OW-012 the two were on the
      // same screen: an investor count chip in the header and a cheti button
      // in the actions, identical. A symbol that means two things means
      // neither.
      final offenders = <String>[];
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (file.path.replaceAll(r'\', '/').endsWith('design/tokens/icons.dart')) {
          continue; // where the name is defined
        }
        if (file.readAsStringSync().contains('Icons.savings_outlined')) {
          offenders.add(file.path.replaceAll(r'\', '/'));
        }
      }
      expect(offenders, isEmpty,
          reason: 'these reach for the raw glyph instead of ManaIcons.cheti '
              'or ManaIcons.investor, which is how one symbol came to mean '
              'two things: ${offenders.join(', ')}');
    });

    test('an investor and a cheti do not share a symbol', () {
      expect(ManaIcons.investor, isNot(ManaIcons.cheti),
          reason: 'this is the whole finding');
    });

    test('the investor glyph is a giving hand', () {
      // Pinned by value, because "change the icon" is easy to undo by
      // accident and hard to notice. The Owner asked for a hand giving out
      // cash; volunteer_activism is the open offering palm and the closest
      // Material has. If a custom rupee-on-a-palm asset is ever drawn, this
      // line changes with it, deliberately.
      expect(ManaIcons.investor, Icons.volunteer_activism_outlined);
      expect(ManaIcons.cheti, Icons.savings_outlined,
          reason: 'the piggy bank was never the wrong glyph for a cheti -- '
              'saving up in instalments is what it draws');
    });
  });

  group('items 4 and 8 - the roster row', () {
    final ow012 =
        lib('features/owner_workspace/screens/ow_012_business_management.dart');

    test('the heading no longer claims the list is only active people', () {
      expect(ow012.contains("ref.t('active_members')"), isFalse,
          reason: 'the Owner asked for the word to go, and it was not only a '
              'word: the list was FILTERED to Active, so suspending somebody '
              'made them vanish from the only screen that lists members');
      expect(ow012, contains("ref.t('members')"));
    });

    test('suspended and removed people are on the list to be seen', () {
      expect(ow012, contains("{'Active', 'Suspended', 'Removed'}"),
          reason: 'the ring can only show orange and red for rows that exist. '
              'An Owner who suspended the wrong person needs somewhere to go '
              'and undo it');
    });

    test('the ring carries status, and says so explicitly', () {
      // NOT by reinterpreting isVerified. Twenty-two other call sites mean
      // identity verification by that ring, and a screen quietly meaning
      // something else by the same circle is how a reader of any of them is
      // left guessing which they are looking at.
      expect(ow012, contains('ringColor: _ringColor'));
      final ring = ow012.substring(ow012.indexOf('Color get _ringColor'));
      final body = ring.substring(0, ring.indexOf('ManaStatus get _statusKind'));
      expect(body, contains("'Active' => ManaColors.statusGood"));
      expect(body, contains("'Suspended' => ManaColors.statusBad"));
      expect(body, contains("'Removed' => ManaColors.statusWarn"),
          reason: "the Owner's own mapping: active green, suspended red, "
              'removed orange');
    });

    test('the pill survives for the two states a colour cannot carry alone',
        () {
      expect(ow012, contains("if (person.status != 'Active') ..."),
          reason: 'a colour on its own is a legend nobody was given. Active '
              'loses its word because the Owner asked; Suspended and Removed '
              'keep theirs because those are the rows where being sure '
              'matters');
    });

    test('the subtitle is the care-of name, not the role', () {
      final subtitle = ow012.substring(ow012.indexOf('subtitle: Row('),
          ow012.indexOf('// NO TRAILING WIDGET AT ALL'));
      expect(subtitle, contains("ref.t('care_of')"));
      expect(subtitle, contains('member.fatherHusbandName'));
      expect(subtitle, contains('member.village'),
          reason: 'the village is what the Village sort orders by, and a sort '
              'you cannot see the key of looks like it did nothing');
      expect(subtitle.contains('member.role'), isFalse,
          reason: 'the role is a letter at the end of the line now; spelling '
              'it out again is the word the letter replaced');
    });

    test('one person is one row, however many roles they hold', () {
      // Six people on the live books hold more than one role and every Owner
      // is also an Agent, so a row per membership meant duplicate rows that
      // differed by one word.
      expect(ow012, contains('List<ManaRosterPerson> manaRosterByPerson('));
      expect(ow012.contains('...active.map((m) => _MemberRow'), isFalse,
          reason: 'a call site went back to one row per membership');
      // Every place that builds rows goes through the grouping.
      final rows = RegExp(r'_MemberRow\(').allMatches(ow012).length;
      final grouped = RegExp(r'manaRosterByPerson\(').allMatches(ow012).length;
      expect(grouped, greaterThanOrEqualTo(rows - 1),
          reason: 'found $rows _MemberRow constructions and $grouped '
              'groupings; one of them is the class declaration, the rest must '
              'each be fed by a grouping');
    });

    test('a status change asks which role when there is a real question', () {
      final hold = ow012.substring(ow012.indexOf('Future<void> _holdActions'));
      expect(hold, contains('_pickRole(context, ref, person.memberships)'),
          reason: 'suspending somebody who is both an Agent and a Customer is '
              'two different decisions -- an Owner may want to stop them '
              'collecting and go on lending to them');
      final pick = ow012.substring(ow012.indexOf('Future<MemberSummary?> _pickRole'));
      expect(pick.substring(0, pick.indexOf('Future<void> _changeStatus')),
          contains('if (among.length == 1) return among.first;'),
          reason: 'and it must NOT ask when there is one role, or every '
              'ordinary suspend grows a pointless tap');
    });

    test('the village head count counts people, not memberships', () {
      expect(ow012, contains("manaRosterByPerson(byVillage[name]!).length"),
          reason: 'an Owner counting heads against a paper page counts '
              'people; a village whose agent also borrows was reporting one '
              'head too many');
    });
  });

  group('item 9 - a name cut off is not an answer', () {
    test('Workspace Information stopped ellipsising its values', () {
      final ag001 =
          lib('features/agent_workspace/screens/ag_001_agent_home_dashboard.dart');
      final card = ag001.substring(ag001.indexOf('class _SectionCard'),
          ag001.indexOf('/// "MY COMPENSATION'));
      expect(card.contains('TextOverflow.ellipsis'), isFalse,
          reason: 'an Agent opens this section to check WHICH book they are '
              'working, and it answered "Sri Satyanaraya...". Two of this '
              "book's businesses begin \"Sri \"");
      expect(card, contains('ManaLabelValueRow'),
          reason: 'delegated rather than patched: this row was a private copy '
              'of the shared one that had drifted, which is the drift');
    });
  });

  group('item 10 - the brand above the only two controls', () {
    test('the hand-rolled copy of the brand mark is gone', () {
      final lr002 =
          lib('features/login_registration/screens/lr_002_workspace_choice.dart');
      expect(lr002.contains("'assets/images/logo.png'"), isFalse,
          reason: 'ManaBrandMark owns the logo. The copy here had already '
              'drifted -- headlineMedium in ManaColors.brand against the '
              "shared mark's 20sp w800 in brandDeep");
      expect(lr002, contains('ManaBrandMark(horizontal: true'));
      expect(lr002, contains("context.push('/admin-login')"),
          reason: 'the admin panel has no other entry point in the app; '
              'moving the mark must not take the gate with it');
    });

    testWidgets('both product cards fit without scrolling, at every scale',
        (tester) async {
      // MEASURED, and the first version of this test was worthless. It
      // asserted the cards fit on a 640px surface at 1.0x -- which the OLD
      // layout also did, at 400px, so it passed on the bug it was written
      // for. Running it against the stashed original is what said so.
      //
      // Measured on both, last card's bottom edge on a 360x640 surface:
      //
      //          1.0x   1.3x   1.6x   2.0x
      //   before  400    444    555    720   <- off the screen
      //   after   282    326    439    554
      //
      // 2.0x is where the finding actually lives, and it is a real setting on
      // a real handset -- the four scales this project tests every layout at
      // exist because people who work in a field set their phones large.
      for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
        await pumpManaScreen(tester, const WorkspaceChoiceScreen(),
            textScale: scale);
        expectNoLayoutFault(tester, 'the workspace chooser at ${scale}x');

        final cards = find.byType(Card);
        expect(cards, findsNWidgets(2));
        final bottom = tester.getBottomLeft(cards.last).dy;
        expect(bottom, lessThanOrEqualTo(kManaSmallPhone.height),
            reason: 'at ${scale}x the second product card ends at $bottom on '
                'a ${kManaSmallPhone.height}px screen, so reaching the only '
                'two controls on this screen means scrolling');
      }
    });

    testWidgets('the brand is pinned, and the options still scroll if they must',
        (tester) async {
      await pumpManaScreen(tester, const WorkspaceChoiceScreen());

      // PINNED means outside the scroll view. That is the whole of "move it
      // to the header": a mark that scrolls away with the content is not a
      // header, it is the first thing you scroll past.
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(ManaBrandMark),
        ),
        findsNothing,
        reason: 'the brand mark is inside the scroll view again',
      );
      expect(find.byType(ManaBrandMark), findsOneWidget);

      // And the scroll view stays. Fitting is not the same as being
      // guaranteed to fit -- the comment this screen used to carry records
      // what a fixed-height Column did the last time: 41px of overflow on a
      // real handset in landscape.
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
