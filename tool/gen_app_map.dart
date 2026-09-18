// Generates docs/APP_MAP.md — the screen and route inventory — from the
// source itself. Never edit that file by hand; run this instead:
//
//   dart run tool/gen_app_map.dart
//
// WHY THIS IS GENERATED AND NOT WRITTEN.
//
// This repo's documented failure mode is a document that was true once.
// README's Status table drifted seven screens and 672 tests behind reality
// without anybody lying; CLAUDE.md's test count is older still. A hand-kept
// inventory of 83 routes would rot faster than either, because every screen
// edit is a chance to forget it.
//
// So the inventory is derived from `lib/app/router.dart` and the screen files
// themselves, and `test/app_map_sync_test.dart` fails when the committed
// document stops matching what this produces. A stale map cannot reach main.
//
// WHY IT PARSES TEXT INSTEAD OF IMPORTING THE ROUTER.
//
// Same reason as tool/gen_site_plans.dart, and the note at the top of that
// file is the long version: router.dart pulls in flutter_riverpod, go_router
// and supabase_flutter, which drag in a native-asset build hook that crashes
// the kernel compiler under a plain `dart run` with no Flutter engine
// attached. Text parsing keeps this runnable from a bare Dart VM. The guard
// test runs under `flutter test`, which has the full toolchain, and checks
// the OUTPUT rather than re-deriving it.
//
// WHAT IT DELIBERATELY DOES NOT CLAIM.
//
// It reports what a route builds, what arguments it accepts, who navigates to
// it and whether a test names it. It does not describe what a screen looks
// like or where its buttons sit: that is the fastest-rotting thing anybody
// could write down, the screen file is the truth, and the rules that govern
// placement across all screens are in docs/APP_FLOWS.md instead.

import 'dart:io';

/// The two routers, and the surface each one drives.
///
/// THERE ARE TWO ON PURPOSE. `manaRouter` is the handset app. `manaWebRouter`
/// is the restricted web build: collections, loans, day closure and reports
/// stay handset-only by design, so the web surface is deliberately a subset.
/// The long reasoning is at the top of `lib/app/web_router.dart`, and
/// `test/web_router_guard_test.dart` is the mitigation for having two.
///
/// Reading only one of them is how the first version of this generator
/// reported `/web-home` as a dead end at runtime. It is not; it is a web
/// route. A generated document that invents a bug costs more than it saves.
const _routers = <String, String>{
  'lib/app/router.dart': 'handset',
  'lib/app/web_router.dart': 'web',
};
const _outputPath = 'docs/APP_MAP.md';

/// A route as the router declares it.
class RouteEntry {
  RouteEntry(this.path);

  final String path;

  /// Widget classes the builder can return. More than one means the route
  /// chooses between them (or passes different arguments to the same screen).
  final Set<String> widgets = {};

  /// `?name=` values the route reads off the URL.
  final Set<String> queryParams = {};

  /// Whether the route reads go_router's `extra`, which does NOT survive a
  /// browser refresh or a pasted URL — the reason `_resolveBusinessId` exists.
  bool usesExtra = false;

  /// Types the builder casts `extra` to.
  final Set<String> extraTypes = {};

  /// A route that only redirects elsewhere, building nothing.
  String? redirectsTo;

  /// Which routers declare this path: `handset`, `web`, or both.
  final Set<String> surfaces = {};
}

/// Where a `context.go`/`push` to a route is written.
class NavEdge {
  NavEdge(this.fromFile, this.line, this.target, this.verb);
  final String fromFile;
  final int line;
  final String target;
  final String verb;
}

/// The document, as the sources say it should be.
///
/// Exposed so `test/app_map_sync_test.dart` can compare it against the
/// committed file without shelling out to a second Dart VM. Run from the
/// package root: every path here is relative to it, which is where both
/// `dart run` and `flutter test` start.
String buildAppMap() => _build().markdown;

/// Routes as parsed, for the guard test's own sanity checks. A parser that
/// quietly finds less is this generator's known failure mode — it once found
/// 7 routes out of 83 and said so without alarm.
List<RouteEntry> parsedRoutes() => _parseAllRouters();

/// One pass over the sources, producing the document and the counts that go
/// with it. Both callers need both, and scanning `lib/` twice to print a
/// summary line would be work for nothing.
({String markdown, List<RouteEntry> routes, List<NavEdge> edges, Map<String, List<NavEdge>> direct})
    _build() {
  final routes = _parseAllRouters();
  final classToFile = _mapClassesToFiles();
  final edges = _collectNavEdges(routes.map((r) => r.path).toSet());
  final testedClasses = _classesNamedInTests();
  final direct = _collectWidgetConstructions(
      routes.expand((r) => r.widgets).toSet(), classToFile);
  return (
    markdown: _render(routes, classToFile, edges, testedClasses, direct),
    routes: routes,
    edges: edges,
    direct: direct,
  );
}

void main(List<String> args) {
  final built = _build();
  final md = built.markdown;
  final routes = built.routes;
  final edges = built.edges;
  final direct = built.direct;

  final out = File(_outputPath);
  final changed = !out.existsSync() || out.readAsStringSync() != md;
  if (args.contains('--check')) {
    if (changed) {
      stderr.writeln('$_outputPath is out of date. Run: dart run tool/gen_app_map.dart');
      exit(1);
    }
    stdout.writeln('$_outputPath is current.');
    return;
  }
  out.writeAsStringSync(md);
  stdout.writeln(
      '${changed ? 'Wrote' : 'Unchanged'} $_outputPath — ${routes.length} routes, '
      '${edges.length} path references, '
      '${direct.values.fold<int>(0, (a, b) => a + b.length)} direct pushes '
      'of ${direct.length} screens.');
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Removes `//` and `/* */` comments, leaving string literals intact.
///
/// THIS IS NOT TIDINESS, IT IS THE BUG. The paren matcher below tracks quotes
/// so a bracket inside a string does not confuse it — and router.dart's
/// comments are full of apostrophes ("the screen's own note", "doesn't"). Each
/// one opened a string that never closed and swallowed the rest of the file:
/// the first run of this generator found 7 routes out of 83 and reported it
/// cheerfully. A parser that silently finds less is exactly the failure this
/// repo keeps meeting, so the guard test pins the route count too.
String _stripComments(String source) {
  final out = StringBuffer();
  String? quote;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (quote != null) {
      out.write(c);
      if (c == r'\') {
        if (next.isNotEmpty) out.write(next);
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      out.write('\n');
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < source.length && !(source[i] == '*' && source[i + 1] == '/')) {
        i++;
      }
      i++;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// Splits router.dart into `GoRoute( ... )` blocks by matching parentheses.
///
/// A regex cannot do this: builders contain nested calls, `switch` expressions
/// and string literals holding their own brackets. Counting depth while
/// skipping quoted text is the only reading that survives them.
List<String> _goRouteBlocks(String source) {
  final blocks = <String>[];
  const marker = 'GoRoute(';
  var i = 0;
  while (true) {
    final start = source.indexOf(marker, i);
    if (start < 0) break;
    final open = start + marker.length - 1;
    var depth = 0;
    var j = open;
    String? quote;
    var end = -1;
    for (; j < source.length; j++) {
      final c = source[j];
      if (quote != null) {
        if (c == r'\') {
          j++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        quote = c;
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) {
          end = j;
          break;
        }
      }
    }
    if (end < 0) break;
    blocks.add(source.substring(start, end + 1));
    // Advance past the marker, NOT past the block, so a `routes:` list nested
    // inside a GoRoute is still scanned. Neither router nests today; skipping
    // to `end` would mean the day somebody adds a sub-route, it vanishes from
    // the inventory without any complaint — the silent undercount this file
    // exists to avoid.
    i = start + marker.length;
  }
  return blocks;
}

final _pathRe = RegExp(r"""path:\s*'([^']+)'""");
final _queryRe = RegExp(r"""queryParameters\['([^']+)'\]""");
final _extraCastRe = RegExp(r'extra\s+(?:is|as)\s+([A-Z]\w+)');
final _sExtraCastRe = RegExp(r's\.extra\s+as\s+([A-Z]\w+)');
/// The builder's return, allowing an import alias in front of the class.
///
/// `cw006.MyProfileMembershipsScreen(...)` is how three routes name their
/// screen — the customer profile screen is imported under an alias because
/// two workspaces declare a class of the same name. Without the optional
/// `alias.` the regex starts matching at a capital that is not there, and
/// those routes parse as building nothing. The guard test's "every route
/// builds something or redirects somewhere" is what found this.
final _returnsWidgetRe = RegExp(r'(?:=>|return)\s+(?:const\s+)?(?:[a-z_]\w*\.)?([A-Z]\w+)\s*\(');
final _redirectRe = RegExp(r"""redirect:\s*\([^)]*\)\s*=>\s*'([^']+)'""");

/// Parses every router and merges them by path, so one row describes a route
/// and says which surfaces carry it.
List<RouteEntry> _parseAllRouters() {
  final merged = <String, RouteEntry>{};
  for (final entry in _routers.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) continue;
    for (final r in _parseRoutes(_stripComments(file.readAsStringSync()))) {
      final target = merged.putIfAbsent(r.path, () => RouteEntry(r.path));
      target.widgets.addAll(r.widgets);
      target.queryParams.addAll(r.queryParams);
      target.extraTypes.addAll(r.extraTypes);
      target.usesExtra = target.usesExtra || r.usesExtra;
      target.redirectsTo ??= r.redirectsTo;
      target.surfaces.add(entry.value);
    }
  }
  final list = merged.values.toList()..sort((a, b) => a.path.compareTo(b.path));
  return list;
}

List<RouteEntry> _parseRoutes(String source) {
  final entries = <RouteEntry>[];
  for (final block in _goRouteBlocks(source)) {
    final pathMatch = _pathRe.firstMatch(block);
    if (pathMatch == null) continue;
    final e = RouteEntry(pathMatch.group(1)!);

    for (final m in _queryRe.allMatches(block)) {
      e.queryParams.add(m.group(1)!);
    }
    e.usesExtra = block.contains('s.extra') || block.contains('.extra');
    for (final m in _extraCastRe.allMatches(block)) {
      e.extraTypes.add(m.group(1)!);
    }
    for (final m in _sExtraCastRe.allMatches(block)) {
      e.extraTypes.add(m.group(1)!);
    }
    for (final m in _returnsWidgetRe.allMatches(block)) {
      final name = m.group(1)!;
      // Argument holders and enums are cast from `extra`, not built as
      // screens; they reach this regex through `return X(...)` only when a
      // builder constructs one, which none do.
      if (e.extraTypes.contains(name)) continue;
      e.widgets.add(name);
    }
    final redirect = _redirectRe.firstMatch(block);
    if (redirect != null && e.widgets.isEmpty) {
      e.redirectsTo = redirect.group(1);
    }
    entries.add(e);
  }
  entries.sort((a, b) => a.path.compareTo(b.path));
  return entries;
}

/// Every widget class declared under `lib/`, mapped to the file — or FILES —
/// declaring it.
///
/// Built from the declarations rather than from router.dart's import list,
/// because an aliased import (`as cw002`) hides the class name and a shared
/// screen is imported from outside its own feature directory.
///
/// A LIST, NOT A SINGLE PATH, BECAUSE NAMES REPEAT. `FindABusinessScreen` and
/// `MyProfileMembershipsScreen` are each declared twice — once in the customer
/// workspace and once in the investor one — which is precisely why the router
/// imports them under aliases. Keeping only the first declaration named the
/// wrong file for one route of each pair, and made the self-reference check in
/// [_collectWidgetConstructions] exclude the wrong file, so a screen could be
/// counted as a way into itself. Both are listed; the reader decides.
Map<String, List<String>> _mapClassesToFiles() {
  final re = RegExp(r'^class\s+([A-Z]\w+)\s+extends\s', multiLine: true);
  final map = <String, List<String>>{};
  for (final f in _dartFilesUnder('lib')) {
    final src = f.readAsStringSync();
    for (final m in re.allMatches(src)) {
      (map[m.group(1)!] ??= []).add(_posix(f.path));
    }
  }
  return map;
}

final _routeLiteralRe = RegExp(r"""'(/[a-z0-9_\-]+)'""");
final _verbBeforeRe = RegExp(r'\.(go|push|replace|pushReplacement)\($');

/// Every place in `lib/` that names a declared route path.
///
/// TWO KINDS, AND THE DIFFERENCE MATTERS. A `context.go('/ow-009')` is a
/// navigation. A bare `'/ow-009'` inside a menu table — the owner dashboard
/// builds its tiles from a list of `(icon, label, path, badge)` records — is a
/// destination the app reaches through a variable, so no literal nav call
/// exists anywhere.
///
/// The first version of this generator only looked for nav calls and reported
/// the Daily Record Book, Day Closure and the whole owner menu as reached from
/// **nothing**. Six screens that a person uses every day read as orphans. An
/// inventory that is confidently wrong is worse than none, so both kinds are
/// collected and labelled, and only a route with neither is called out.
///
/// Still invisible: a path assembled at runtime from pieces. Nothing here
/// proves a screen unreachable — it proves nobody wrote its path down.
List<NavEdge> _collectNavEdges(Set<String> knownPaths) {
  final edges = <NavEdge>[];
  for (final f in _dartFilesUnder('lib')) {
    final path = _posix(f.path);
    if (path.endsWith('lib/app/router.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final m in _routeLiteralRe.allMatches(line)) {
        final target = m.group(1)!;
        final before = line.substring(0, m.start);
        final verb = _verbBeforeRe.firstMatch(before)?.group(1) ?? 'listed';
        // An unknown path is only interesting when something actually
        // navigates to it — that is a dead end at runtime. A bare unknown
        // string is just a string; `/storage/v1/...` is not a route.
        if (!knownPaths.contains(target) && verb == 'listed') continue;
        edges.add(NavEdge(path, i + 1, target, verb));
      }
    }
  }
  return edges;
}

/// Widget classes named anywhere under `test/`.
///
/// Presence is not proof of a good test — it is proof that something at least
/// mentions the screen, which is the weaker claim this document makes.
/// Screens constructed directly in `lib/`, outside the routers and outside
/// their own file — `Navigator.push(MaterialPageRoute(builder: (_) => X()))`.
///
/// THE THIRD WAY IN, AND THE ONE THAT NEARLY PUT A WRONG FINDING IN THIS
/// DOCUMENT. Cheti Management has no `'/ow-019'` anywhere outside the router,
/// so a map that only counts paths calls it an orphan. It is not: the business
/// management and migration screens push the widget itself. `/ow-019` is an
/// unused door into a room with two other doors.
///
/// A route is only reported as unreferenced when neither its path nor its
/// screen is named anywhere outside the routers.
Map<String, List<NavEdge>> _collectWidgetConstructions(
    Set<String> classes, Map<String, List<String>> classToFile) {
  final found = <String, List<NavEdge>>{};
  if (classes.isEmpty) return found;
  final re = RegExp(r'\b([A-Z]\w+)\s*\(');
  for (final f in _dartFilesUnder('lib')) {
    final path = _posix(f.path);
    if (_routers.containsKey(path)) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      for (final m in re.allMatches(line)) {
        final name = m.group(1)!;
        if (!classes.contains(name)) continue;
        // Its own file declares and may re-enter it; that is not a way in
        // from elsewhere. Asked of the declaration map rather than guessed
        // from the file name — `OwnerProfileScreen` lives in
        // `ow_016_profile.dart`, which no name-mangling rule predicts, and a
        // guess that misses counts a screen as reaching itself.
        if (classToFile[name]?.contains(path) ?? false) continue;
        found.putIfAbsent(name, () => []).add(NavEdge(path, i + 1, name, 'direct'));
      }
    }
  }
  return found;
}

Set<String> _classesNamedInTests() {
  final found = <String>{};
  final re = RegExp(r'\b([A-Z]\w*Screen)\b');
  for (final f in _dartFilesUnder('test')) {
    for (final m in re.allMatches(f.readAsStringSync())) {
      found.add(m.group(1)!);
    }
  }
  return found;
}

List<File> _dartFilesUnder(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  final files = d
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => _posix(a.path).compareTo(_posix(b.path)));
  return files;
}

String _posix(String p) => p.replaceAll(r'\', '/');

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

const _workspaces = <String, String>{
  '/lr-': 'Login & Registration',
  '/ow-': 'Owner',
  '/ag-': 'Agent',
  '/cw-': 'Customer',
  '/iw-': 'Investor',
  '/sp-': 'Support Admin',
  '/admin': 'Platform Admin',
};

String _workspaceOf(String path) {
  for (final e in _workspaces.entries) {
    if (path.startsWith(e.key)) return e.value;
  }
  return 'Shared / Utility';
}

String _render(
  List<RouteEntry> routes,
  Map<String, List<String>> classToFile,
  List<NavEdge> edges,
  Set<String> testedClasses,
  Map<String, List<NavEdge>> direct,
) {
  final b = StringBuffer();
  final byTarget = <String, List<NavEdge>>{};
  for (final e in edges) {
    byTarget.putIfAbsent(e.target, () => []).add(e);
  }

  b.writeln('# APP MAP — every screen, every route, who reaches it');
  b.writeln();
  b.writeln('<!-- GENERATED FILE. Do not edit by hand.');
  b.writeln('     Run: dart run tool/gen_app_map.dart');
  b.writeln('     Guarded by: test/app_map_sync_test.dart -->');
  b.writeln();
  b.writeln('Derived from both routers — `lib/app/router.dart` for the');
  b.writeln('handset, `lib/app/web_router.dart` for the restricted web build —');
  b.writeln('plus the screen files and `test/`,');
  b.writeln('by `tool/gen_app_map.dart`. It cannot go stale without failing');
  b.writeln('`flutter test`, which is the whole reason it is generated rather');
  b.writeln('than written.');
  b.writeln();
  b.writeln('**What this answers:** which file serves `/ow-005`, what arguments');
  b.writeln('it takes, what else in the app navigates to it, and whether');
  b.writeln('anything tests it.');
  b.writeln();
  b.writeln('**What it deliberately does not answer:** what a screen looks like');
  b.writeln('or where its buttons sit. That is in the screen file, which is 200');
  b.writeln('readable lines, and the placement rules that govern every screen');
  b.writeln('are in `docs/APP_FLOWS.md` §"Where things go".');
  b.writeln();

  // -- Summary --------------------------------------------------------------
  final built = routes.where((r) => r.widgets.isNotEmpty).length;
  final redirects = routes.where((r) => r.redirectsTo != null).length;
  b.writeln('## At a glance');
  b.writeln();
  b.writeln('| | |');
  b.writeln('|---|---|');
  b.writeln('| Routes declared | ${routes.length} |');
  b.writeln('| Routes that build a screen | $built |');
  b.writeln('| Routes that only redirect | $redirects |');
  b.writeln('| Distinct screen widgets | ${routes.expand((r) => r.widgets).toSet().length} |');
  b.writeln('| Literal navigation call sites | ${edges.length} |');
  b.writeln('| On the handset only | ${routes.where((r) => r.surfaces.length == 1 && r.surfaces.contains('handset')).length} |');
  b.writeln('| On the restricted web build | ${routes.where((r) => r.surfaces.contains('web')).length} |');
  b.writeln();

  // -- Per workspace --------------------------------------------------------
  final order = [
    'Login & Registration',
    'Owner',
    'Agent',
    'Customer',
    'Investor',
    'Support Admin',
    'Platform Admin',
    'Shared / Utility',
  ];
  for (final ws in order) {
    final rs = routes.where((r) => _workspaceOf(r.path) == ws).toList();
    if (rs.isEmpty) continue;
    b.writeln('## $ws');
    b.writeln();
    b.writeln('| Route | Screen | File | Takes | On | Reached from | Test |');
    b.writeln('|---|---|---|---|---|---|---|');
    for (final r in rs) {
      final widget = r.widgets.isEmpty
          ? (r.redirectsTo != null ? '_redirects to `${r.redirectsTo}`_' : '—')
          : r.widgets.map((w) => '`$w`').join('<br>');
      final files = r.widgets
          .expand((w) => classToFile[w] ?? const <String>[])
          .toSet()
          .map((f) => '`${f.replaceFirst('lib/', '')}`')
          .join('<br>');
      final takes = <String>[
        if (r.extraTypes.isNotEmpty)
          'extra: ${r.extraTypes.map((t) => '`$t`').join(', ')}'
        else if (r.usesExtra)
          'extra',
        ...r.queryParams.map((q) => '`?$q`'),
      ].join('<br>');
      final callers = byTarget[r.path] ?? const <NavEdge>[];
      final pushes = r.widgets.expand((w) => direct[w] ?? const <NavEdge>[]).length;
      final from = callers.isEmpty && pushes == 0
          ? '**nothing**'
          : [
              if (callers.isNotEmpty)
                '${callers.length} via path',
              if (pushes > 0) '$pushes direct',
            ].join('<br>');
      final tested = r.widgets.isEmpty
          ? '—'
          : (r.widgets.every(testedClasses.contains) ? 'yes' : '**no**');
      final on = r.surfaces.length == _routers.length
          ? 'both'
          : r.surfaces.join(', ');
      b.writeln('| `${r.path}` | $widget | ${files.isEmpty ? '—' : files} | '
          '${takes.isEmpty ? '—' : takes} | $on | $from | $tested |');
    }
    b.writeln();
  }

  // -- Navigation graph -----------------------------------------------------
  b.writeln('## Who navigates where');
  b.writeln();
  b.writeln('Every place in `lib/` that names a route path, by destination.');
  b.writeln('`go` / `push` / `replace` is a navigation call. `listed` is the');
  b.writeln('path sitting in a menu or tile table, reached through a variable —');
  b.writeln('the owner dashboard builds its whole menu that way, so those');
  b.writeln('screens have no literal nav call anywhere.');
  b.writeln();
  b.writeln('A path assembled at runtime appears in neither. Nothing here');
  b.writeln('proves a screen unreachable — only that nobody wrote its path.');
  b.writeln();
  final targets = byTarget.keys.toList()..sort();
  for (final t in targets) {
    final list = byTarget[t]!..sort((a, b) => a.fromFile.compareTo(b.fromFile));
    b.writeln('**`$t`** — ${list.length} call site${list.length == 1 ? '' : 's'}');
    b.writeln();
    for (final e in list) {
      b.writeln('- `${e.fromFile.replaceFirst('lib/', '')}:${e.line}` (`${e.verb}`)');
    }
    b.writeln();
  }

  // -- Orphans --------------------------------------------------------------
  b.writeln('## Worth a look');
  b.writeln();
  final unreached = routes
      .where((r) =>
          !byTarget.containsKey(r.path) &&
          r.redirectsTo == null &&
          !r.widgets.any((w) => (direct[w] ?? const []).isNotEmpty))
      .map((r) => r.path)
      .toList();
  b.writeln('**Routes with no way in that anybody wrote down** — neither the');
  b.writeln('path nor the screen is named anywhere outside the routers. Each');
  b.writeln('is reachable by typing the URL and, as far as the source shows,');
  b.writeln('no other way. Deep-link-only by design, or orphaned — check which');
  b.writeln('before assuming either:');
  b.writeln();
  if (unreached.isEmpty) {
    b.writeln('- none');
  } else {
    for (final p in unreached) {
      b.writeln('- `$p`');
    }
  }
  b.writeln();

  final dangling = byTarget.keys
      .where((t) => !routes.any((r) => r.path == t))
      .toList()
    ..sort();
  b.writeln('**Navigation targets with no matching route** — each one is a');
  b.writeln('dead end at runtime, not a compile error:');
  b.writeln();
  if (dangling.isEmpty) {
    b.writeln('- none');
  } else {
    for (final t in dangling) {
      final list = byTarget[t]!;
      b.writeln('- `$t` — from ${list.map((e) => '`${e.fromFile.replaceFirst('lib/', '')}:${e.line}`').join(', ')}');
    }
  }
  b.writeln();

  final untested = routes
      .where((r) => r.widgets.isNotEmpty && !r.widgets.every(testedClasses.contains))
      .map((r) => r.path)
      .toList();
  b.writeln('**Routes whose screen is not named in any test:**');
  b.writeln();
  if (untested.isEmpty) {
    b.writeln('- none');
  } else {
    for (final p in untested) {
      b.writeln('- `$p`');
    }
  }
  b.writeln();

  return b.toString();
}
