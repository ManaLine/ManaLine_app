import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_back_handler.dart';

/// The defect: 91 navigations use context.go(), which replaces the router
/// stack, so the Android back button had nothing to pop and fell through to
/// Android — closing the app from three screens deep into someone's work.
void main() {
  group('where back goes', () {
    test('each workspace goes to its own home, never another', () {
      expect(ManaBackHandler.homeFor('/ow-006'), '/ow-001');
      expect(ManaBackHandler.homeFor('/ag-007'), '/ag-001');
      expect(ManaBackHandler.homeFor('/cw-004'), '/cw-001');
      expect(ManaBackHandler.homeFor('/iw-004'), '/iw-001');
    });

    test('login is a flow, not a workspace, so it has no home to jump to', () {
      // Jumping to a dashboard from inside registration would land somebody on
      // a workspace they have not signed into yet.
      expect(ManaBackHandler.homeFor('/lr-009'), isNull);
      expect(ManaBackHandler.homeFor('/recent-deletes'), isNull);
    });

    test('a workspace home is where back means leave', () {
      expect(ManaBackHandler.isExitPoint('/ow-001'), isTrue);
      expect(ManaBackHandler.isExitPoint('/ag-001'), isTrue);
      // The first screen of the app, likewise.
      expect(ManaBackHandler.isExitPoint('/lr-001'), isTrue);
    });

    test('anywhere else is not', () {
      // These are the ones that used to close the app.
      expect(ManaBackHandler.isExitPoint('/ow-006'), isFalse);
      expect(ManaBackHandler.isExitPoint('/ag-002'), isFalse);
      expect(ManaBackHandler.isExitPoint('/ow-005'), isFalse);
    });
  });
  group('what a back press actually does', () {
    // The rules above were right the whole time and the app still closed on
    // back, because nothing was calling them. The handler was a PopScope in
    // MaterialApp.router's builder -- above the Navigator, registered with no
    // ModalRoute, silently inert. These test the decision itself.

    test('something on the stack is popped, and nothing else happens', () {
      var popped = false, wentHome = false;
      final handled = ManaBackHandler.handleBack(
        canPop: true,
        pop: () => popped = true,
        location: '/ow-006',
        goHome: (_) => wentHome = true,
      );
      expect(handled, isTrue);
      expect(popped, isTrue);
      expect(wentHome, isFalse, reason: 'popping is enough; do not also route');
    });

    test('an empty stack away from home routes home rather than exiting', () {
      // This is the case that closed the app: go() left nothing to pop.
      String? destination;
      final handled = ManaBackHandler.handleBack(
        canPop: false,
        pop: () => fail('nothing to pop'),
        location: '/ow-006',
        goHome: (home) => destination = home,
      );
      expect(handled, isTrue);
      expect(destination, '/ow-001');
    });

    test('an empty stack AT home is not handled, so the app exits', () {
      final handled = ManaBackHandler.handleBack(
        canPop: false,
        pop: () => fail('nothing to pop'),
        location: '/ow-001',
        goHome: (_) => fail('already home'),
        );
      expect(handled, isFalse,
          reason: 'unhandled falls through to Flutter, which leaves the app -- '
              'which is what back means on a dashboard');
    });

    test('inside login, an empty stack exits rather than jumping to a dashboard', () {
      final handled = ManaBackHandler.handleBack(
        canPop: false,
        pop: () => fail('nothing to pop'),
        location: '/lr-009',
        goHome: (_) => fail('login has no workspace home'),
      );
      expect(handled, isFalse);
    });
  });
}
