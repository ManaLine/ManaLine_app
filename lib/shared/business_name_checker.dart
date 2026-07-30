import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../design/tokens/spacing.dart';
import '../design/components/mana_text.dart';

/// Checks whether a business name is already taken (case-insensitive,
/// matching the real DB constraint — uq_businesses_name_ci) and, if so,
/// generates alternative suggestions that are verified available too
/// (not just plausible-looking — actually checked against the DB each).
class BusinessNameChecker {
  static Future<bool> isAvailable(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true;
    final rows = await Supabase.instance.client
        .from('businesses')
        .select('business_id')
        .ilike('business_name', trimmed)
        .limit(1);
    return (rows as List).isEmpty;
  }

  /// Returns up to 2 verified-available alternative names, or an empty
  /// list if even the fallback candidates are somehow also taken (rare,
  /// but don't ever present an unverified suggestion as if it were safe).
  static Future<List<String>> suggestAlternatives(String name) async {
    final base = name.trim();
    final candidates = ['$base 2', '$base 3', '$base (New)', '$base Finance'];
    final available = <String>[];
    for (final c in candidates) {
      if (available.length >= 2) break;
      if (await isAvailable(c)) available.add(c);
    }
    return available;
  }
}

/// Shown when a business name is already taken — offers verified-
/// available alternatives (not just plausible-looking guesses). Public
/// (shared between OW-000's first-time wizard and OW-012's Create
/// Business dialog) — Dart's underscore-privacy is per-file, so this
/// couldn't stay a private class in either screen file without
/// duplicating it.
class BusinessNameTakenDialog extends StatelessWidget {
  final String name;
  final List<String> alternatives;
  const BusinessNameTakenDialog({super.key, required this.name, required this.alternatives});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ManaText('name already taken'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw('"$name" is already in use by another business.'),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.md),
            const ManaText('available alternatives:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            ...alternatives.map((alt) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: ManaText.raw(alt),
                  trailing: TextButton(
                    onPressed: () => Navigator.pop(context, alt),
                    child: const ManaText('use this'),
                  ),
                )),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: ManaSpacing.sm),
              child: ManaText.raw('Please choose a different name.'),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const ManaText('close')),
      ],
    );
  }
}
