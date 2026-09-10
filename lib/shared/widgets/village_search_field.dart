import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../location_api_service.dart';
import '../translation_service.dart';
import 'village_picker_field.dart';

/// How a person is finding their village. PIN is the established path and
/// the default on every open; cascade is the second way in, for someone who
/// does not know their PIN.
enum _VillageSearchMode { pin, cascade }

/// A village field with two ways in: PIN (default, unchanged) or
/// State -> District -> name.
///
/// SAME CALLBACK SHAPE AS [ManaVillagePickerField], deliberately — the
/// eleven screens adopting this later are a swap, not a rewrite at each
/// site.
///
/// PIN MODE IS NOT REIMPLEMENTED HERE. It embeds [ManaVillagePickerField]
/// itself, because a second copy of a working village search is exactly how
/// the two drift apart — see that widget's own doc comment for the ten
/// times this already happened in this codebase before the service and the
/// widget were consolidated.
///
/// MODE IS NEVER REMEMBERED. It resets to PIN on every open: the person who
/// needed the cascade needed it for one address they had no PIN for, not as
/// a standing preference, and next time they may have a different address
/// entirely.
class ManaVillageSearchField extends ConsumerStatefulWidget {
  /// Called on every change to the chosen village — including null when a
  /// prior pick is edited away, an earlier cascade step is changed, or the
  /// mode itself is switched.
  final ValueChanged<ManaVillage?> onPicked;

  /// Shown above the mode switch. Null for none.
  final String? label;

  const ManaVillageSearchField({super.key, required this.onPicked, this.label});

  @override
  ConsumerState<ManaVillageSearchField> createState() =>
      _ManaVillageSearchFieldState();
}

class _ManaVillageSearchFieldState
    extends ConsumerState<ManaVillageSearchField> {
  _VillageSearchMode _mode = _VillageSearchMode.pin;

  // Re-keying the PIN child on every switch drops its PIN/name controllers
  // and whatever half-typed search sat in them, rather than let a stale
  // search resurface if the person switches back to PIN later.
  Key _pinKey = UniqueKey();

  String? _state;
  String? _district;
  final _village = TextEditingController();

  Timer? _debounce;
  List<ManaVillage> _results = const [];
  bool _searching = false;
  ManaVillage? _picked;

  Future<List<String>>? _statesFuture;
  Future<List<String>>? _districtsFuture;

  @override
  void dispose() {
    _debounce?.cancel();
    _village.dispose();
    super.dispose();
  }

  Future<List<String>> _states() =>
      _statesFuture ??= ref.read(locationApiServiceProvider).states();

  void _switchMode(_VillageSearchMode next) {
    if (next == _mode) return;
    setState(() {
      _mode = next;
      _pinKey = UniqueKey();
      _state = null;
      _district = null;
      _districtsFuture = null;
      _village.clear();
      _results = const [];
      _picked = null;
    });
    // A village found by PIN and one found by the cascade are the same row
    // reached two ways. Carrying a half-finished pick across the switch is
    // how somebody submits an address they did not choose.
    widget.onPicked(null);
  }

  void _onStateChanged(String? next) {
    setState(() {
      _state = next;
      // Changing an earlier step clears every later one — a person who
      // corrects their district must not keep a village from the old one,
      // or a customer ends up filed in a district nobody collects from.
      _district = null;
      _districtsFuture = next == null
          ? null
          : ref.read(locationApiServiceProvider).districtsIn(next);
      _village.clear();
      _results = const [];
      _picked = null;
    });
    widget.onPicked(null);
  }

  void _onDistrictChanged(String? next) {
    setState(() {
      _district = next;
      _village.clear();
      _results = const [];
      _picked = null;
    });
    widget.onPicked(null);
  }

  void _onQueryChanged(String _) {
    // Unpick first: a selection made against the previous search text must
    // not survive somebody typing a different name over it.
    if (_picked != null) {
      _picked = null;
      widget.onPicked(null);
    }
    _debounce?.cancel();
    // 400ms. searchVillages costs 15-65ms server-side; the rest of the
    // budget is a rural handset's network round-trip, which routinely runs
    // into the hundreds of milliseconds on its own. Below this interval, six
    // keystrokes fire four overlapping queries whose answers can arrive out
    // of order, so the result list flickers between a stale answer and the
    // current one. Much above it, the field reads as waiting rather than
    // searching. 400ms sits past typical inter-keystroke gaps while typing a
    // village name but well inside "feels immediate".
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final st = _state;
    final di = _district;
    final needle = _village.text.trim();
    if (st == null ||
        di == null ||
        needle.length < LocationApiService.minVillageLetters) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    final found = await ref
        .read(locationApiServiceProvider)
        .searchVillages(state: st, district: di, query: needle);
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
        // A plain, visible control — not a hidden setting somebody has to
        // guess at. PIN first, because it is the default every screen has
        // always offered.
        SegmentedButton<_VillageSearchMode>(
          segments: [
            ButtonSegment(
              value: _VillageSearchMode.pin,
              label: ManaText.raw(ref.t('village_search_by_pin')),
            ),
            ButtonSegment(
              value: _VillageSearchMode.cascade,
              label: ManaText.raw(ref.t('village_search_by_state_district')),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) => _switchMode(selection.first),
        ),
        const SizedBox(height: ManaSpacing.sm),
        if (_mode == _VillageSearchMode.pin)
          ManaVillagePickerField(key: _pinKey, onPicked: widget.onPicked)
        else
          ..._cascade(),
      ],
    );
  }

  List<Widget> _cascade() {
    return [
      // State and district are PICKERS, not free text — 35 and roughly 22
      // options respectively. Free text on either reintroduces the spelling
      // problem this whole feature exists to remove.
      FutureBuilder<List<String>>(
        future: _states(),
        builder: (context, snap) {
          final states = snap.data ?? const [];
          return DropdownButtonFormField<String>(
            initialValue: _state,
            isExpanded: true,
            decoration: InputDecoration(labelText: ref.t('state_field')),
            items: [
              for (final s in states)
                DropdownMenuItem(
                  value: s,
                  child: ManaText.raw(s,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _onStateChanged,
          );
        },
      ),
      const SizedBox(height: ManaSpacing.sm),
      if (_state == null)
        Padding(
          padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
          child: ManaText.raw(ref.t('choose_state_to_continue'),
              style: ManaType.note),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
          child: FutureBuilder<List<String>>(
            future: _districtsFuture,
            builder: (context, snap) {
              final districts = snap.data ?? const [];
              return DropdownButtonFormField<String>(
                initialValue: _district,
                isExpanded: true,
                decoration: InputDecoration(labelText: ref.t('district_field')),
                items: [
                  for (final d in districts)
                    DropdownMenuItem(
                      value: d,
                      child: ManaText.raw(d,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _onDistrictChanged,
              );
            },
          ),
        ),
      if (_district != null) ...[
        TextField(
          controller: _village,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: ref.t('village_name_field')),
          onChanged: _onQueryChanged,
        ),
        if (_village.text.trim().length < LocationApiService.minVillageLetters)
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
        if (!_searching &&
            _results.isEmpty &&
            _village.text.trim().length >= LocationApiService.minVillageLetters)
          Padding(
            padding: const EdgeInsets.only(top: ManaSpacing.xs),
            child: ManaText.raw(ref.t('no_villages_found_for_search'),
                style: ManaType.note),
          ),
        ..._results.map(_resultTile),
      ],
    ];
  }

  Widget _resultTile(ManaVillage v) {
    // Compared on NAME, not id: a cascade result has no location_id until
    // somebody resolves it, so comparing ids would tick every row at once —
    // same reasoning as ManaVillagePickerField's own result list.
    final selected = _picked?.name == v.name;
    // Village, mandal, district, state and PIN — every result row carries
    // all five so a person can recognise their own place. The PIN is shown,
    // never typed, in this mode.
    final place = [v.mandal, v.district, v.state]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final subtitle = v.pinCode.isEmpty ? place : '$place - ${v.pinCode}';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        selected ? Icons.check_circle : Icons.location_on_outlined,
        color: selected ? ManaColors.statusGood : ManaColors.brand,
      ),
      title: ManaText.raw(v.name),
      subtitle: subtitle.isEmpty
          ? null
          : ManaText.raw(subtitle,
              style: ManaType.note, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () {
        setState(() => _picked = v);
        widget.onPicked(v);
      },
    );
  }
}
