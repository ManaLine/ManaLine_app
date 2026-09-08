// Generates the tier table in site/plans.html from kOwnerTiers, the same
// tier data the app enforces (lib/features/owner_workspace/state/
// subscription_state.dart). Never edit the table in plans.html by hand —
// run this instead:
//
//   dart run tool/gen_site_plans.dart
//
// Why this parses the source file as text instead of `import`-ing it:
// subscription_state.dart pulls in flutter_riverpod and supabase_flutter,
// which drag in a native-asset build hook. Under the plain Dart VM (`dart
// run`, no Flutter engine attached) that hook's FFI use-site transformer
// crashes the kernel compiler outright — confirmed by reproducing the
// crash with an otherwise-empty file that only imports subscription_state
// .dart. `flutter test` doesn't hit this because the Flutter test runner
// carries the full toolchain, which is exactly why the sync guard
// (test/site_plans_sync_test.dart) imports the real library and this
// generator does not.
//
// Only `name`, `agents`, `customers` and `investors` are read out of the
// source. `monthly` and `yearly` are deliberately never matched or
// emitted here — billing is not live, and a price quoted to a stranger
// reads as an offer this app cannot yet take payment against.
// test/site_plans_sync_test.dart is the guard that would fail this if a
// price ever reached the file, whether from this generator or by hand.

import 'dart:io';

const _sourcePath =
    'lib/features/owner_workspace/state/subscription_state.dart';
const _startMarker = '<!-- GENERATED:TIERS START -->';
const _endMarker = '<!-- GENERATED:TIERS END -->';

class _Tier {
  final String name;
  final int? agents;
  final int? customers;
  final int? investors;
  _Tier(this.name, this.agents, this.customers, this.investors);
}

int? _parseCap(String raw) => raw.trim() == 'null' ? null : int.parse(raw.trim());

List<_Tier> _readTiersFromSource() {
  final source = File(_sourcePath).readAsStringSync();

  final listStart = source.indexOf('kOwnerTiers');
  if (listStart == -1) {
    throw StateError('kOwnerTiers not found in $_sourcePath');
  }
  final body = source.substring(listStart);

  // Each tier is a `SubscriptionTier(...)` constructor call with named
  // fields. Match name/agents/customers/investors individually rather than
  // the whole block, so field order in the source doesn't matter and
  // monthly/yearly are never captured by this generator at all.
  final tierBlocks =
      RegExp(r'SubscriptionTier\s*\(([\s\S]*?)\),').allMatches(body);

  final tiers = <_Tier>[];
  for (final block in tierBlocks) {
    final fields = block.group(1)!;
    final name = RegExp(r"""name:\s*'([^']*)'""").firstMatch(fields)?.group(1);
    final agents = RegExp(r'agents:\s*([\w]+)').firstMatch(fields)?.group(1);
    final customers =
        RegExp(r'customers:\s*([\w]+)').firstMatch(fields)?.group(1);
    final investors =
        RegExp(r'investors:\s*([\w]+)').firstMatch(fields)?.group(1);
    if (name == null || agents == null || customers == null || investors == null) {
      throw StateError('Could not parse a SubscriptionTier block: $fields');
    }
    tiers.add(_Tier(name, _parseCap(agents), _parseCap(customers), _parseCap(investors)));
  }

  if (tiers.isEmpty) {
    throw StateError('Parsed zero tiers out of kOwnerTiers in $_sourcePath');
  }
  return tiers;
}

String _cap(int? value) => value == null ? 'Unlimited' : _withThousands(value);

/// Renders an integer with comma thousands separators (e.g. 1500 -> "1,500"),
/// matching how the app itself formats figures. Caps here are always
/// non-negative counts, so no sign handling is needed.
String _withThousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _renderTiers(List<_Tier> tiers) {
  final rows = tiers.map((t) {
    return '''
          <tr>
            <th scope="row">${t.name}</th>
            <td>${_cap(t.agents)}</td>
            <td>${_cap(t.customers)}</td>
            <td>${_cap(t.investors)}</td>
          </tr>''';
  }).join('\n');

  return '''
      <table class="plans-table">
        <caption class="visually-hidden">Plan tiers and their agent, customer and investor limits</caption>
        <thead>
          <tr>
            <th scope="col">Plan</th>
            <th scope="col">Agents</th>
            <th scope="col">Customers</th>
            <th scope="col">Investors</th>
          </tr>
        </thead>
        <tbody>
$rows
        </tbody>
      </table>''';
}

void main() {
  final tiers = _readTiersFromSource();

  final file = File('site/plans.html');
  if (!file.existsSync()) {
    stderr.writeln(
        'site/plans.html does not exist yet — write the static shell first '
        '(header, footer, copy, and the two GENERATED:TIERS markers), then '
        'run this generator to fill in the table.');
    exitCode = 1;
    return;
  }

  final content = file.readAsStringSync();
  final startIdx = content.indexOf(_startMarker);
  final endIdx = content.indexOf(_endMarker);
  if (startIdx == -1 || endIdx == -1 || endIdx < startIdx) {
    stderr.writeln(
        'site/plans.html is missing the $_startMarker / $_endMarker markers.');
    exitCode = 1;
    return;
  }

  final before = content.substring(0, startIdx + _startMarker.length);
  final after = content.substring(endIdx);
  final updated = '$before\n${_renderTiers(tiers)}\n      $after';

  file.writeAsStringSync(updated);
  stdout.writeln('site/plans.html regenerated from kOwnerTiers '
      '(${tiers.length} tiers: ${tiers.map((t) => t.name).join(', ')}).');
}
