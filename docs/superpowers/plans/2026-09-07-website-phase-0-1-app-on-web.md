# MANA LINE on the Web — Plan 1: The App on the Web

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing Flutter app usable in a browser — every route reachable, nothing crashing on a missing plugin — without changing a single thing about how it behaves on Android.

**Architecture:** The app does not fork. A width clamp installed at one place in `main.dart` renders every screen as a centred phone-width column on a wide viewport. Platform-specific code is separated by *conditional import* rather than by a runtime `kIsWeb` check wherever a `dart:io` type appears in a signature, so `dart:io` is never compiled into the web bundle at all.

**Tech Stack:** Flutter (dart2js/CanvasKit), `package:web` for browser APIs, `share_plus`/`file_selector` (already dependencies), `flutter_test`.

## Global Constraints

- **Android behaviour must not change.** The width clamp is inert below 600 px logical width; every other change is behind a platform branch. Any task that alters an Android-visible behaviour is a task written wrong.
- **Money-path files are not touched by this plan.** Not one file under a `*_ledger*`, `*_collection*`, `*_loan_math*` path is modified. If a task appears to need one, stop and flag it.
- **Screen IDs are the routing contract.** No route is added, removed, or renamed. `lib/app/router.dart` is not modified by this plan.
- **`flutter analyze` must be clean on every touched file before a task is called done.**
- **The existing suite (2,191 tests) must stay green after every task.** It is the regression net for the ~65 screens nobody is editing.
- **Compiling is not running.** A task whose deliverable is reachable in a browser is not done until it has been *opened in a browser*. `flutter build web` succeeding proves only that the graph resolves — it already succeeded with `dart:io` imported in three services that would throw on first use.
- Encoding: files are UTF-8, no BOM. `test/source_encoding_test.dart` enforces this over `lib/` and `tool/`.
- Never commit credentials. Web builds take `--dart-define` exactly as Android does.

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `lib/design/tokens/breakpoints.dart` | The width numbers, and the set of routes exempt from the clamp. Data only. |
| `lib/design/components/mana_web_frame.dart` | The clamp widget. One job: constrain and centre. |
| `lib/shared/mana_file_share.dart` | Public API for "hand these bytes to the user as a file". Conditional import. |
| `lib/shared/mana_file_share_io.dart` | Android/iOS implementation — temp file + `SharePlus`. |
| `lib/shared/mana_file_share_web.dart` | Web implementation — Blob + download anchor. |
| `lib/shared/mana_token_store.dart` | Public API for session persistence. Conditional import. |
| `lib/shared/mana_token_store_io.dart` | `FlutterSecureStorage` — today's behaviour, unchanged. |
| `lib/shared/mana_token_store_web.dart` | `sessionStorage` — dies with the tab. |
| `test/web_plugin_fallback_test.dart` | Guard: no unguarded web-hostile API in `lib/`. |
| `test/web_shell_test.dart` | Guard: the Flutter boilerplate never ships. |
| `test/mana_web_frame_test.dart` | The clamp behaves at three widths. |

**Modified:**

| File | Change |
|---|---|
| `lib/main.dart:166` | Wrap `child!` in `ManaWebFrame`. |
| `lib/shared/ledger_statement_service.dart:191-197` | Use `manaShareBytes`. |
| `lib/features/owner_workspace/state/backup_export_service.dart:302-309` | Use `manaShareBytes`. |
| `lib/features/owner_workspace/state/import_service.dart:157-163` | Use `manaShareBytes`. |
| `lib/features/owner_workspace/state/bulk_onboarding_service.dart` | Drop the `dart:io` import. |
| `lib/shared/mana_biometric.dart:47` | Unavailable on web. |
| `lib/shared/mana_location.dart:201` | No reverse-geocoding on web. |
| `lib/shared/live_face_capture_screen.dart` | Upload instead of live capture on web. |
| `lib/features/login_registration/state/auth_flow_state.dart:400` | `ManaTokenStore` instead of `FlutterSecureStorage`. |
| `web/index.html`, `web/manifest.json` | Real title, description, theme colour, icons. |
| `pubspec.yaml` | Add `web`. |

**Why three services collapse into one helper:** all three do the identical four lines — `getTemporaryDirectory()`, `File(...)`, `writeAsBytes`, `SharePlus`. That is triplicated code today and the only reason `dart:io` is in those files. One helper removes the duplication and the web problem in the same edit.

---

### Task 1: The width clamp

**Files:**
- Create: `lib/design/tokens/breakpoints.dart`
- Create: `lib/design/components/mana_web_frame.dart`
- Create: `test/mana_web_frame_test.dart`
- Modify: `lib/main.dart:166-190` (the `builder:` callback)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `ManaBreakpoints.compact` = `600.0`, `ManaBreakpoints.columnMax` = `480.0`
  - `Set<String> kManaWideRoutes` — empty in this plan; Plan 2 adds route paths to it.
  - `class ManaWebFrame extends StatelessWidget { const ManaWebFrame({super.key, required Widget child, required String Function() currentLocation}); }`

- [ ] **Step 1: Write the failing test**

Create `test/mana_web_frame_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/design/components/mana_web_frame.dart';
import 'package:mana_line/design/tokens/breakpoints.dart';

/// The clamp exists so ~85 handset screens are legible in a desktop browser
/// without laying any of them out again. Its most important property is the
/// one asserted first: BELOW the breakpoint it does nothing at all, so the
/// Android build cannot be affected by it.
void main() {
  Future<double> widthOfChildAt(WidgetTester tester, double surface,
      {String location = '/ow-001'}) async {
    tester.view.physicalSize = Size(surface, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: ManaWebFrame(
        currentLocation: () => location,
        child: Container(key: const Key('content'), color: Colors.red),
      ),
    ));
    return tester.getSize(find.byKey(const Key('content'))).width;
  }

  testWidgets('a handset width is untouched', (tester) async {
    expect(await widthOfChildAt(tester, 360), 360);
  });

  testWidgets('a desktop width is clamped and centred', (tester) async {
    expect(await widthOfChildAt(tester, 1440), ManaBreakpoints.columnMax);
  });

  testWidgets('a route in kManaWideRoutes keeps the full width', (tester) async {
    // Plan 2 opts each responsive workflow out by adding its path here. Until
    // a screen has actually been laid out for a wide window, being clamped is
    // the correct outcome, not a limitation.
    kManaWideRoutes.add('/test-wide');
    addTearDown(() => kManaWideRoutes.remove('/test-wide'));
    expect(await widthOfChildAt(tester, 1440, location: '/test-wide'), 1440);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/mana_web_frame_test.dart
```

Expected: compile failure — `Target of URI doesn't exist: 'package:mana_line/design/components/mana_web_frame.dart'`.

- [ ] **Step 3: Write the tokens**

Create `lib/design/tokens/breakpoints.dart`:

```dart
/// Where the layout changes its mind.
///
/// The design system had NO breakpoint before this file — not one
/// `MediaQuery...size.width` in lib/design/ or lib/shared/. Every screen was
/// built for a 360x640 handset and tested at that surface, which is why the
/// web answer is to clamp rather than to reflow: reflowing ~85 screens would
/// re-open the overflow bug class that has already shipped four times.
class ManaBreakpoints {
  const ManaBreakpoints._();

  /// Below this, a viewport is a handset and nothing here applies. Every
  /// Android device this app targets sits under it, which is what makes the
  /// clamp incapable of changing the Android build.
  static const compact = 600.0;

  /// How wide the centred column is allowed to get. Roughly a large handset,
  /// so the screens render in the shape they were designed and tested in.
  static const columnMax = 480.0;
}

/// Routes that have been laid out for a wide window and must NOT be clamped.
///
/// Empty on purpose. Plan 2 adds a path here as each of the five workflows
/// becomes genuinely responsive — so a screen is only ever let out of the
/// column once somebody has laid it out and tested it at that width.
///
/// Mutable rather than const because the widget test needs to add and remove
/// an entry; nothing in the app writes to it at runtime.
final Set<String> kManaWideRoutes = <String>{};
```

- [ ] **Step 4: Write the clamp**

Create `lib/design/components/mana_web_frame.dart`:

```dart
import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/colors.dart';

/// Renders the app as a centred, phone-width column when the window is wider
/// than a phone.
///
/// WHY A CLAMP AND NOT A RESPONSIVE PASS: the app is ~85 screens, all built
/// and tested against a 360x640 surface. Dropped into a 1440px window a
/// full-width Column stretches its buttons to 1400px and its cards into
/// unreadable bands. Laying all of them out again would re-open the overflow
/// bug class that has shipped four times here. Clamping makes every screen
/// legible on day one, from ONE edit, with no per-screen step to forget.
///
/// The route check is how a screen escapes: once a workflow has actually been
/// laid out for a wide window, its path goes in [kManaWideRoutes] and this
/// widget stops constraining it. Opt-in, so an unconverted screen cannot
/// accidentally be let out.
///
/// [currentLocation] is injected rather than read from the global router
/// because this widget sits ABOVE the Navigator, where `GoRouterState.of`
/// does not resolve — and because a callback is what makes it testable
/// without standing up a router.
class ManaWebFrame extends StatelessWidget {
  final Widget child;
  final String Function() currentLocation;

  const ManaWebFrame({
    super.key,
    required this.child,
    required this.currentLocation,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < ManaBreakpoints.compact ||
        kManaWideRoutes.contains(currentLocation())) {
      return child;
    }

    return ColoredBox(
      color: ManaColors.surfaceMuted,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: ManaBreakpoints.columnMax),
          child: child,
        ),
      ),
    );
  }
}
```

Note: if `ManaColors` has no `surfaceMuted`, use the darkest neutral surface token that exists — read `lib/design/tokens/colors.dart` and pick it; do not add a token in this task.

- [ ] **Step 5: Run the test — expect PASS**

```bash
flutter test test/mana_web_frame_test.dart
```

Expected: 3 tests pass.

- [ ] **Step 6: Wire it into the app**

In `lib/main.dart`, inside the existing `builder:` at line 166, wrap the `child!` that is currently passed to `MediaQuery`:

```dart
          child: ManaWebFrame(
            currentLocation: () =>
                manaRouter.routerDelegate.currentConfiguration.uri.path,
            child: child!,
          ),
```

Add the import beside the other design imports:

```dart
import 'design/components/mana_web_frame.dart';
```

Leave the surrounding `MediaQuery`/`textScaler` code exactly as it is, and leave the "NO SelectionArea here" comment in place — it documents a real outage and the clamp does not change that constraint.

- [ ] **Step 7: Verify Android is untouched, then the suite**

```bash
flutter analyze lib/main.dart lib/design/components/mana_web_frame.dart lib/design/tokens/breakpoints.dart
flutter test
```

Expected: analyze clean; all tests pass, including the existing layout-fault tests — they pump at 360 wide, where the clamp is inert. If any existing test's layout changed, the clamp is firing on a handset width and is wrong.

- [ ] **Step 8: Commit**

```bash
git add lib/design/tokens/breakpoints.dart lib/design/components/mana_web_frame.dart test/mana_web_frame_test.dart lib/main.dart
git commit -m "Eighty-five handset screens become legible in a browser from one edit"
```

---

### Task 2: The web shell stops saying "A new Flutter project"

**Files:**
- Modify: `web/index.html`
- Modify: `web/manifest.json`
- Create: `test/web_shell_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by later tasks.

`web/index.html` is untouched Flutter boilerplate today: `<title>mana_line</title>` and `<meta name="description" content="A new Flutter project.">`. That is what a browser tab, a bookmark, and a link preview would show.

- [ ] **Step 1: Write the failing test**

Create `test/web_shell_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web shell is a file nobody looks at after the first day, which is
/// exactly why it ships wrong. Flutter's default index.html titles the tab
/// `mana_line` and describes the product as "A new Flutter project." — text
/// that reaches a bookmark, a browser tab and a shared link preview.
void main() {
  test('index.html carries no Flutter boilerplate', () {
    final html = File('web/index.html').readAsStringSync();

    expect(html, isNot(contains('A new Flutter project')),
        reason: 'The default description is still in web/index.html.');
    expect(html, isNot(contains('<title>mana_line</title>')),
        reason: 'The browser tab still says mana_line.');
    expect(html, contains('<title>MANA LINE</title>'));
    expect(html, contains(r'<base href="$FLUTTER_BASE_HREF">'),
        reason: 'The base href placeholder must survive — --base-href=/app/ '
            'substitutes it at build time, and every asset path depends on it.');
  });

  test('the manifest names the product, not the package', () {
    final manifest = File('web/manifest.json').readAsStringSync();
    expect(manifest, isNot(contains('A new Flutter project')));
    expect(manifest, contains('MANA LINE'));
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/web_shell_test.dart
```

Expected: FAIL — "The default description is still in web/index.html."

- [ ] **Step 3: Fix `web/index.html`**

Replace the `<meta name="description">`, `<title>`, and apple title lines. Keep `<base href="$FLUTTER_BASE_HREF">`, the manifest link, the favicon link and the `flutter_bootstrap.js` script exactly as they are.

```html
  <meta name="description" content="MANA LINE — the operating system for a local lending business. Loans, collections, agents and daily accounts, in five languages.">
  <meta name="apple-mobile-web-app-title" content="MANA LINE">
  <meta name="theme-color" content="#0B2545">
  <title>MANA LINE</title>
```

Use the app's own primary navy for `theme-color`; read the exact hex from `lib/design/tokens/colors.dart` rather than trusting the value above.

- [ ] **Step 4: Fix `web/manifest.json`**

Set `"name": "MANA LINE"`, `"short_name": "MANA LINE"`, and a `"description"` matching the meta tag. Leave the `icons` array alone — those files exist.

- [ ] **Step 5: Run the test — expect PASS**

```bash
flutter test test/web_shell_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add web/index.html web/manifest.json test/web_shell_test.dart
git commit -m "The browser tab said mana_line and the description said A new Flutter project"
```

---

### Task 3: The guard that makes the rest of this plan mandatory

**Files:**
- Create: `test/web_plugin_fallback_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: a failing test that Tasks 4–8 turn green, one file at a time.

This task deliberately ends RED. It is the specification for the remaining tasks, expressed as something that fails rather than something somebody has to remember.

- [ ] **Step 1: Write the guard**

Create `test/web_plugin_fallback_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Four plugins and one core library compile for the web and throw when used.
///
/// `flutter build web` succeeds today with `dart:io` imported in three
/// services and `camera` in a fourth — dart2js accepts every one of them,
/// because the web SDK ships dart:io as a STUB that compiles and throws on
/// use, and a plugin with no web implementation only fails when its method
/// channel is called. So the build says nothing at all about whether the app
/// works in a browser, and the failure surfaces on a screen, in front of an
/// Owner, on first use.
///
/// Two ways a file may hold one of these, and only two:
///
///  1. Conditional import — the file is named `*_io.dart` and is only ever
///     reached through a `dart.library.io` conditional export. Preferred: the
///     web bundle then never compiles it at all.
///  2. A `kIsWeb` branch in the same file, for a plugin whose Dart API has no
///     `dart:io` types in its signatures and can simply be skipped.
const _webHostile = <String, String>{
  "import 'dart:io'": 'dart:io is a stub on web and throws on use',
  'package:camera/': 'camera has no web implementation',
  'package:google_mlkit_face_detection/':
      'ML Kit face detection has no web implementation',
  'package:local_auth/': 'local_auth has no web implementation',
  'package:geocoding/': 'geocoding has no web implementation',
};

void main() {
  test('no web-hostile API is reachable from a web build unguarded', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // A scan that finds nothing passes without checking anything.
    expect(dartFiles.length, greaterThan(100),
        reason: 'Only ${dartFiles.length} files scanned — lib/ moved and this '
            'guard is checking almost nothing.');

    final offenders = <String>[];

    for (final file in dartFiles) {
      // Platform-specific halves of a conditional import are the sanctioned
      // home for this code — the web bundle never compiles them.
      if (file.path.endsWith('_io.dart')) continue;

      final source = file.readAsStringSync();
      final guarded = source.contains('kIsWeb');

      for (final entry in _webHostile.entries) {
        if (source.contains(entry.key) && !guarded) {
          offenders.add('${file.path}: ${entry.key} — ${entry.value}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Reachable on web and will throw at runtime:\n'
            '${offenders.join("\n")}\n\n'
            'Move it behind a conditional import (a *_io.dart half) or a '
            'kIsWeb branch with a real fallback. Not a silent catch.');
  });
}
```

- [ ] **Step 2: Run it and record exactly what it names**

```bash
flutter test test/web_plugin_fallback_test.dart
```

Expected: FAIL, naming six files — `ledger_statement_service.dart`, `backup_export_service.dart`, `import_service.dart`, `bulk_onboarding_service.dart`, `mana_biometric.dart`, `mana_location.dart`. `live_face_capture_screen.dart` already contains `kIsWeb` and will not be listed; Task 7 handles it regardless, because the existing branches assume a camera exists.

Write the actual list down. If it names a file not in that list, a new call site appeared and belongs in this plan — flag it before continuing.

- [ ] **Step 3: Commit the guard, red**

```bash
git add test/web_plugin_fallback_test.dart
git commit -m "A guard for the five APIs that compile on web and throw when used"
```

Committing a failing test is deliberate here: the next five tasks are its GREEN, and a guard added after the fixes would never have been proven to fire.

---

### Task 4: One helper replaces four lines of `dart:io`, three times over

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/shared/mana_file_share.dart`
- Create: `lib/shared/mana_file_share_io.dart`
- Create: `lib/shared/mana_file_share_web.dart`
- Create: `test/mana_file_share_test.dart`
- Modify: `lib/shared/ledger_statement_service.dart:191-197`
- Modify: `lib/features/owner_workspace/state/backup_export_service.dart:302-309`
- Modify: `lib/features/owner_workspace/state/import_service.dart:157-163`
- Modify: `lib/features/owner_workspace/state/bulk_onboarding_service.dart` (import line only)

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<void> manaShareBytes({required Uint8List bytes, required String fileName, String? subject})`

All three services do the identical thing: build bytes, write them to a temp file, hand the path to `SharePlus`. That duplication is the only reason `dart:io` is in any of them.

- [ ] **Step 1: Add the dependency**

```bash
flutter pub add web
```

Run the command rather than hand-editing a version into `pubspec.yaml` — the existing `supabase_flutter` comment records what happens when a version is guessed instead of resolved.

- [ ] **Step 2: Write the failing test**

Create `test/mana_file_share_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/shared/mana_file_share.dart';

/// The helper's contract is thin on purpose: bytes in, a file in front of the
/// user, and a filename that survives. The platform halves are exercised on
/// their platforms — what a unit test can hold honestly is that the API
/// exists and rejects the two inputs that would produce a nameless download.
void main() {
  test('a filename is required and must not be blank', () {
    expect(
      () => manaShareBytes(bytes: Uint8List(0), fileName: ''),
      throwsArgumentError,
    );
  });
}
```

Add `import 'dart:typed_data';` at the top of the test.

- [ ] **Step 3: Run it and watch it fail**

```bash
flutter test test/mana_file_share_test.dart
```

Expected: compile failure — `mana_file_share.dart` does not exist.

- [ ] **Step 4: Write the three halves**

`lib/shared/mana_file_share.dart`:

```dart
import 'dart:typed_data';

import 'mana_file_share_io.dart'
    if (dart.library.js_interop) 'mana_file_share_web.dart' as impl;

/// Hand [bytes] to the person as a file called [fileName].
///
/// WHY THIS EXISTS: three services — the ledger statement, the backup export
/// and the loan-import template — each carried the same four lines:
/// getTemporaryDirectory, File(...), writeAsBytes, SharePlus. That is
/// triplicated code, and it is the ONLY reason dart:io appeared in any of
/// them. On the web dart:io is a stub that compiles and throws on use, so all
/// three would have failed in a browser at the moment somebody pressed
/// Export — the point at which they had already waited for the file to build.
///
/// A conditional import rather than a `kIsWeb` branch, because the branch
/// would still have to COMPILE `File` on web. This way the web bundle never
/// sees dart:io at all.
Future<void> manaShareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) {
  if (fileName.trim().isEmpty) {
    throw ArgumentError.value(
        fileName, 'fileName', 'A download with no filename is unopenable');
  }
  return impl.shareBytes(bytes: bytes, fileName: fileName, subject: subject);
}
```

`lib/shared/mana_file_share_io.dart` — this is today's code, moved, not rewritten:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Android/iOS: a real file in the temp directory, handed to the system share
/// sheet. Unchanged from what the three services each did inline.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: fileName)],
      subject: subject,
    ),
  );
}
```

`lib/shared/mana_file_share_web.dart`:

```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: a Blob and a click on an invisible anchor — the plain browser
/// download, not the Web Share API.
///
/// Web Share with files is unevenly supported (Firefox does not have it at
/// all), and an export that silently does nothing on one browser is exactly
/// the failure this whole task exists to remove. A download works everywhere.
Future<void> shareBytes({
  required Uint8List bytes,
  required String fileName,
  String? subject,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  anchor.click();
  // Revoked on the next turn of the event loop: revoking synchronously can
  // beat the browser to reading the URL the click just queued.
  Future<void>.delayed(Duration.zero, () => web.URL.revokeObjectURL(url));
}
```

- [ ] **Step 5: Run the test — expect PASS**

```bash
flutter test test/mana_file_share_test.dart
```

- [ ] **Step 6: Adopt it in all three services**

In each of the three, delete the four-line block and call the helper. `ledger_statement_service.dart:191-197` becomes:

```dart
    await manaShareBytes(
      bytes: result.bytes,
      fileName: result.fileName,
      subject: /* keep whatever subject the existing ShareParams passed */,
    );
```

Then remove the now-unused `dart:io` and `path_provider` imports from each file — `flutter analyze` will name them. Do the same in `backup_export_service.dart:302-309` and `import_service.dart:157-163`, whose filename is the literal `'ManaLine-Loan-Import-Template.xlsx'`.

For `bulk_onboarding_service.dart`, remove only the `dart:io` import. Its byte-building and `_decodeTable` parsing already work on `Uint8List` and touch no file paths — confirm with `flutter analyze` that nothing else in the file needed it.

**Before editing each file, read the surrounding lines.** These are export paths, and one of them (`backup_export_service`) writes an Owner's whole book. The `subject:` argument and the exact filename are behaviour that must survive verbatim.

- [ ] **Step 7: Run the guard and the suite**

```bash
flutter test test/web_plugin_fallback_test.dart
flutter analyze
flutter test
```

Expected: the guard now names two files, not six — `mana_biometric.dart` and `mana_location.dart`. Analyze clean. Full suite green.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/shared/mana_file_share*.dart test/mana_file_share_test.dart lib/shared/ledger_statement_service.dart lib/features/owner_workspace/state/backup_export_service.dart lib/features/owner_workspace/state/import_service.dart lib/features/owner_workspace/state/bulk_onboarding_service.dart
git commit -m "The same four lines of dart:io, in three services, become one helper"
```

---

### Task 5: Fingerprint unlock, on a machine with no fingerprint reader

**Files:**
- Modify: `lib/shared/mana_biometric.dart:47`

**Interfaces:**
- Consumes: nothing.
- Produces: no signature change. `ManaBiometric.isAvailable()` keeps returning `Future<bool>`.

`local_auth` has no web implementation, so `isAvailable()` throws rather than returning false — and every caller reads a throw as a crash, not as "no reader here".

- [ ] **Step 1: Add the branch**

At the top of `ManaBiometric.isAvailable()`:

```dart
    // No web implementation of local_auth, so the plugin THROWS here rather
    // than answering false. Every caller treats this method as the question
    // "may I offer the fingerprint button?", and on a browser the honest
    // answer is no — the password path they already have is the whole
    // fallback, so nothing else needs to change.
    if (kIsWeb) return false;
```

Add `import 'package:flutter/foundation.dart' show kIsWeb;`.

- [ ] **Step 2: Verify no caller needed more**

```bash
grep -rn "ManaBiometric\." lib --include=*.dart
```

Read every hit. Confirm each one gates the fingerprint UI on `isAvailable()` and has a password path when it is false. **If any caller calls `authenticate()` without checking `isAvailable()` first, that caller is a second consumer and must be fixed in this task** — that shape (three sites updated, the rest silently broken) is the exact regression this project keeps hitting.

- [ ] **Step 3: Run the guard and the suite**

```bash
flutter analyze lib/shared/mana_biometric.dart
flutter test
```

- [ ] **Step 4: Commit**

```bash
git add lib/shared/mana_biometric.dart
git commit -m "A browser has no fingerprint reader, and local_auth threw rather than saying so"
```

---

### Task 6: "Use my location" without a platform geocoder

**Files:**
- Modify: `lib/shared/mana_location.dart:201` (`currentPlace`)

**Interfaces:**
- Consumes: nothing.
- Produces: no signature change. `ManaLocation.currentPlace()` keeps returning `Future<ManaPlace>`.

`geolocator` works on the web; `geocoding` does not. So coordinates are obtainable and turning them into a village name is not.

- [ ] **Step 1: Read what `ManaPlace` can express**

```bash
sed -n '238,272p' lib/shared/mana_location.dart
```

The fallback must be a value `ManaPlace` can already carry — an empty or unresolved place. Do not add a field in this task.

- [ ] **Step 2: Add the branch**

At the top of `currentPlace()`:

```dart
    // geolocator has a web implementation; geocoding does not. So on the web a
    // coordinate is obtainable and a VILLAGE NAME is not — and a village name
    // is the only part of this the address forms actually use.
    //
    // Returning an unresolved place rather than throwing, because the address
    // forms already handle it: the PIN-code + village reference lookup is the
    // primary path on every one of them, and "use my location" is the
    // shortcut. Losing a shortcut in a browser is not an error state.
    if (kIsWeb) return const ManaPlace.unresolved();
```

If `ManaPlace` has no `unresolved` constructor, construct the equivalent empty instance the existing failure path already returns — read the method's own error branch and match it exactly.

Add `import 'package:flutter/foundation.dart' show kIsWeb;`.

- [ ] **Step 3: Check every consumer**

```bash
grep -rn "currentPlace\|ManaLocation\." lib --include=*.dart
```

Each address editor must show its PIN + village fields when the place comes back unresolved, not an error toast. Read each one.

- [ ] **Step 4: Run the guard and the suite**

```bash
flutter test test/web_plugin_fallback_test.dart
flutter analyze lib/shared/mana_location.dart
flutter test
```

Expected: the guard is now GREEN. Full suite green.

- [ ] **Step 5: Commit**

```bash
git add lib/shared/mana_location.dart
git commit -m "geolocator works in a browser and geocoding does not, so the village name has to be typed"
```

---

### Task 7: Face capture, where there is no camera plugin

**Files:**
- Modify: `lib/shared/live_face_capture_screen.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: no signature change — the screen returns the same result type it does today.

This screen already branches on `kIsWeb` in nine places, and every branch assumes the `camera` plugin *works* on web and only ML Kit is missing (`_faceDetected = kIsWeb`, i.e. "assume a face is there"). `camera` has no web implementation in this dependency set, so `availableCameras()` throws before any of that runs.

- [ ] **Step 1: Read the whole file first**

```bash
sed -n '1,180p' lib/shared/live_face_capture_screen.dart
```

413 lines, and it is on the customer-onboarding path — one of the five workflows. Understand the existing `kIsWeb` branches before adding a tenth.

- [ ] **Step 2: Replace the camera path on web with an upload**

On web, do not initialise a controller at all. Present the same screen chrome with a single "Choose a photo" action backed by `file_selector` (already a dependency), and return the selected bytes through the exact same result path the capture button uses today.

The photo requirement itself does not relax: whatever validation the captured image goes through — size, format, the `image` package processing — runs identically on the uploaded bytes. A face photo that skipped validation because it arrived by a different door would be a hole in customer onboarding, not a convenience.

- [ ] **Step 3: Say plainly why it is different**

The screen must tell the person, not silently offer a different control:

> Live capture needs a phone camera. On a computer, choose a recent photo instead — the same photo rules apply.

- [ ] **Step 4: Verify in a browser**

```bash
flutter build web --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Then serve `build/web`, open the onboarding flow, and reach this screen. **Select a real photo and complete the flow.** This is the task most likely to be reported done on the strength of the code reading correctly; the whole point of the task is that the previous `kIsWeb` branches read correctly too and were wrong.

- [ ] **Step 5: Run analyze and the suite**

```bash
flutter analyze lib/shared/live_face_capture_screen.dart
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/shared/live_face_capture_screen.dart
git commit -m "The web branches here assumed a camera plugin that has no web implementation"
```

---

### Task 8: The session token does not outlive the tab

**Files:**
- Create: `lib/shared/mana_token_store.dart`
- Create: `lib/shared/mana_token_store_io.dart`
- Create: `lib/shared/mana_token_store_web.dart`
- Modify: `lib/features/login_registration/state/auth_flow_state.dart:400`

**Interfaces:**
- Consumes: `package:web` (added in Task 4).
- Produces: `class ManaTokenStore { const ManaTokenStore(); Future<void> write({required String key, required String? value}); Future<String?> read({required String key}); Future<void> delete({required String key}); }` — deliberately the same three method shapes `FlutterSecureStorage` offers, so the call sites do not change.

`flutter_secure_storage` on the web is `localStorage` plus WebCrypto — confirmed by the wasm dry run naming `flutter_secure_storage_web` pulling in `dart:html`. `ManaSession` persists the custom JWT carrying the `person_id` claim. On Android that token sits in the Keystore; in `localStorage` any XSS on the origin can read it, and it survives the browser being closed.

Decision (a) in the spec: on web, memory plus `sessionStorage`, so the token dies with the tab.

- [ ] **Step 1: Write the platform-neutral API**

`lib/shared/mana_token_store.dart`:

```dart
import 'mana_token_store_io.dart'
    if (dart.library.js_interop) 'mana_token_store_web.dart' as impl;

/// Where the session token lives.
///
/// Android and iOS: flutter_secure_storage, i.e. the Keystore — exactly what
/// ManaSession used before this file existed, unchanged.
///
/// Web: sessionStorage. flutter_secure_storage's web implementation is
/// localStorage, which any XSS on the origin can read and which SURVIVES the
/// browser closing. The token carries the person_id claim that RLS trusts, so
/// on a shared or public machine a localStorage token is a signed-in session
/// left behind for the next person. sessionStorage dies with the tab; the cost
/// is that a web user re-enters their PIN after closing it, which for a
/// lending book is the right side of the trade.
///
/// The one-hour expiry bounds this either way. It does not remove it.
class ManaTokenStore {
  const ManaTokenStore();

  Future<void> write({required String key, required String? value}) =>
      impl.write(key, value);

  Future<String?> read({required String key}) => impl.read(key);

  Future<void> delete({required String key}) => impl.delete(key);
}
```

- [ ] **Step 2: Write the two halves**

`lib/shared/mana_token_store_io.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

Future<void> write(String key, String? value) =>
    _storage.write(key: key, value: value);

Future<String?> read(String key) => _storage.read(key: key);

Future<void> delete(String key) => _storage.delete(key: key);
```

`lib/shared/mana_token_store_web.dart`:

```dart
import 'package:web/web.dart' as web;

Future<void> write(String key, String? value) async {
  if (value == null) {
    web.window.sessionStorage.removeItem(key);
    return;
  }
  web.window.sessionStorage.setItem(key, value);
}

Future<String?> read(String key) async =>
    web.window.sessionStorage.getItem(key);

Future<void> delete(String key) async =>
    web.window.sessionStorage.removeItem(key);
```

- [ ] **Step 3: Swap the one field**

In `lib/features/login_registration/state/auth_flow_state.dart:400`:

```dart
  static const _storage = ManaTokenStore();
```

Add the import; remove the `flutter_secure_storage` import from that file. **All 22 existing call sites compile unchanged** — that is the reason the method shapes were copied rather than improved.

- [ ] **Step 4: Run analyze and the suite**

```bash
flutter analyze lib/features/login_registration/state/auth_flow_state.dart lib/shared/mana_token_store.dart
flutter test
```

Expected: analyze clean, suite green. If a test stubs `FlutterSecureStorage` directly, it now needs to stub `ManaTokenStore` — the harness sets up secure storage, so check `test/support/mana_harness.dart` and update it in this task if so.

- [ ] **Step 5: Verify the session actually persists on Android**

Because this touches login for every existing user, and analyze proves nothing about it:

```bash
pwsh tool/build_apk.ps1
$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe -s 95a05e0c install -r build/app/outputs/flutter-apk/app-debug.apk
```

Log in, close the app, reopen it. It must come back to the PIN pad with the session intact — not to a fresh registration. **This is the one task in the plan that can lock every existing user out of the Android app**, and a code reading cannot tell you whether it did.

- [ ] **Step 6: Commit**

```bash
git add lib/shared/mana_token_store*.dart lib/features/login_registration/state/auth_flow_state.dart
git commit -m "A JWT in localStorage outlives the browser; in sessionStorage it does not"
```

---

### Task 9: Walk it in a browser

**Files:** none — this task changes nothing and proves everything.

- [ ] **Step 1: Build and serve**

```bash
flutter build web --dart-define=SUPABASE_URL=$URL --dart-define=SUPABASE_ANON_KEY=$KEY
```

Serve `build/web` and open it.

- [ ] **Step 2: Walk the five workflows against production**

Sign in as a real Owner and reach each of: registration/login, transaction history (OW-017), pre-existing business migration (OW-018), `/subscription`, and profile + settings. At 1440 px and at 390 px.

- [ ] **Step 3: Exercise every fallback deliberately**

Export a statement (downloads a file). Open the loan-import template (downloads). Reach face capture (offers upload, and completes). Open an address editor (PIN + village, no location error). Confirm no fingerprint button is offered.

- [ ] **Step 4: Read the browser console**

Any `MissingPluginException` means a plugin call was missed. The guard scans imports; a call reached through a re-export would slip past it. The console is the check the guard cannot be.

- [ ] **Step 5: Report**

State what was verified and how, separately from what was changed. Anything not verified gets said plainly rather than implied.

---

## Self-Review

**Spec coverage.** Phase 0 → Tasks 1–2. Phase 1 → Tasks 3–7. §7 session storage → Task 8. §8 guards: `web_plugin_fallback_test` (Task 3) and the encoding guard widened to `site/` — **that belongs to Plan 3, which creates `site/`; it is not a gap here.** `site_plans_sync_test` and `expectNoLayoutFault` at three widths belong to Plans 3 and 2. §9 phases 2–4 are Plans 2 and 3.

**Placeholders.** Three steps deliberately say "read the file and match what is there" rather than quoting code — Task 1 Step 4 (`surfaceMuted`), Task 6 Step 2 (`ManaPlace.unresolved`), Task 4 Step 6 (`subject:`). Each names the exact file and what to look for. Inventing a token or constructor name here is precisely the failure mode this codebase has been bitten by; instructing the implementer to read is the correct instruction, not a missing one.

**Type consistency.** `manaShareBytes` — same name and signature in Tasks 4 and 9. `ManaTokenStore` — `write`/`read`/`delete` named-argument shapes match `FlutterSecureStorage`, which is what keeps the 22 call sites compiling. `kManaWideRoutes` — defined in Task 1, consumed by Plan 2. `ManaBreakpoints.compact`/`columnMax` — used consistently in the test and the widget.

**Scope.** Nine tasks, ~11 files created and ~11 modified. Independently shippable: after Task 9 the app works in a browser.

---

## The other two plans

The spec covers three subsystems that each produce working software on their own. This is the first.

**Plan 2 — Responsive across the five workflows** (spec §4, phase 2). ~20 screens, ~10,200 lines. Each workflow adds its route to `kManaWideRoutes` and gets laid out for a wide window, with `expectNoLayoutFault` at three widths. `ManaLedgerHistoryView` is shared with AG-010, so that one has two consumers to check. Depends on Task 1 of this plan.

**Plan 3 — The public site and deploy** (spec §2, phases 3–4). `site/` as five static pages, `tool/gen_site_plans.dart` generating tiers and caps with no rupee figures, `test/site_plans_sync_test.dart` asserting both the caps match `kOwnerTiers` and that no price appears, `test/source_encoding_test.dart` widened to `site/`, Cloudflare Pages with the `/app/*` rewrite and a CSP header, `manaline.in`. Independent of Plan 2.
