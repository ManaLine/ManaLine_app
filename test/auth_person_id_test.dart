import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/login_registration/state/auth_flow_state.dart';

import 'support/mana_harness.dart';

/// Two copies of person_id, and only one of them survived a restart.
///
/// AuthFlowState.personId was written by setLoginResult and
/// setRegistrationResult — both of which only run while somebody is actually
/// logging in. On a cold start neither fires: main.dart hydrates ManaSession
/// from secure storage, the app comes up signed in, and this one stays null.
///
/// Nine screens read it. An Investor who reopened the app and pressed Send
/// Request threw StateError('No logged-in person_id available') inside
/// submitRequest, which was caught, parked in state.error, and never
/// rendered — so the request simply did not happen and nothing said why.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    seedSecureStorage();
    await ManaSession.instance.clear();
  });

  test('a restored session gives the auth state its person', () async {
    await ManaSession.instance.setSession(accessToken: 'tok', personId: '42');

    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(authFlowProvider).personId, '42',
        reason: 'the screens read this one; the session is what survives');
  });

  test('no session means no person, rather than a stale one', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(authFlowProvider).personId, isNull);
  });

  test('logging in still sets both', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(authFlowProvider.notifier).setLoginResult(
          personId: '7',
          token: 'tok',
          pinExists: true,
        );

    expect(container.read(authFlowProvider).personId, '7');
    expect(ManaSession.instance.currentPersonId, '7',
        reason: 'the two are written together and must not drift');
  });
}
