import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/theme.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_004_customer_management.dart';

/// Add Customer: nothing on this form may fail in silence.
///
/// FOUR FINDINGS, one shape. A village picked without the box saying so; two
/// buttons that did nothing and explained nothing; a book with no villages
/// letting somebody fill a form with nowhere to put an address; and a back
/// press throwing away everything typed.
void main() {
  String lib(String path) => File('lib/$path').readAsStringSync();

  final ow004 =
      lib('features/owner_workspace/screens/ow_004_customer_management.dart');

  group('item 5a - the box shows what was picked', () {
    test('both village pickers write the chosen name into their own field',
        () {
      // The PIN picker is the one in the screenshot: the box read "Pan" while
      // "Panagal" was selected underneath it, so the one field a person reads
      // back to check themselves disagreed with the choice.
      final pin = lib('shared/widgets/village_picker_field.dart');
      final tap = pin.substring(pin.indexOf('onTap: () {'));
      expect(tap.substring(0, tap.indexOf('},')), contains('_query.text = v.name;'));

      // MOVED, NOT REMOVED. The cascade picker's tap became a call to
      // _choose so it could ask which district first -- lgd_villages carries
      // the 2022 split as two rows and the app had been resolving that by
      // sort order. The rule this test exists for is unchanged and lives
      // there now, which is why this reads _choose rather than an inline
      // onTap. A scan for the old shape returned -1 and took the substring
      // with it, so the failure was a RangeError rather than a sentence.
      final cascade = lib('shared/widgets/village_search_field.dart');
      final choose = cascade.substring(cascade.indexOf('Future<void> _choose('));
      expect(choose.substring(0, choose.indexOf('widget.onPicked')),
          contains('_village.text = chosen.name;'),
          reason: 'the two pickers must agree, or one screen autofills and '
              'the other does not');
      // And what it writes is what was CHOSEN, district and all, not the row
      // the search happened to return first.
      expect(choose, contains('widget.onPicked(chosen)'));
    });
  });

  group('item 5b - a button either acts or says why', () {
    test('neither ending can be disabled into silence', () {
      final endings = ow004.substring(ow004.indexOf('class _AddEndings'));
      final body = endings.substring(0, endings.indexOf('// --- C5 Customer'));
      expect(body.contains('onPressed: enabled ?'), isFalse,
          reason: 'a disabled button at a doorstep is indistinguishable from '
              'a broken one -- which is exactly how this was reported');
      expect(body, contains('void _press(BuildContext context'));
      expect(body, contains('blockedReason()'));
    });

    test('the reason names a field, in the order the form is read', () {
      final missing = ow004.substring(ow004.indexOf('String? _whatIsMissing()'));
      final body = missing.substring(0, missing.indexOf('\n  }'));
      // Top to bottom, so the first thing named is the first thing missing.
      final order = [
        'full_name_required',
        'father_husband_name_required',
        'gender_required',
        'village_required',
      ];
      var at = -1;
      for (final key in order) {
        final next = body.indexOf(key);
        expect(next, greaterThan(at),
            reason: '$key is checked out of the order the form is read in');
        at = next;
      }
    });

    test('the phone-or-Aadhaar rule moved INTO the same sentence', () {
      // It used to be a snackbar inside _createNew, which only fired once the
      // button was believed to work. Now it is one of the reasons.
      final missing = ow004.substring(ow004.indexOf('String? _whatIsMissing()'));
      expect(missing.substring(0, missing.indexOf('\n  }')),
          contains('customer_needs_phone_or_aadhaar'));
    });
  });

  group('a disabled outline must look disabled', () {
    test('the theme resolves a disabled border, not one flat colour', () {
      // styleFrom's `side` is state-blind: the old style kept its full 1.2px
      // brand-blue border while disabled, and against the white page the
      // border is what reads as "this is a button". App-wide, not one screen.
      final style = ManaTheme.light().outlinedButtonTheme.style!;
      final enabled = style.side!.resolve(<WidgetState>{});
      final disabled = style.side!.resolve(<WidgetState>{WidgetState.disabled});
      expect(disabled, isNotNull);
      expect(disabled!.color, isNot(enabled!.color),
          reason: 'a disabled outlined button still looks pressable');
    });

    test('and its label greys too', () {
      final style = ManaTheme.light().outlinedButtonTheme.style!;
      final enabled = style.foregroundColor!.resolve(<WidgetState>{});
      final disabled =
          style.foregroundColor!.resolve(<WidgetState>{WidgetState.disabled});
      expect(disabled, isNot(enabled));
    });
  });

  group('item 6 - a book with no villages', () {
    test('the form asks which villages this business works', () {
      expect(ow004, contains('businessVillages(widget.businessId)'),
          reason: 'this screen never asked, so an Owner on a new book could '
              'fill seven fields and only then find there was nowhere to put '
              'the person');
      expect(ow004, contains("ref.t('villages_this_business_works')"));
    });

    test('the shortlist carries the PIN beside each name', () {
      // Two villages of the same name in one district is ordinary; the PIN is
      // what separates them.
      expect(ow004, contains(r"'${v.name} (${v.pinCode})'"));
    });

    test('adding a village goes to Operating Areas, not an inline create', () {
      // A village is not a customer's field. It is a decision about where
      // this book works, and it belongs with the other ones.
      expect(ow004, contains("context.push('/ow-012?tab=areas'"));
      expect(ow004, contains("ref.t('add_new_village')"));
    });
  });

  group('items 7 and 13 - typing survives a back press', () {
    test('the draft lives outside the State that dies', () {
      expect(ow004, contains('class ManaAddCustomerDraft'));
      expect(ow004, contains('_saveDraft();'),
          reason: 'dispose must copy the fields out before the controllers go');
      final dispose = ow004.substring(ow004.indexOf('  void dispose() {'));
      final body = dispose.substring(0, dispose.indexOf('\n  }'));
      expect(body.indexOf('_saveDraft()'), lessThan(body.indexOf('_query.dispose()')),
          reason: 'saving after disposing the controllers would read from '
              'objects that are already gone');
    });

    test('it is held in memory and never written to the handset', () {
      // It carries a mobile number and an Aadhaar number. Persisting those
      // would outlive the session, the person and the reason -- a different
      // decision from "do not retype what you just typed".
      final draft = ow004.substring(ow004.indexOf('class ManaAddCustomerDraft'));
      final body = draft.substring(0, draft.indexOf('\n}'));
      expect(body.contains('SharedPreferences'), isFalse);
      expect(body.contains('secureStorage'), isFalse);
      expect(body.contains('FlutterSecureStorage'), isFalse);
    });

    test('it is per business', () {
      expect(ManaAddCustomerDraft.of('a'), isNot(ManaAddCustomerDraft.of('b')),
          reason: 'an Owner of two books adding somebody to each must not '
              'find one book\'s half-typed customer in the other\'s form');
      expect(ManaAddCustomerDraft.of('a'), same(ManaAddCustomerDraft.of('a')));
    });

    test('a created customer clears the draft before the sheet pops', () {
      final create = ow004.substring(ow004.indexOf('Future<void> _createNew('));
      final body = create.substring(0, create.indexOf('_announceCreated(id)'));
      expect(body, contains('ManaAddCustomerDraft.clear(widget.businessId)'),
          reason: 'otherwise the next Add Customer opens offering a person '
              'who is already on the book');
    });

    test('an empty form says Close, a filled one says Discard', () {
      expect(ow004, contains("_isDirty ? ref.t('discard') : ref.t('close')"),
          reason: '"Discard" over an untouched form is a threat about '
              'nothing, and it makes somebody stop and read a button that '
              'should have just closed');
      final d = ManaAddCustomerDraft.of('fresh-book');
      expect(d.isEmpty, isTrue);
      d.fullName = 'Ramesh';
      expect(d.isEmpty, isFalse);
      ManaAddCustomerDraft.clear('fresh-book');
    });
  });
}
