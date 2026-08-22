/// Choosing a person who is already on the books.
///
/// Investors and shareholders used to be entered by downloading a spreadsheet,
/// retyping names and MLIDs that page 1 had already recorded, and uploading it
/// again. There are a handful of them — this business has three investors and
/// five shareholders — so the spreadsheet was pure overhead, and every retyped
/// MLID was a chance to attach money to the wrong person.
///
/// Here the Owner searches the people already imported and taps one. Name,
/// MLID and village are all searched together, because which of the three an
/// Owner remembers is not something the app gets to decide.
library;

import 'package:flutter/material.dart';

import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../state/bulk_onboarding_service.dart';

class ManaMemberPicker extends StatefulWidget {
  final List<ManaMemberRef> members;

  /// MLIDs already used, shown greyed and unselectable so the same person
  /// cannot be added twice by accident.
  final Set<String> alreadyUsed;
  final ValueChanged<ManaMemberRef> onPick;
  final String emptyNote;

  const ManaMemberPicker({
    super.key,
    required this.members,
    required this.onPick,
    this.alreadyUsed = const {},
    required this.emptyNote,
  });

  @override
  State<ManaMemberPicker> createState() => _ManaMemberPickerState();
}

class _ManaMemberPickerState extends State<ManaMemberPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.md),
        child: ManaText.raw(widget.emptyNote, style: ManaType.note),
      );
    }
    final matches =
        widget.members.where((m) => m.matches(_search.text)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search By Name, MLID Or Village',
          ),
        ),
        const SizedBox(height: ManaSpacing.sm),
        // Bounded height: this sits inside a scrolling page, and an unbounded
        // list of members would fight the page for the gesture.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: matches.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: ManaText.raw('Nobody matches that.',
                      style: ManaType.note),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final m = matches[i];
                    final used = widget.alreadyUsed.contains(m.mlid);
                    return ListTile(
                      dense: true,
                      enabled: !used,
                      leading: Icon(
                        used ? Icons.check_circle : Icons.person_outline,
                        color: used ? ManaColors.statusGood : null,
                      ),
                      title: ManaText.raw(m.fullName, style: ManaType.strong),
                      subtitle: ManaText.raw(
                        [m.mlid, if (m.village != null) m.village!].join(' · '),
                        style: ManaType.small,
                      ),
                      onTap: used ? null : () => widget.onPick(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
