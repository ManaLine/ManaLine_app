import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mana_line/app/router.dart';
import 'package:mana_line/shared/widgets/workspace_nav.dart';

import 'support/mana_harness.dart';

/// The four destinations, in one order, in both workspaces.
///
/// There were two navigation bars: the Owner's used GoRouter, and the Agent's
/// was a private copy inside AG-001 built from a raw NavigationBar that pushed
/// each destination with Navigator.push. Two copies of a navigation contract
/// is how two screens end up disagreeing about where a tab goes.
///
/// The second difference was the reported bug. AG-002's back calls
/// context.go('/ag-001'), which rewrites the ROUTER's stack -- but a page
/// pushed with Navigator.push sits above the router's pages, so the screen
/// underneath changed and the pushed page stayed exactly where it was. Back
/// looked dead.
void main() {
  for (final workspace in ManaWorkspace.values) {
    testWidgets('${workspace.name}: Home, Collections, Customers, History',
        (tester) async {
      await pumpManaScreen(
        tester,
        Scaffold(
          bottomNavigationBar: ManaWorkspaceNav(
            workspace: workspace,
            businessId: 'b1',
            currentIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Read off the rendered bar rather than the route list, because the
      // order is what somebody's thumb learns.
      final labels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(labels, ['Home', 'Collections', 'Customers', 'History'],
          reason: 'Collections comes second: it is where the day is spent');
    });
  }

  test('every tab in both workspaces is a registered route', () {
    // The Agent's bar pushed its tabs with Navigator.push because AG-010 had
    // no route -- "the one screen ID without a route". That is what forced the
    // pushed-page-above-the-router shape that broke Back.
    final paths = <String>{};
    void collect(Iterable routes) {
      for (final r in routes) {
        if (r is GoRoute) {
          paths.add(r.path);
          collect(r.routes);
        }
      }
    }

    collect(manaRouter.configuration.routes);

    for (final path in [
      '/ow-001', '/ow-006', '/ow-004', '/ow-017',
      '/ag-001', '/ag-002', '/ag-004', '/ag-010',
    ]) {
      expect(paths, contains(path),
          reason: '$path is a footer tab; a tab that cannot be go()ne to is '
              'what made the Agent push its pages instead');
    }
  });
}
