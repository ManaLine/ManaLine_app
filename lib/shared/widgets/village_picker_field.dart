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

  /// What the PIN says its mandal/district/state can be. The Add New Village
  /// panel offers these instead of asking somebody to type them, which is how
  /// a village came to record its state as "Andhrapradesh".
  List<ManaPinOption> _pinOptions = const [];
  ManaPinOption? _chosenOption;

  /// Villages at this PIN close enough to the typed name to be worth asking
  /// about, so two spellings of one place do not become two locations.
  List<ManaSimilarVillage> _similar = const [];
  bool _adding = false;
  String? _addError;

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
    final api = ref.read(locationApiServiceProvider);
    final found = await api.searchByPin(pinCode: pin, query: needle, limit: 15);
    if (!mounted) return;
    setState(() {
      _results = found;
      _searching = false;
    });

    // Only when the search came back empty is there anything to add — and only
    // then is it worth asking what else this PIN could mean, or what the name
    // nearly matches.
    if (found.isNotEmpty) {
      setState(() => _similar = const []);
      return;
    }
    final options = await api.pinOptions(pin);
    final similar = await api.similarVillages(pinCode: pin, name: needle);
    if (!mounted) return;
    setState(() {
      _pinOptions = options;
      // One answer is not a choice. Auto-select it rather than making somebody
      // confirm the only thing it could be.
      _chosenOption = options.length == 1 ? options.first : _chosenOption;
      _similar = similar;
    });
  }

  Future<void> _addTypedVillage() async {
    final option = _chosenOption;
    if (option == null) return;
    setState(() {
      _adding = true;
      _addError = null;
    });
    try {
      final created = await ref.read(locationApiServiceProvider).addIfMissing(
            pinCode: _pin.text.trim(),
            villageTownName: _query.text.trim(),
            areaType: 'Village',
            mandal: option.mandal,
            district: option.district,
            state: option.state,
            // Typed, not chosen from the reference. Recorded so a village
            // added by mistake can be found again later.
            source: 'Owner Entered',
          );
      if (!mounted) return;
      setState(() {
        _adding = false;
        _picked = created;
        _results = [created];
        _similar = const [];
      });
      widget.onPicked(created);
    } catch (e) {
      if (!mounted) return;
      // Said out loud. A silent failure here leaves somebody believing their
      // village was added when it was not.
      setState(() {
        _adding = false;
        _addError = '$e';
      });
    }
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
          ..._addPanel(),
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

  /// What to offer when the search found nothing.
  ///
  /// Villages the LGD directory has never heard of are legitimate and
  /// permanent — hamlets, new settlements, local names that never entered
  /// government records. Dommarametta is one. So "no match" must not be a dead
  /// end; it has to be the start of adding one.
  ///
  /// But adding one used to be four free-text boxes, and that is how a village
  /// came to record its state as "Andhrapradesh" and then narrow every picker
  /// to nothing. So this asks for the NAME only — already typed — and offers
  /// the rest.
  List<Widget> _addPanel() {
    return [
      Padding(
        padding: const EdgeInsets.only(top: ManaSpacing.xs),
        child: ManaText.raw(ref.t('no_villages_found_for_pin'),
            style: ManaType.note),
      ),

      // Asked BEFORE offering to create, because the cheapest fix for a
      // duplicate is not making it. ichapuram and Ichchapuram are one town.
      if (_similar.isNotEmpty) ...[
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('did_you_mean_note'), style: ManaType.strong),
        ..._similar.map((m) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(Icons.help_outline, color: ManaColors.brand),
              title: ManaText.raw(m.village.name),
              subtitle: ManaText.raw(
                  m.village.placeLabel.isEmpty ? '' : m.village.placeLabel,
                  style: ManaType.note),
              onTap: () {
                setState(() {
                  _picked = m.village;
                  _query.text = m.village.name;
                  _results = [m.village];
                  _similar = const [];
                });
                widget.onPicked(m.village);
              },
            )),
      ],

      const SizedBox(height: ManaSpacing.sm),
      ManaText.raw(
        ref.t('add_village_named_note').replaceAll('{name}', _query.text.trim()),
        style: ManaType.strong,
      ),

      if (_pinOptions.isEmpty)
        // A pincode the directory does not carry at all. Nothing to offer, and
        // saying so beats a dropdown with one empty row in it.
        Padding(
          padding: const EdgeInsets.only(top: ManaSpacing.xs),
          child: ManaText.raw(ref.t('pin_not_in_directory_note'),
              style: ManaType.note),
        )
      else ...[
        const SizedBox(height: ManaSpacing.xs),
        DropdownButtonFormField<ManaPinOption>(
          initialValue: _chosenOption,
          isExpanded: true,
          decoration:
              InputDecoration(labelText: ref.t('mandal_district_field')),
          items: [
            for (final o in _pinOptions)
              DropdownMenuItem(
                value: o,
                child: ManaText.raw(o.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _chosenOption = v),
        ),
      ],

      if (_addError != null)
        Padding(
          padding: const EdgeInsets.only(top: ManaSpacing.xs),
          child: ManaText.raw(_addError!, style: ManaType.bad),
        ),

      const SizedBox(height: ManaSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed:
              (_adding || _chosenOption == null) ? null : _addTypedVillage,
          icon: _adding
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_location_alt_outlined, size: 18),
          label: ManaText.raw(ref.t('add_this_village')),
        ),
      ),
    ];
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
