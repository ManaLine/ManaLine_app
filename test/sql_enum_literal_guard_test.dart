import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/schema_snapshot.dart';

/// Enum literals written into SQL, checked against the enums that exist.
///
/// THE BUG CLASS THIS EXISTS FOR, four times and counting: plpgsql bodies are
/// NOT type-checked at CREATE time. A function naming an enum value that does
/// not exist applies perfectly, reports success, and throws 22P02 on its first
/// call — possibly months later, possibly on one branch while the branch beside
/// it works.
///
///   'General'       expense category that was not one
///   'Self Request'  onboarding method that was not one
///   'Full Payment'  collection result that was not one
///   'Other'         occupation_enum has 'Other-Custom'. This one made an Owner
///                   approving a Customer's request to join fail EVERY time
///                   since the function was written, while the Investor branch
///                   two lines below it worked, so the feature looked half-alive
///                   rather than broken.
///
/// CLAUDE.md listed this as explicitly uncovered — the schema snapshot checked
/// the Dart side of the enum contract and not the SQL side. This is that half.
///
/// WHAT IT CHECKS: positional `INSERT INTO t (cols) VALUES (vals)` in the
/// migration files, which is the shape all four incidents took. A value is only
/// checked when it is a plain quoted literal landing on a column the snapshot
/// knows is enum-typed. Anything else — a variable, a function call, NULL, a
/// cast expression — is counted as skipped rather than guessed at.
///
/// IT REPORTS ITS OWN BLIND SPOT. A guard that quietly checks nothing reads
/// exactly like a guard that passes, which is the failure mode this repo keeps
/// meeting. The coverage test below fails if the parser stops finding literals
/// to check.
///
/// NOT A SQL PARSER, and not trying to be. It understands quoting and nesting
/// well enough to line columns up with values, and gives up loudly otherwise.

/// Bad literals that were really written, really applied, and have since been
/// replaced by a later migration.
///
/// A migration file is a historical record: it says what ran that day, and
/// editing it to look correct would be a lie about what the database was told.
/// So the wrong values stay in those files and are named here instead, each
/// with the migration that superseded it. Every one of these is a function the
/// LAST definition of which is now correct — verified by invoking it, not by
/// reading it.
///
/// Adding to this list is only ever right for a literal that is already dead.
/// A NEW violation is a bug on its way to production and must be fixed in the
/// code, never parked here.
const _superseded = <String, String>{
  "20260901071610_approving_a_request_makes_somebody_a_member.sql: "
      "business_members.onboarding_method = 'Self Request' is not a "
      "onboarding_method_enum":
      'fixed the next morning by 20260901071702, whose name is literally '
          '"the join request uses a real onboarding method"',
  "20260901071610_approving_a_request_makes_somebody_a_member.sql: "
      "customers.occupation = 'Other' is not a occupation_enum":
      'fixed by 20260904092720 — it threw 22P02 on every Customer approval '
          'from the day it was written until then',
  "20260901071702_the_join_request_uses_a_real_onboarding_method.sql: "
      "customers.occupation = 'Other' is not a occupation_enum":
      'carried forward from 20260901071610; fixed by 20260904092720',
  "20260904091024_an_accepted_invitation_must_also_make_the_agent_row.sql: "
      "customers.occupation = 'Other' is not a occupation_enum":
      'mine, and the reason this guard exists. I copied the literal out of '
          'decide_membership_request and wrote in the migration comment that '
          'its values were known-good because that path was "exercised in '
          'production". That branch had never once succeeded. Fixed by '
          '20260904092720, in the same hour',
};

/// Splits a comma-separated SQL list, respecting quotes, dollar-quoting and
/// nesting. Returns null when it cannot be sure — the caller then skips.
List<String>? _splitSqlList(String s) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var inSingle = false;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (inSingle) {
      if (c == "'") {
        // '' is an escaped quote inside a literal, not the end of one.
        if (i + 1 < s.length && s[i + 1] == "'") {
          buf.write("''");
          i += 2;
          continue;
        }
        inSingle = false;
      }
      buf.write(c);
      i++;
      continue;
    }
    if (c == "'") {
      inSingle = true;
      buf.write(c);
      i++;
      continue;
    }
    if (c == r'$') return null; // dollar-quoted body — out of scope, say so
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString().trim());
      buf.clear();
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  if (inSingle || depth != 0) return null;
  parts.add(buf.toString().trim());
  return parts;
}

/// The literal a value expression carries, or null when it is not a plain
/// quoted string. `'X'` and `'X'::some_enum` both count; everything else does
/// not.
String? _literalOf(String value) {
  final m = RegExp(r"^'((?:[^']|'')*)'(?:\s*::\s*[\w.]+)?$").firstMatch(value.trim());
  if (m == null) return null;
  return m.group(1)!.replaceAll("''", "'");
}

void main() {
  final dir = Directory('supabase/migrations');

  final violations = <String>[];
  final supersededSeen = <String>{};
  var checked = 0;
  var skippedValues = 0;
  var skippedStatements = 0;

  final files = dir.existsSync()
      ? (dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  for (final file in files) {
    final sql = file.readAsStringSync();
    final name = file.uri.pathSegments.last;

    // INSERT INTO t (a, b, c) VALUES
    final inserts = RegExp(
      r'INSERT\s+INTO\s+(?:public\.)?(\w+)\s*\(([^;]*?)\)\s*VALUES\s*',
      caseSensitive: false,
      multiLine: true,
    ).allMatches(sql);

    for (final ins in inserts) {
      final table = ins.group(1)!.toLowerCase();
      final cols = _splitSqlList(ins.group(2)!)
          ?.map((c) => c.trim().toLowerCase().replaceAll('"', ''))
          .toList();
      if (cols == null) {
        skippedStatements++;
        continue;
      }

      // Only the enum columns in this statement are of interest.
      final enumPositions = <int, String>{};
      for (var i = 0; i < cols.length; i++) {
        final type = manaEnumColumns['$table.${cols[i]}'];
        if (type != null) enumPositions[i] = type;
      }
      if (enumPositions.isEmpty) continue;

      // Walk the tuples after VALUES.
      var pos = ins.end;
      while (pos < sql.length) {
        while (pos < sql.length && (sql[pos] == ' ' || sql[pos] == '\n' || sql[pos] == '\r' || sql[pos] == '\t')) {
          pos++;
        }
        if (pos >= sql.length || sql[pos] != '(') break;

        // Find this tuple's closing paren, respecting quotes.
        var depth = 0;
        var inSingle = false;
        var end = pos;
        var bad = false;
        while (end < sql.length) {
          final c = sql[end];
          if (inSingle) {
            if (c == "'") {
              if (end + 1 < sql.length && sql[end + 1] == "'") {
                end += 2;
                continue;
              }
              inSingle = false;
            }
          } else if (c == "'") {
            inSingle = true;
          } else if (c == r'$') {
            bad = true;
            break;
          } else if (c == '(') {
            depth++;
          } else if (c == ')') {
            depth--;
            if (depth == 0) break;
          }
          end++;
        }
        if (bad || end >= sql.length || depth != 0) {
          skippedStatements++;
          break;
        }

        final values = _splitSqlList(sql.substring(pos + 1, end));
        if (values == null || values.length != cols.length) {
          skippedStatements++;
        } else {
          enumPositions.forEach((i, type) {
            final literal = _literalOf(values[i]);
            if (literal == null) {
              skippedValues++;
              return;
            }
            final allowed = manaDbEnums[type];
            if (allowed == null) return; // unknown enum — snapshot's problem
            checked++;
            if (!allowed.contains(literal)) {
              final key = "$name: $table.${cols[i]} = '$literal' is not a $type";
              if (_superseded.containsKey(key)) {
                supersededSeen.add(key);
                return;
              }
              violations.add('$key (allowed: ${allowed.join(', ')})');
            }
          });
        }

        pos = end + 1;
        // Another tuple follows a comma; anything else ends the statement.
        while (pos < sql.length && (sql[pos] == ' ' || sql[pos] == '\n' || sql[pos] == '\r' || sql[pos] == '\t')) {
          pos++;
        }
        if (pos < sql.length && sql[pos] == ',') {
          pos++;
        } else {
          break;
        }
      }
    }
  }

  test('there are migrations to check', () {
    expect(files, isNotEmpty);
  });

  test('the parser is actually checking enum literals', () {
    // Without this, a regex that silently stops matching turns the assertion
    // below into a guarantee about nothing. That is the failure this repo has
    // met most often, so it is asserted rather than assumed.
    expect(checked, greaterThan(0),
        reason: 'No enum literal in any migration was checked. The INSERT '
            'matcher or the column map has drifted — $skippedValues values and '
            '$skippedStatements statements were skipped.');
  });

  test('the superseded list has no stale entries', () {
    // An exemption covering a file that was fixed or renamed silently protects
    // nothing, and reads as though it still matters.
    final stale = _superseded.keys.toSet().difference(supersededSeen);
    expect(stale, isEmpty,
        reason: 'Listed as superseded but no longer found. Remove:\n  '
            '${stale.join('\n  ')}');
  });

  test('every enum literal in a migration is a value that enum has', () {
    expect(
      violations,
      isEmpty,
      reason: 'These write a value the enum does not have. plpgsql applies '
          'them cleanly and throws 22P02 on the first call:\n  '
          '${violations.join('\n  ')}',
    );
  });
}
