import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Operating Areas tab leads with the areas, and names one agent per row.
///
/// REPORTED FROM THE HANDSET (item 12): "operating areas - change the screen
/// display looks outdated - what to change - remove area name & village
/// selection show operating areas (if any) and add area option opposite to
/// 'current operating areas'" and "each agent in a single row not
/// continution".
///
/// Source assertions rather than a widget test, because what has to stay true
/// is the SHAPE of the screen — which pieces exist and where creation lives.
/// A widget test of this tab needs the whole business-detail provider graph
/// stood up, and would pin the rendering rather than the decision.
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final src =
      _code('lib/features/owner_workspace/screens/ow_012_business_management.dart');

  group('the list leads', () {
    test('creating an area is a sheet, not the top of the screen', () {
      expect(src, contains('_AddAreaSheet'));
      expect(src, contains('showModalBottomSheet<_NewArea>'));
    });

    test('the inline form is gone', () {
      // What was removed: a controller for the area name and a pick held on
      // the TAB, which together were the form that pushed the rounds an Owner
      // came to look at below the fold.
      expect(src, isNot(contains('final _areaName = TextEditingController();')),
          reason: 'the area name is asked for in the sheet now');
      expect(src, isNot(contains('_addSelected')),
          reason: 'replaced by _addArea, which opens the sheet');
    });

    test('Add Area sits opposite the heading', () {
      final heading = src.indexOf("ref.t('current_operating_areas')");
      expect(heading, isNonNegative);
      // Within the same Wrap: the button is declared just after the heading.
      final nearby = src.substring(heading, heading + 400);
      expect(nearby, contains("ref.t('add_area')"));
    });
  });

  group('the add-area sheet', () {
    test('asks for the village first and names the area after it', () {
      expect(src, contains("ref.t('add_area_step_village')"));
      expect(src, contains('if (v != null && _nameIsDefault) _name.text = v.name;'),
          reason: 'the Owner said village and area are the same thing here — '
              'the old screen already did this and said so nowhere, because '
              'an empty box cannot tell anybody what it will do');
    });

    test('a typed name is not overwritten by a later village', () {
      // _nameIsDefault is the whole reason this is not a one-liner: once
      // somebody types, the text is theirs.
      expect(src, contains('onChanged: (_) => setState(() => _nameIsDefault = false)'));
    });

    test('it will not submit without both a village and a name', () {
      expect(src, contains("_picked == null || _name.text.trim().isEmpty"));
    });
  });

  group('agents', () {
    test('each gets its own row', () {
      expect(src, contains('_AreaAgentRow'));
      expect(src, contains('for (final agent in a.assignedAgents)'));
    });

    test('the names no longer share a line with the button', () {
      // THE ACTUAL BUG. assignedAgentsLabel already joined with '\n', so "one
      // per row" was true in the string and false on screen: the names shared
      // a cramped Expanded with Manage Agents and wrapped MID-NAME, so
      // "Medapati Suresh Krishna Reddy" arrived as three lines and read as
      // three people. The fix is width, not the string.
      expect(src, isNot(contains("replaceAll('{names}', a.assignedAgentsLabel)")),
          reason: 'the joined label is what wrapped mid-name');
    });
  });
}
