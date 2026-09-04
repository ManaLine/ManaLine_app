import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../location_api_service.dart';
import '../translation_service.dart';

/// Adding a village the LGD directory has never recorded.
///
/// WHY ONE SHEET AND NOT SEVEN FORMS. This existed seven times — the
/// registration form, the setup wizard, OW-004, and the four profile editors —
/// and every copy asked for the same four things as free text: village name,
/// mandal, district, state. Four boxes, seven times, and every one of them a
/// place where somebody could type a state the directory does not carry. One
/// did: "Andhrapradesh", which then narrowed every district picker to nothing
/// and pushed the next person straight back into manual entry. One typed value
/// reproduced itself.
///
/// TWO THINGS THE COPIES COULD NOT DO.
///
/// The PIN already knows the administrative geography. 99.8% of pincodes
/// resolve to one state, 97.8% to at most two districts, 85% to at most three
/// mandals — so mandal and district are a CHOICE, not a question, even for a
/// village the directory has never heard of. Free text was never the right
/// control.
///
/// And `add_location_if_missing` deduplicates on an exact name, so two
/// spellings of one town become two locations and the customers split between
/// them. `ichapuram` and `Ichchapuram` are one town — the railway station
/// carries the second spelling — and they score 0.83. Asking "did you mean?"
/// before creating is the only cheap moment to prevent that.
///
/// Returns the village that ended up chosen — created, or an existing one the
/// person recognised from the suggestions — or null if they backed out.
Future<ManaVillage?> manaShowAddVillageSheet(
  BuildContext context,
  WidgetRef ref, {
  required String pinCode,
  String initialName = '',
}) {
  return showModalBottomSheet<ManaVillage>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddVillageSheet(pinCode: pinCode, initialName: initialName),
  );
}

class _AddVillageSheet extends ConsumerStatefulWidget {
  final String pinCode;
  final String initialName;
  const _AddVillageSheet({required this.pinCode, required this.initialName});

  @override
  ConsumerState<_AddVillageSheet> createState() => _AddVillageSheetState();
}

class _AddVillageSheetState extends ConsumerState<_AddVillageSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);

  /// Free-text fallbacks, used ONLY when the directory does not carry this PIN
  /// at all. A genuinely new postal area has nothing to offer, and refusing to
  /// let somebody proceed would be worse than asking them to type it.
  final _mandal = TextEditingController();
  final _district = TextEditingController();
  final _state = TextEditingController();

  List<ManaPinOption> _options = const [];
  ManaPinOption? _chosen;
  List<ManaSimilarVillage> _similar = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _mandal.dispose();
    _district.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(locationApiServiceProvider);
    final options = await api.pinOptions(widget.pinCode);
    if (!mounted) return;
    setState(() {
      _options = options;
      // One answer is not a choice.
      _chosen = options.length == 1 ? options.first : null;
      _loading = false;
    });
    await _checkSimilar();
  }

  Future<void> _checkSimilar() async {
    final found = await ref.read(locationApiServiceProvider).similarVillages(
        pinCode: widget.pinCode, name: _name.text.trim());
    if (!mounted) return;
    setState(() => _similar = found);
  }

  bool get _canSave {
    if (_name.text.trim().isEmpty) return false;
    if (_options.isNotEmpty) return _chosen != null;
    return _mandal.text.trim().isNotEmpty &&
        _district.text.trim().isNotEmpty &&
        _state.text.trim().isNotEmpty;
  }

  Future<void> _pickSuggestion(ManaSimilarVillage m) async {
    if (m.inUse) {
      Navigator.of(context).pop(m.village);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Materialises the directory row, provenance 'Directory' — chosen from
      // the reference, not typed.
      final id =
          await ref.read(locationApiServiceProvider).resolveId(m.village);
      if (!mounted) return;
      Navigator.of(context).pop(ManaVillage(
        locationId: id,
        name: m.village.name,
        pinCode: m.village.pinCode,
        mandal: m.village.mandal,
        district: m.village.district,
        state: m.village.state,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ref.t('could_not_add_village_note').replaceAll('{error}', '$e');
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(locationApiServiceProvider).addIfMissing(
            pinCode: widget.pinCode,
            villageTownName: _name.text.trim(),
            areaType: 'Village',
            mandal: _chosen?.mandal ?? _mandal.text.trim(),
            district: _chosen?.district ?? _district.text.trim(),
            state: _chosen?.state ?? _state.text.trim(),
            // Typed, not chosen from the reference — recorded so a village
            // added by mistake can be found again.
            source: 'Owner Entered',
          );
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      // Said out loud. Four of the seven copies of this swallowed the error and
      // just stopped the spinner, so the person believed their village was
      // added when it was not.
      setState(() {
        _saving = false;
        _error = ref.t('could_not_add_village_note').replaceAll('{error}', '$e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(ref.t('add_new_village'), style: ManaType.sheetTitle),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('add_village_for_pin_note')
                    .replaceAll('{pin}', widget.pinCode),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: ref.t('village_name_field')),
                onChanged: (_) {
                  setState(() {});
                  _checkSimilar();
                },
              ),

              // Before the offer to create, not after: the cheapest fix for a
              // duplicate is not making it.
              if (_similar.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(ref.t('did_you_mean_note'), style: ManaType.strong),
                ..._similar.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading:
                          Icon(Icons.help_outline, color: ManaColors.brand),
                      title: ManaText.raw(m.village.name),
                      subtitle: m.village.placeLabel.isEmpty
                          ? null
                          : ManaText.raw(m.village.placeLabel,
                              style: ManaType.note),
                      // A suggestion is one of two things and they must not be
                      // treated alike: a `locations` row somebody already works
                      // in, which has a real id, or a DIRECTORY row, which has
                      // none until it is written. Popping the second one
                      // unresolved would hand the caller an empty location_id
                      // to store against an address.
                      onTap: () => _pickSuggestion(m),
                    )),
                const Divider(),
              ],

              const SizedBox(height: ManaSpacing.sm),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_options.isNotEmpty)
                DropdownButtonFormField<ManaPinOption>(
                  initialValue: _chosen,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: ref.t('mandal_district_field')),
                  items: [
                    for (final o in _options)
                      DropdownMenuItem(
                        value: o,
                        child: ManaText.raw(o.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _chosen = v),
                )
              else ...[
                // The directory does not carry this PIN at all.
                ManaText.raw(ref.t('pin_not_in_directory_note'),
                    style: ManaType.note),
                TextField(
                  controller: _mandal,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('mandal_field')),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _district,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      InputDecoration(labelText: ref.t('district_field')),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _state,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: ref.t('state_field')),
                  onChanged: (_) => setState(() {}),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(_error!, style: ManaType.bad),
              ],

              const SizedBox(height: ManaSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: ManaText.raw(ref.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_saving || !_canSave) ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : ManaText.raw(ref.t('add_this_village')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
