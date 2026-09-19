import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'location_api_service.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';
import 'village_merge_state.dart';

/// Two entries for one village, made into one.
///
/// WHY THE OWNER ENDS UP HERE. A village gets typed before the directory has
/// it, or typed twice with two spellings, and its customers split across two
/// names: the round shows both, the village book shows both, and neither one
/// is the whole village. On this book it is 'Panagal' and 'Panagallu (Rural)',
/// same PIN, same mandal, 2 customers on one and 19 on the other.
///
/// WHAT IT PROMISES, in the Owner's words: "their loans, collections and
/// account history follow silently - just their address village name changes
/// to the new one, remaining all stays." That is checkable rather than
/// hopeful -- exactly three tables reference a village and none of them is
/// money -- and it is checked, in `village_merge_test.dart` and against the
/// live book before this shipped: 91 customers, 0 balances moved, 0 collecting
/// agents moved.
///
/// THE SCREEN'S ONE JOB IS THE DIRECTION. Which of the two names survives is
/// the only real decision here, and it is not obvious: the server suggests the
/// row more people already live on, and the Owner knows which name the village
/// is actually called by. So the two sides are shown as a pair with a Swap
/// between them, not as a from-and-to.
class ManaVillageMergeScreen extends ConsumerStatefulWidget {
  final String businessId;
  const ManaVillageMergeScreen({super.key, required this.businessId});

  @override
  ConsumerState<ManaVillageMergeScreen> createState() =>
      _ManaVillageMergeScreenState();
}

class _ManaVillageMergeScreenState
    extends ConsumerState<ManaVillageMergeScreen> {
  List<ManaVillageDuplicate> _pairs = const [];

  /// Every village this book works, so a wrong district can be put right.
  ///
  /// The two halves of this screen are the two ways a village list goes wrong:
  /// the same place entered twice, and one place recorded under the wrong
  /// name for where it is. An Owner looking at either is looking at the same
  /// list, so they are one screen.
  List<ManaVillage> _villages = const [];
  bool _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).candidates(widget.businessId),
    );
    // The screen can be popped between the two calls, and the second one
    // takes a context to report an error into. Checked rather than assumed --
    // this is the analyzer's async-gap warning and it is a real one here,
    // because the first call is a round trip on a village connection.
    if (!mounted) return;
    final villages = await NetworkErrorHandler.run(
      context,
      () => ref.read(locationApiServiceProvider).businessVillages(widget.businessId),
    );
    if (!mounted) return;
    setState(() {
      _pairs = rows ?? const [];
      _villages = villages ?? const [];
      _loading = false;
    });
  }

  /// Turn the pair around and ask the server again.
  ///
  /// The refusal is per direction, so a swapped pair carries no answer until
  /// one is fetched -- showing the old reason against the new direction would
  /// be quoting a sentence about the wrong villages.
  Future<void> _swap(int i) async {
    final before = _pairs[i];
    final swapped = before.swapped();
    setState(() {
      _pairs = [..._pairs]..[i] = swapped;
      _busyId = swapped.dropId;
    });
    final reason = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).blockedReason(
            businessId: widget.businessId,
            loserId: swapped.dropId,
            survivorId: swapped.keepId,
          ),
    );
    if (!mounted) return;

    // THE SWAP IS UNDONE WHEN THE CHECK COULD NOT BE MADE. A null here means
    // the call failed -- the handler has already said so -- and the screen
    // must not be left showing a direction whose answer it never got, because
    // a pair with no reason against it draws the Merge button.
    if (reason == null) {
      setState(() {
        _busyId = null;
        _pairs = [..._pairs]..[i] = before;
      });
      return;
    }

    setState(() {
      _busyId = null;
      _pairs = [..._pairs]
        ..[i] = ManaVillageDuplicate(
          keepId: swapped.keepId,
          keepName: swapped.keepName,
          keepMandal: swapped.keepMandal,
          keepDistrict: swapped.keepDistrict,
          keepPeople: swapped.keepPeople,
          dropId: swapped.dropId,
          dropName: swapped.dropName,
          dropMandal: swapped.dropMandal,
          dropDistrict: swapped.dropDistrict,
          dropPeople: swapped.dropPeople,
          pinCode: swapped.pinCode,
          blockedReason: reason.isEmpty ? null : reason,
        );
    });
  }

  Future<void> _merge(ManaVillageDuplicate p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: ManaText.raw(ref.t('merge_confirm_question')),
        content: ManaText.raw(ref
            .t('merge_confirm_note')
            .replaceAll('{count}', '${p.dropPeople}')
            .replaceAll('{from}', p.dropName)
            .replaceAll('{to}', p.keepName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: ManaText.raw(ref.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: ManaText.raw(ref.t('merge_villages')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busyId = p.dropId);
    final result = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).merge(
            businessId: widget.businessId,
            loserId: p.dropId,
            survivorId: p.keepId,
          ),
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result == null) return;

    // The server's own count, not the one this screen was showing. It is what
    // actually moved, and it includes past addresses the list never counted.
    final moved = (result['addresses_moved'] as num?)?.toInt() ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(ref
          .t('merged_note')
          .replaceAll('{count}', '$moved')
          .replaceAll('{to}', '${result['kept']}')),
    ));
    await _load();
  }

  /// Returned by a chooser to mean "let me type one".
  ///
  /// A sentinel rather than a nullable second return value, because the
  /// chooser already uses null for "cancelled" and the two must not collide --
  /// the same ambiguity that made a failed check look like permission to
  /// merge earlier in this file.
  static const _kTypeNew = '::type-a-new-one::';

  /// Put a village's mandal AND district right.
  ///
  /// The Owner, item 11: "enable user to select mandal, district (while user
  /// opts to select show available list and then option to add new if in
  /// future more split happens) which is correct if app fills it wrong or old
  /// data".
  ///
  /// BOTH, IN ONE SHEET, because they are one answer. The districts the
  /// directory lists DEPEND on the mandal, so correcting the mandal in one
  /// dialog and the district in the next would offer a district list
  /// belonging to the mandal that had just been replaced. Changing the mandal
  /// here re-asks for the districts, and drops the chosen district if the new
  /// mandal does not have it.
  ///
  /// On this book every village in Srikalahasti mandal is stored as Chittoor,
  /// which the mandal left in 2022 -- the app chose it by sort order and
  /// nothing ever said so.
  Future<void> _correct(ManaVillage v) async {
    var mandal = v.mandal;
    var district = v.district;

    var options = await _optionsFor(v, mandal);
    if (options == null || !mounted) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (c, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            ManaSpacing.lg,
            ManaSpacing.lg,
            ManaSpacing.lg,
            MediaQuery.of(c).viewInsets.bottom + ManaSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(v.name, style: ManaType.sheetTitle),
              const SizedBox(height: 2),
              ManaText.raw(
                ref.t('correct_place_note').replaceAll('{pin}', v.pinCode),
                style: ManaType.note,
              ),
              const SizedBox(height: ManaSpacing.md),
              _placeRow(ref.t('mandal_field'), mandal, () async {
                final picked = await _choosePlace(
                    ref.t('which_mandal'), options!.where((o) => o.isMandal));
                if (picked == null || !mounted) return;
                final refreshed = await _optionsFor(v, picked);
                if (refreshed == null) return;
                final stillThere = refreshed
                    .where((o) => !o.isMandal)
                    .any((o) => o.value == district);
                setSheetState(() {
                  mandal = picked;
                  options = refreshed;
                  if (!stillThere) district = '';
                });
              }),
              _placeRow(ref.t('district_field'), district, () async {
                final picked = await _choosePlace(
                    ref.t('which_district'), options!.where((o) => !o.isMandal));
                if (picked == null || !mounted) return;
                setSheetState(() => district = picked);
              }),
              const SizedBox(height: ManaSpacing.lg),
              // Wrap, not Row: Save and Cancel in Telugu at a 2.0x text scale
              // do not share a 360dp line.
              Wrap(
                spacing: ManaSpacing.sm,
                runSpacing: ManaSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    // Nothing to save is not a reason to disable. A button
                    // that does nothing and says nothing is the shape this
                    // project keeps having reported as broken; it closes.
                    onPressed: () => Navigator.of(sheetContext)
                        .pop(mandal.isNotEmpty && district.isNotEmpty),
                    child: ManaText.raw(ref.t('save')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: ManaText.raw(ref.t('cancel')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    // Nothing changed is not a write. It would still rewrite a row that every
    // book on this database shares.
    if (mandal == v.mandal && district == v.district) return;

    setState(() => _busyId = v.locationId);
    final result = await NetworkErrorHandler.run(
      context,
      () => ref.read(villageMergeApiServiceProvider).correctPlace(
            businessId: widget.businessId,
            locationId: v.locationId,
            mandal: mandal,
            district: district,
          ),
    );
    if (!mounted) return;
    setState(() => _busyId = null);
    if (result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(ref
          .t('district_corrected')
          .replaceAll('{village}', '${result['village']}')
          .replaceAll('{was}', '${result['was_district']}')
          .replaceAll('{now}', '${result['now_district']}')),
    ));
    await _load();
  }

  Future<List<ManaPlaceOption>?> _optionsFor(ManaVillage v, String mandal) =>
      NetworkErrorHandler.run(
        context,
        () => ref.read(villageMergeApiServiceProvider).placeOptions(
              businessId: widget.businessId,
              locationId: v.locationId,
              mandal: mandal,
            ),
      );

  Widget _placeRow(String label, String value, VoidCallback onTap) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: ManaText.raw(label, style: ManaType.fine),
        subtitle: ManaText.raw(
          value.isEmpty ? ref.t('profile_not_on_file') : value,
          style: ManaType.smallStrong,
        ),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: onTap,
      );

  /// One list, most-used first, with the option to type a name nobody has yet.
  Future<String?> _choosePlace(
      String title, Iterable<ManaPlaceOption> options) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: ManaText.raw(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: ManaText.raw(o.value),
                  subtitle: o.usedHere > 0
                      ? ManaText.raw(
                          ref
                              .t('already_used_here')
                              .replaceAll('{count}', '${o.usedHere}'),
                          style: ManaType.fine)
                      : null,
                  onTap: () => Navigator.of(c).pop(o.value),
                ),
              // "option to add new if in future more split happens" -- the
              // Owner's words. The directory is a snapshot: Andhra Pradesh
              // split its districts in 2022 and will again, and a book that
              // can only choose from last year's list has to wait for a data
              // refresh to record where its customers live.
              //
              // Whatever is typed shows up in the most-used list for the next
              // village, which is the "app creates it's & suggest the same in
              // next user search" half of the same sentence.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add, size: 18),
                title: ManaText.raw(ref.t('add_a_different_one')),
                onTap: () => Navigator.of(c).pop(_kTypeNew),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: ManaText.raw(ref.t('cancel')),
          ),
        ],
      ),
    );
    if (picked != _kTypeNew) return picked;
    if (!mounted) return null;
    return _typeOne(title);
  }

  Future<String?> _typeOne(String title) async {
    final controller = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: ManaText.raw(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (x) => Navigator.of(c).pop(x.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: ManaText.raw(ref.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(controller.text.trim()),
            child: ManaText.raw(ref.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    return (typed == null || typed.isEmpty) ? null : typed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('merge_villages')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                children: [
                  ManaText.raw(ref.t('merge_villages_note'),
                      style: ManaType.note),
                  const SizedBox(height: ManaSpacing.md),
                  if (_pairs.isEmpty)
                    ManaText.raw(ref.t('no_duplicate_villages'),
                        style: ManaType.secondary)
                  else
                    ...List.generate(
                        _pairs.length, (i) => _pairCard(_pairs[i], i)),
                  if (_villages.isNotEmpty) ...[
                    const SizedBox(height: ManaSpacing.lg),
                    ManaText.raw(ref.t('your_villages'), style: ManaType.strong),
                    ManaText.raw(ref.t('your_villages_note'),
                        style: ManaType.note),
                    const SizedBox(height: ManaSpacing.xs),
                    for (final v in _villages) _villageRow(v),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _pairCard(ManaVillageDuplicate p, int i) {
    final busy = _busyId == p.dropId;
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _side(ref.t('merge_keeps'), p.keepName, p.keepMandal,
                p.keepDistrict, p.keepPeople),
            const SizedBox(height: ManaSpacing.sm),
            // Wrap, not Row: two Telugu labels and a button do not share a
            // 360dp line at a 2.0x text scale.
            Wrap(
              spacing: ManaSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.arrow_downward,
                    size: 18, color: ManaColors.textSecondary),
                TextButton.icon(
                  onPressed: busy ? null : () => _swap(i),
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: ManaText.raw(ref.t('merge_swap')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            _side(ref.t('merge_drops'), p.dropName, p.dropMandal,
                p.dropDistrict, p.dropPeople),
            const SizedBox(height: ManaSpacing.md),
            if (p.isBlocked) ...[
              // SAID IN FULL, not reduced to a disabled button. The refusal is
              // something the Owner can act on -- put both villages in the
              // same area -- and a greyed-out control with no sentence beside
              // it reads as a broken screen.
              ManaText.raw(ref.t('merge_blocked'),
                  style: ManaType.smallStrong),
              const SizedBox(height: 2),
              ManaText.raw(p.blockedReason!, style: ManaType.note),
            ] else
              FilledButton(
                onPressed: busy ? null : () => _merge(p),
                child: busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ManaText.raw(ref.t('merge_villages')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _villageRow(ManaVillage v) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.place_outlined, color: ManaColors.brandDeep),
        title: ManaText.raw(v.name),
        subtitle: ManaText.raw(
          [v.mandal, v.district].where((x) => x.isNotEmpty).join(', '),
          style: ManaType.fine,
        ),
        trailing: _busyId == v.locationId
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.edit_outlined, size: 18),
        onTap: _busyId == null ? () => _correct(v) : null,
      );

  Widget _side(String label, String name, String mandal, String district,
          int people) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(label, style: ManaType.fine),
          ManaText.raw(name, style: ManaType.smallStrong),
          ManaText.raw(
            [mandal, district].where((s) => s.isNotEmpty).join(', '),
            style: ManaType.fine,
          ),
          ManaText.raw(
            ref.t('people_here').replaceAll('{count}', '$people'),
            style: ManaType.note,
          ),
        ],
      );
}
