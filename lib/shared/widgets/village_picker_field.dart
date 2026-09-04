import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../location_api_service.dart';
import '../translation_service.dart';

/// PIN code plus a village name, with the picker every other village field in
/// this app had to grow its own copy of.
///
/// WHY THIS EXISTS. The same three-part pattern — PIN field, name field, list of
/// matches merged from `locations` and the LGD reference — was written
/// independently in the registration form, the setup wizard, two operating-area
/// pickers, the migration screen, an agent's edit-contact sheet and four
/// address editors. Ten copies. They drifted, and every drift was the same
/// bug in a different place: one searched `locations` alone, one used a
/// two-letter threshold, one sorted by provenance, one read `location_id` as a
/// String and threw on a suggestion.
///
/// The service was consolidated first. This is the widget half, so that the
/// eleventh and twelfth uses — the two Create Business forms — do not become
/// copies eleven and twelve.
///
/// IT DOES NOT WRITE ANYTHING. [onPicked] hands back the chosen [ManaVillage],
/// and a village that came from the reference still has an empty `locationId`.
/// Callers that need a real row call [LocationApiService.resolveId]; callers
/// that only need the words — a business's registered address, say — must not,
/// because writing a `locations` row for a head office nobody collects in
/// would put a place into the operating directory that no round ever visits.
class ManaVillagePickerField extends ConsumerStatefulWidget {
  /// Called on every change of the chosen village, including null when the
  /// person edits the search and unpicks what they had.
  final ValueChanged<ManaVillage?> onPicked;

  /// Shown above the two fields. Null for none.
  final String? label;

  const ManaVillagePickerField({super.key, required this.onPicked, this.label});

  @override
  ConsumerState<ManaVillagePickerField> createState() =>
      _ManaVillagePickerFieldState();
}

class _ManaVillagePickerFieldState
    extends ConsumerState<ManaVillagePickerField> {
  final _pin = TextEditingController();
  final _query = TextEditingController();

  List<ManaVillage> _results = const [];
  ManaVillage? _picked;
  bool _searching = false;

  @override
  void dispose() {
    _pin.dispose();
    _query.dispose();
    super.dispose();
  }

  /// True when the PIN is complete but the name is not, so nothing has been
  /// searched for. Distinct from "searched and found nothing", and said
  /// differently — conflating the two is how "No villages found for that PIN"
  /// came to be shown for a PIN carrying fifty villages.
  bool get _needsName =>
      _pin.text.trim().length == 6 &&
      _query.text.trim().length < LocationApiService.minVillageLetters;

  Future<void> _search() async {
    // Unpick first: a selection made against the previous search must not
    // survive the person typing a different name over it.
    if (_picked != null) {
      _picked = null;
      widget.onPicked(null);
    }
    final pin = _pin.text.trim();
    final needle = _query.text.trim();
    if (pin.length != 6 || needle.length < LocationApiService.minVillageLetters) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final found = await ref
        .read(locationApiServiceProvider)
        .searchByPin(pinCode: pin, query: needle, limit: 15);
    if (!mounted) return;
    setState(() {
      _results = found;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          ManaText.raw(widget.label!, style: ManaType.strong),
          const SizedBox(height: ManaSpacing.xs),
        ],
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: ref.t('pin_code_field')),
          onChanged: (_) => _search(),
        ),
        TextField(
          controller: _query,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: ref.t('village_name_field')),
          onChanged: (_) => _search(),
        ),
        if (_needsName)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: ManaText.raw(ref.t('enter_village_name_to_search'),
                style: ManaType.note),
          ),
        if (_searching)
          const Padding(
            padding: EdgeInsets.all(ManaSpacing.sm),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_searching && !_needsName && _results.isEmpty && _pin.text.trim().length == 6)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: ManaText.raw(ref.t('no_villages_found_for_pin'),
                style: ManaType.note),
          ),
        ..._results.map((v) {
          // Compared on NAME: a reference row has an empty id until somebody
          // resolves it, so comparing ids would tick every suggestion at once.
          final selected = _picked?.name == v.name;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              selected ? Icons.check_circle : Icons.location_on_outlined,
              color: selected ? ManaColors.statusGood : ManaColors.brand,
            ),
            title: ManaText.raw(v.name),
            subtitle: v.placeLabel.isEmpty
                ? null
                : ManaText.raw(v.placeLabel, style: ManaType.note),
            onTap: () {
              setState(() => _picked = v);
              widget.onPicked(v);
            },
          );
        }),
      ],
    );
  }
}

/// A village written the way an address is read: door number first, then the
/// place, widening out, with the PIN last.
///
/// Empty parts are dropped rather than left as stray separators — a business
/// with no door number should not have an address beginning with a comma.
String manaComposeAddress({String? doorNo, required ManaVillage village}) {
  final parts = [
    if ((doorNo ?? '').trim().isNotEmpty) doorNo!.trim(),
    village.name,
    village.mandal,
    village.district,
    village.state,
  ].where((s) => s.trim().isNotEmpty).join(', ');
  final pin = village.pinCode.trim();
  return pin.isEmpty ? parts : '$parts - $pin';
}
