import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/customer_workspace/screens/cw_002_find_a_business.dart' as cw;
import 'package:mana_line/features/customer_workspace/state/customer_discovery_state.dart' as cws;
import 'package:mana_line/features/investor_workspace/screens/iw_002_find_a_business.dart' as iw;
import 'package:mana_line/features/investor_workspace/state/investor_discovery_state.dart' as iws;
import 'package:mana_line/shared/widgets/language_selector.dart';

import 'support/mana_harness.dart';

/// CW-002 and IW-002 draw a different body per DiscoveryPhase, and neither
/// screen had ever been laid out at text scale. A phase-blind test would
/// cover one of five bodies, so every phase is pumped.
///
/// The seeded business carries a long name and several operating areas
/// deliberately: a village list is exactly the kind of content that grows
/// without limit, and "Sri Satyanarayana Swamy Finance Corporation" is not an
/// unusual name for this book.
class _SeededCwDiscovery extends cws.CustomerDiscoveryNotifier {
  _SeededCwDiscovery(this._seed);
  final cws.CustomerDiscoveryState _seed;

  @override
  cws.CustomerDiscoveryState build() => _seed;
}

class _SeededIwDiscovery extends iws.InvestorDiscoveryNotifier {
  _SeededIwDiscovery(this._seed);
  final iws.InvestorDiscoveryState _seed;

  @override
  iws.InvestorDiscoveryState build() => _seed;
}

void main() {
  final areas = [
    'Srikalahasti — Uranduru Colony',
    'Puttur',
    'Renigunta',
    'Yerpedu',
  ];

  final cwBusiness = cws.DiscoveredBusiness(
    businessId: 'b1',
    businessName: 'Sri Satyanarayana Swamy Finance Corporation',
    mlbi: 'MLBI0000001234',
    operatingAreas: areas,
    acceptingNewCustomers: true,
  );

  final iwBusiness = iws.DiscoveredBusiness(
    businessId: 'b1',
    businessName: 'Sri Satyanarayana Swamy Finance Corporation',
    mlbi: 'MLBI0000001234',
    operatingAreas: areas,
    acceptingNewInvestors: true,
  );

  for (final phase in cws.DiscoveryPhase.values) {
    for (final scale in kManaTextScales) {
      for (final lang in [ManaLanguage.english, ManaLanguage.telugu]) {
        final tag = lang == ManaLanguage.telugu ? ' in Telugu' : '';

        testWidgets('CW-002 ${phase.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const cw.FindABusinessScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [
              cws.customerDiscoveryProvider.overrideWith(
                () => _SeededCwDiscovery(cws.CustomerDiscoveryState(
                  phase: phase,
                  query: 'Satyanarayana',
                  results: [cwBusiness],
                  selectedBusiness: cwBusiness,
                  lastRequest: cws.MembershipRequestResult(
                      requestId: 'r1',
                      status: phase == cws.DiscoveryPhase.rejected ? 'Rejected' : 'Pending',
                      cooldownUntil: DateTime(2026, 8, 28)),
                )),
              ),
            ],
          );
          expectNoLayoutFault(tester, 'CW-002 ${phase.name} at ${scale}x$tag');
        });

        testWidgets('IW-002 ${phase.name} survives text scale ${scale}x$tag', (tester) async {
          await pumpManaScreen(
            tester,
            const iw.FindABusinessScreen(businessId: 'b1'),
            textScale: scale,
            language: lang,
            overrides: [
              iws.investorDiscoveryProvider.overrideWith(
                () => _SeededIwDiscovery(iws.InvestorDiscoveryState(
                  phase: iws.DiscoveryPhase.values[phase.index],
                  query: 'Satyanarayana',
                  results: [iwBusiness],
                  selectedBusiness: iwBusiness,
                  lastRequest: iws.MembershipRequestResult(
                      requestId: 'r1',
                      status: phase == cws.DiscoveryPhase.rejected ? 'Rejected' : 'Pending',
                      cooldownUntil: DateTime(2026, 8, 28)),
                )),
              ),
            ],
          );
          expectNoLayoutFault(tester, 'IW-002 ${phase.name} at ${scale}x$tag');
        });
      }
    }
  }
}
